import Foundation
import WhisperKit
import os

actor WhisperTranscriptionActor {
    static let logger = Logger(subsystem: "com.scribeflowpro", category: "Transcription")

    private let pipeline = WhisperPipeline()
    private(set) var isModelLoaded = false
    private(set) var loadedModelID: String?

    private let windowDuration: TimeInterval = 10.0
    private let sampleRate: Double = 16_000
    private var windowSamples: Int { Int(windowDuration * sampleRate) }

    // MARK: - Model Lifecycle

    func loadModel(modelID: String) async throws {
        let whisperModel = Self.mapToWhisperKitModel(modelID)
        FileHandle.standardError.write(Data("[SFP] Loading WhisperKit model=\(whisperModel) from modelID=\(modelID)\n".utf8))

        do {
            let config = WhisperKitConfig(
                model: whisperModel,
                verbose: true,
                logLevel: .debug,
                prewarm: true,
                load: true,
                download: true
            )
            FileHandle.standardError.write(Data("[SFP] Calling WhisperKit init...\n".utf8))
            let kit = try await WhisperKit(config)
            pipeline.kit = kit
            self.isModelLoaded = true
            self.loadedModelID = modelID
            FileHandle.standardError.write(Data("[SFP] WhisperKit ready: \(whisperModel)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("[SFP] WhisperKit FAILED: \(error)\n".utf8))
            throw TranscriptionError.modelLoadFailed(underlying: error)
        }
    }

    func unloadModel() {
        Self.logger.info("Unloading Whisper model")
        pipeline.kit = nil
        isModelLoaded = false
        loadedModelID = nil
        Self.logger.info("Whisper model unloaded")
    }

    // MARK: - Transcription

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
            FileHandle.standardError.write(Data("[SFP] runTranscription: no model!\n".utf8))
            continuation.finish()
            return
        }

        FileHandle.standardError.write(Data("[SFP] runTranscription started\n".utf8))
        var sampleBuffer: [Float] = []
        sampleBuffer.reserveCapacity(windowSamples)
        var totalSamplesProcessed: Int = 0
        var chunkCount = 0

        for await audioSamples in audioStream {
            guard !Task.isCancelled else {
                FileHandle.standardError.write(Data("[SFP] Task cancelled\n".utf8))
                break
            }

            sampleBuffer.append(contentsOf: audioSamples.samples)
            chunkCount += 1
            if chunkCount % 50 == 1 {
                FileHandle.standardError.write(Data("[SFP] Buffer: \(sampleBuffer.count)/\(windowSamples) samples (\(chunkCount) chunks)\n".utf8))
            }

            // Process when we have a full window
            while sampleBuffer.count >= windowSamples {
                let windowData = Array(sampleBuffer.prefix(windowSamples))
                let windowStartTime = Double(totalSamplesProcessed) / sampleRate

                Self.logger.debug("Processing window at \(windowStartTime, format: .fixed(precision: 1))s")

                let signpostID = OSSignpostID(log: .default)
                os_signpost(.begin, log: .default, name: "WhisperInference", signpostID: signpostID)

                do {
                    FileHandle.standardError.write(Data("[SFP] Transcribing window at \(windowStartTime)s...\n".utf8))
                    let results: [TranscriptionResult] = try await kit.transcribe(audioArray: windowData)
                    FileHandle.standardError.write(Data("[SFP] Got \(results.count) results\n".utf8))
                    for result in results {
                        FileHandle.standardError.write(Data("[SFP] Result: \(result.segments.count) segments, text=\(result.text.prefix(80))\n".utf8))
                        for segment in result.segments {
                            let confidence = min(1.0, max(0.0, exp(segment.avgLogprob)))
                            let cleanedText = Self.cleanWhisperText(segment.text)
                            guard !cleanedText.isEmpty else { continue }
                            let chunk = TranscriptChunk(
                                text: cleanedText,
                                startTime: windowStartTime + Double(segment.start),
                                endTime: windowStartTime + Double(segment.end),
                                confidence: confidence,
                                isFinal: true
                            )
                            continuation.yield(chunk)
                        }
                    }
                } catch {
                    FileHandle.standardError.write(Data("[SFP] Window error: \(error)\n".utf8))
                }

                os_signpost(.end, log: .default, name: "WhisperInference", signpostID: signpostID)

                sampleBuffer.removeFirst(windowSamples)
                totalSamplesProcessed += windowSamples
            }
        }

        FileHandle.standardError.write(Data("[SFP] Stream ended. Remaining buffer: \(sampleBuffer.count) samples\n".utf8))

        // Process remaining audio (at least 1 second)
        if sampleBuffer.count > Int(sampleRate) {
            let windowStartTime = Double(totalSamplesProcessed) / sampleRate

            Self.logger.debug("Processing final \(sampleBuffer.count) samples")

            do {
                let results: [TranscriptionResult] = try await kit.transcribe(audioArray: sampleBuffer)
                for result in results {
                    for segment in result.segments {
                        let confidence = min(1.0, max(0.0, exp(segment.avgLogprob)))
                        let chunk = TranscriptChunk(
                            text: segment.text,
                            startTime: windowStartTime + Double(segment.start),
                            endTime: windowStartTime + Double(segment.end),
                            confidence: confidence,
                            isFinal: true
                        )
                        continuation.yield(chunk)
                    }
                }
            } catch {
                Self.logger.error("Final transcription error: \(error.localizedDescription)")
            }
        }

        continuation.finish()
        Self.logger.info("Transcription stream completed")
    }

    // MARK: - Text Cleaning

    private static func cleanWhisperText(_ text: String) -> String {
        // Strip Whisper control tokens: <|startoftranscript|>, <|en|>, <|transcribe|>, <|0.00|>, etc.
        text.replacingOccurrences(
            of: "<\\|[^|]*\\|>",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
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
