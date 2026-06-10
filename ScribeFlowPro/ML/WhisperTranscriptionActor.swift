import Foundation
@preconcurrency import WhisperKit
import os

actor WhisperTranscriptionActor {
    static let logger = Logger(subsystem: "com.scribeflowpro", category: "Transcription")

    private let pipeline = WhisperPipeline()
    private(set) var isModelLoaded = false
    private(set) var loadedModelID: String?
    private var loadedModelFolder: URL?
    private var usesMLXWhisperBridge = false

    private let windowDuration: TimeInterval = 10.0
    private let sampleRate: Double = 16_000
    private var windowSamples: Int { Int(windowDuration * sampleRate) }

    // MARK: - Model Lifecycle

    func loadModel(modelID: String) async throws {
        let whisperModel = Self.mapToWhisperKitModel(modelID)
        let localModelFolder = ModelPathResolver.existingDirectory(for: modelID)

        if let localModelFolder, Self.isMLXWhisperDirectory(localModelFolder) {
            #if DEBUG
            FileHandle.standardError.write(Data("[SFP] Using MLX Whisper bridge for modelID=\(modelID) at \(localModelFolder.path)\n".utf8))
            #endif
            pipeline.kit = nil
            self.loadedModelFolder = localModelFolder
            self.usesMLXWhisperBridge = true
            self.isModelLoaded = true
            self.loadedModelID = modelID
            return
        }

        #if DEBUG
        FileHandle.standardError.write(Data("[SFP] Loading WhisperKit model=\(whisperModel) from modelID=\(modelID)\n".utf8))
        #endif

        do {
            let config = WhisperKitConfig(
                model: localModelFolder == nil ? whisperModel : nil,
                modelFolder: localModelFolder?.path,
                verbose: true,
                logLevel: .debug,
                prewarm: true,
                load: true,
                download: localModelFolder == nil
            )
            #if DEBUG
            FileHandle.standardError.write(Data("[SFP] Calling WhisperKit init...\n".utf8))
            #endif
            let kit = try await WhisperKit(config)
            pipeline.kit = kit
            self.loadedModelFolder = localModelFolder
            self.usesMLXWhisperBridge = false
            self.isModelLoaded = true
            self.loadedModelID = modelID
            #if DEBUG
            FileHandle.standardError.write(Data("[SFP] WhisperKit ready: \(whisperModel)\n".utf8))
            #endif
        } catch {
            #if DEBUG
            FileHandle.standardError.write(Data("[SFP] WhisperKit FAILED: \(error)\n".utf8))
            #endif
            throw TranscriptionError.modelLoadFailed(underlying: error)
        }
    }

    func unloadModel() {
        Self.logger.info("Unloading Whisper model")
        pipeline.kit = nil
        loadedModelFolder = nil
        usesMLXWhisperBridge = false
        isModelLoaded = false
        loadedModelID = nil
        Self.logger.info("Whisper model unloaded")
    }

    // MARK: - Transcription

    func transcribe(audioFileURL: URL) async throws -> [TranscriptChunk] {
        if usesMLXWhisperBridge {
            guard let modelFolder = loadedModelFolder else {
                throw TranscriptionError.noModelLoaded
            }
            return try Self.transcribeWithMLXWhisperBridge(audioFileURL: audioFileURL, modelFolder: modelFolder)
        }

        guard let kit = pipeline.kit else {
            throw TranscriptionError.noModelLoaded
        }

        let results = try await kit.transcribe(audioPath: audioFileURL.path)
        return Self.chunks(from: results, windowStartTime: 0)
    }

    func transcribe(audioStream: AsyncStream<AudioSamples>) -> AsyncStream<TranscriptChunk> {
        AsyncStream { continuation in
            Task {
                await self.runTranscription(audioStream: audioStream, continuation: continuation)
            }
        }
    }

    private func runTranscription(
        audioStream: AsyncStream<AudioSamples>,
        continuation: AsyncStream<TranscriptChunk>.Continuation
    ) async {
        guard let kit = pipeline.kit else {
            #if DEBUG
            FileHandle.standardError.write(Data("[SFP] runTranscription: no model!\n".utf8))
            #endif
            continuation.finish()
            return
        }

        #if DEBUG
        FileHandle.standardError.write(Data("[SFP] runTranscription started\n".utf8))
        #endif
        var sampleBuffer: [Float] = []
        sampleBuffer.reserveCapacity(windowSamples)
        var totalSamplesProcessed: Int = 0
        var chunkCount = 0

        for await audioSamples in audioStream {
            guard !Task.isCancelled else {
                #if DEBUG
                FileHandle.standardError.write(Data("[SFP] Task cancelled\n".utf8))
                #endif
                break
            }

            sampleBuffer.append(contentsOf: audioSamples.samples)
            chunkCount += 1
            #if DEBUG
            if chunkCount % 50 == 1 {
                FileHandle.standardError.write(Data("[SFP] Buffer: \(sampleBuffer.count)/\(windowSamples) samples (\(chunkCount) chunks)\n".utf8))
            }
            #endif

            // Process when we have a full window
            while sampleBuffer.count >= windowSamples {
                let windowData = Array(sampleBuffer.prefix(windowSamples))
                let windowStartTime = Double(totalSamplesProcessed) / sampleRate

                Self.logger.debug("Processing window at \(windowStartTime, format: .fixed(precision: 1))s")

                let signpostID = OSSignpostID(log: .default)
                os_signpost(.begin, log: .default, name: "WhisperInference", signpostID: signpostID)

                do {
                    #if DEBUG
                    FileHandle.standardError.write(Data("[SFP] Transcribing window at \(windowStartTime)s...\n".utf8))
                    #endif
                    let results: [TranscriptionResult] = try await kit.transcribe(audioArray: windowData)
                    #if DEBUG
                    FileHandle.standardError.write(Data("[SFP] Got \(results.count) results\n".utf8))
                    #endif
                    for result in results {
                        #if DEBUG
                        FileHandle.standardError.write(Data("[SFP] Result: \(result.segments.count) segments, text=\(result.text.prefix(80))\n".utf8))
                        #endif
                        for chunk in Self.chunks(from: [result], windowStartTime: windowStartTime) {
                            continuation.yield(chunk)
                        }
                    }
                } catch {
                    #if DEBUG
                    FileHandle.standardError.write(Data("[SFP] Window error: \(error)\n".utf8))
                    #endif
                }

                os_signpost(.end, log: .default, name: "WhisperInference", signpostID: signpostID)

                sampleBuffer.removeFirst(windowSamples)
                totalSamplesProcessed += windowSamples
            }
        }

        #if DEBUG
        FileHandle.standardError.write(Data("[SFP] Stream ended. Remaining buffer: \(sampleBuffer.count) samples\n".utf8))
        #endif

        // Process remaining audio (at least 1 second)
        if sampleBuffer.count > Int(sampleRate) {
            let windowStartTime = Double(totalSamplesProcessed) / sampleRate

            Self.logger.debug("Processing final \(sampleBuffer.count) samples")

            do {
                let results: [TranscriptionResult] = try await kit.transcribe(audioArray: sampleBuffer)
                for chunk in Self.chunks(from: results, windowStartTime: windowStartTime) {
                    continuation.yield(chunk)
                }
            } catch {
                Self.logger.error("Final transcription error: \(error.localizedDescription)")
            }
        }

        continuation.finish()
        Self.logger.info("Transcription stream completed")
    }

    // MARK: - Text Cleaning

    static func chunks(from results: [TranscriptionResult], windowStartTime: TimeInterval = 0) -> [TranscriptChunk] {
        results.flatMap { result in
            result.segments.compactMap { segment in
                let cleanedText = cleanWhisperText(segment.text)
                guard !cleanedText.isEmpty else { return nil }

                let confidence = min(1.0, max(0.0, exp(segment.avgLogprob)))
                return TranscriptChunk(
                    text: cleanedText,
                    startTime: windowStartTime + Double(segment.start),
                    endTime: windowStartTime + Double(segment.end),
                    confidence: confidence,
                    isFinal: true
                )
            }
        }
    }

    static func cleanWhisperText(_ text: String) -> String {
        // Strip Whisper control tokens: <|startoftranscript|>, <|en|>, <|transcribe|>, <|0.00|>, etc.
        text.replacingOccurrences(
            of: "<\\|[^|]*\\|>",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - MLX Whisper Bridge

    private struct MLXWhisperBridgeOutput: Decodable {
        struct Segment: Decodable {
            let text: String
            let start: Double
            let end: Double
            let confidence: Float?
        }
        let text: String?
        let segments: [Segment]?
        let error: String?
    }

    private static func isMLXWhisperDirectory(_ directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("weights.npz").path)
        || FileManager.default.fileExists(atPath: directory.appendingPathComponent("model.safetensors").path)
    }

    private static func transcribeWithMLXWhisperBridge(audioFileURL: URL, modelFolder: URL) throws -> [TranscriptChunk] {
        let bridge = try locateMLXWhisperBridge()
        let python = locateMLXWhisperPython()
        let process = Process()
        process.executableURL = python
        process.arguments = [
            bridge.path,
            "--model", modelFolder.path,
            "--audio", audioFileURL.path,
            "--language", "en"
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw TranscriptionError.inferenceError(underlying: error)
        }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "MLX Whisper bridge failed"
            throw TranscriptionError.inferenceError(underlying: BridgeError(message))
        }

        do {
            let decoded = try JSONDecoder().decode(MLXWhisperBridgeOutput.self, from: outputData)
            if let error = decoded.error {
                throw TranscriptionError.inferenceError(underlying: BridgeError(error))
            }
            let chunks = (decoded.segments ?? []).compactMap { segment -> TranscriptChunk? in
                let cleaned = cleanWhisperText(segment.text)
                guard !cleaned.isEmpty else { return nil }
                return TranscriptChunk(
                    text: cleaned,
                    startTime: segment.start,
                    endTime: segment.end,
                    confidence: segment.confidence ?? 0.8,
                    isFinal: true
                )
            }
            if !chunks.isEmpty { return chunks }
            let cleaned = cleanWhisperText(decoded.text ?? "")
            guard !cleaned.isEmpty else { return [] }
            return [TranscriptChunk(text: cleaned, startTime: 0, endTime: 0, confidence: 0.8, isFinal: true)]
        } catch let transcriptionError as TranscriptionError {
            throw transcriptionError
        } catch {
            let raw = String(data: outputData, encoding: .utf8) ?? ""
            throw TranscriptionError.inferenceError(underlying: BridgeError("Could not parse MLX Whisper output: \(raw)"))
        }
    }

    private static func locateMLXWhisperBridge() throws -> URL {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        let candidates: [URL] = [
            env["SFP_MLX_WHISPER_BRIDGE"].map(URL.init(fileURLWithPath:)),
            Bundle.main.resourceURL?.appendingPathComponent("Scripts/mlx_whisper_transcribe.py"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Scripts/mlx_whisper_transcribe.py")
        ].compactMap { $0 }
        if let match = candidates.first(where: { fm.fileExists(atPath: $0.path) }) {
            return match
        }
        throw TranscriptionError.inferenceError(underlying: BridgeError("MLX Whisper bridge script not found"))
    }

    private static func locateMLXWhisperPython() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let explicit = env["SFP_MLX_WHISPER_PYTHON"], !explicit.isEmpty {
            return URL(fileURLWithPath: explicit)
        }
        let appSupportVenv = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ScribeFlowPro/venv/bin/python")
        if FileManager.default.fileExists(atPath: appSupportVenv.path) {
            return appSupportVenv
        }
        let repoVenv = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".venv-smoke/bin/python")
        if FileManager.default.fileExists(atPath: repoVenv.path) {
            return repoVenv
        }
        return URL(fileURLWithPath: "/usr/bin/python3")
    }

    private struct BridgeError: Error, LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    // MARK: - Model Mapping

    private static func mapToWhisperKitModel(_ modelID: String) -> String {
        let id = modelID.lowercased()
        if id.contains("large") && id.contains("turbo") {
            return "openai_whisper-large-v3_turbo"
        } else if id.contains("large") {
            return "openai_whisper-large-v3"
        } else if id.contains("medium") && id.contains("en") {
            return "openai_whisper-medium.en"
        } else if id.contains("medium") {
            return "openai_whisper-medium"
        } else if id.contains("small") && id.contains("en") {
            return "openai_whisper-small.en"
        } else if id.contains("small") {
            return "openai_whisper-small"
        } else if id.contains("base") {
            return "openai_whisper-base"
        } else if id.contains("tiny") {
            return "openai_whisper-tiny"
        }
        return "openai_whisper-medium"
    }
}

// Thread-safe wrapper for WhisperKit (not Sendable)
private final class WhisperPipeline: @unchecked Sendable {
    var kit: WhisperKit?
}
