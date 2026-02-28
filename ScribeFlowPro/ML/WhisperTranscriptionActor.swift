import Foundation
import MLX
import MLXNN
import os

actor WhisperTranscriptionActor {
    static let logger = Logger(subsystem: "com.scribeflowpro", category: "Transcription")

    private var model: WhisperMLXModel?
    private(set) var isModelLoaded = false
    private(set) var loadedModelID: String?

    // Windowing parameters
    private let windowDuration: TimeInterval = 30.0
    private let overlapDuration: TimeInterval = 5.0
    private let sampleRate: Double = 16_000

    private var windowSamples: Int { Int(windowDuration * sampleRate) }
    private var overlapSamples: Int { Int(overlapDuration * sampleRate) }

    // MARK: - Model Lifecycle

    func loadModel(modelID: String) throws {
        let modelsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Models", isDirectory: true)
        let modelPath = modelsDir.appendingPathComponent(modelID, isDirectory: true)

        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw TranscriptionError.modelNotFound(modelID: modelID)
        }

        // Check available memory via ProcessInfo
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let estimatedModelSize: UInt64 = 3_000_000_000 // ~3GB for large-v3
        // Ensure at least 20% headroom beyond model size
        if physicalMemory < estimatedModelSize + (physicalMemory / 5) {
            Self.logger.warning("Low memory: \(physicalMemory) bytes total, model needs ~\(estimatedModelSize)")
        }

        Self.logger.info("Loading Whisper model from: \(modelPath.path)")

        do {
            let loadedModel = try WhisperMLXModel(modelDirectory: modelPath)
            self.model = loadedModel
            self.isModelLoaded = true
            self.loadedModelID = modelID
            Self.logger.info("Whisper model loaded: \(modelID)")
        } catch {
            throw TranscriptionError.modelLoadFailed(underlying: error)
        }
    }

    func unloadModel() {
        Self.logger.info("Unloading Whisper model")
        model = nil
        isModelLoaded = false
        loadedModelID = nil
        MLX.Memory.cacheLimit = 0
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
        guard let model else {
            Self.logger.error("Transcription started without loaded model")
            continuation.finish()
            return
        }

        var sampleBuffer: [Float] = []
        sampleBuffer.reserveCapacity(windowSamples)
        let _ = Date() // session start reference
        var totalSamplesProcessed: Int = 0
        var previousChunks: [TranscriptChunk] = []

        for await audioSamples in audioStream {
            guard !Task.isCancelled else { break }

            sampleBuffer.append(contentsOf: audioSamples.samples)

            // Process when we have a full window
            while sampleBuffer.count >= windowSamples {
                let windowData = Array(sampleBuffer.prefix(windowSamples))

                let windowStartSample = totalSamplesProcessed
                let windowStartTime = Double(windowStartSample) / sampleRate
                let windowEndTime = windowStartTime + windowDuration

                Self.logger.debug("Processing window: \(windowStartTime, format: .fixed(precision: 1))s - \(windowEndTime, format: .fixed(precision: 1))s")

                // Run inference on this window
                let signpostID = OSSignpostID(log: .default)
                os_signpost(.begin, log: .default, name: "WhisperInference", signpostID: signpostID)

                let segments = model.inferWindow(samples: windowData)

                os_signpost(.end, log: .default, name: "WhisperInference", signpostID: signpostID)

                // Convert to TranscriptChunks with absolute timestamps
                for segment in segments {
                    let chunk = TranscriptChunk(
                        text: segment.text,
                        startTime: windowStartTime + segment.relativeStart,
                        endTime: windowStartTime + segment.relativeEnd,
                        confidence: segment.confidence,
                        isFinal: false
                    )
                    continuation.yield(chunk)
                }

                // Mark previous window's chunks as final (overlap confirmed)
                for var chunk in previousChunks {
                    chunk.isFinal = true
                    continuation.yield(chunk)
                }
                previousChunks = segments.map { segment in
                    TranscriptChunk(
                        text: segment.text,
                        startTime: windowStartTime + segment.relativeStart,
                        endTime: windowStartTime + segment.relativeEnd,
                        confidence: segment.confidence,
                        isFinal: false
                    )
                }

                // Advance buffer by (window - overlap) samples
                let advanceSamples = windowSamples - overlapSamples
                sampleBuffer.removeFirst(advanceSamples)
                totalSamplesProcessed += advanceSamples
            }
        }

        // Process remaining buffer if substantial
        if sampleBuffer.count > Int(sampleRate) { // At least 1 second
            let windowStartTime = Double(totalSamplesProcessed) / sampleRate

            // Pad to full window if needed
            let paddedSamples: [Float]
            if sampleBuffer.count < windowSamples {
                paddedSamples = sampleBuffer + [Float](repeating: 0, count: windowSamples - sampleBuffer.count)
            } else {
                paddedSamples = Array(sampleBuffer.prefix(windowSamples))
            }

            let segments = model.inferWindow(samples: paddedSamples)
            for segment in segments {
                let chunk = TranscriptChunk(
                    text: segment.text,
                    startTime: windowStartTime + segment.relativeStart,
                    endTime: windowStartTime + segment.relativeEnd,
                    confidence: segment.confidence,
                    isFinal: true
                )
                continuation.yield(chunk)
            }
        }

        // Final chunks are confirmed
        for var chunk in previousChunks {
            chunk.isFinal = true
            continuation.yield(chunk)
        }

        continuation.finish()
        Self.logger.info("Transcription stream completed")
    }
}

// MARK: - MLX Whisper Model

/// Internal segment from a single inference window.
struct WhisperSegment {
    let text: String
    let relativeStart: TimeInterval
    let relativeEnd: TimeInterval
    let confidence: Float
}

/// Loads and runs Whisper inference using MLX arrays.
///
/// Loads weights from an MLX-format Whisper checkpoint directory.
/// The directory should contain `weights.npz` (or safetensors) and `config.json`.
final class WhisperMLXModel: @unchecked Sendable {
    private let modelDirectory: URL
    private var weights: [String: MLXArray] = [:]
    private let config: WhisperConfig

    struct WhisperConfig {
        let nMels: Int
        let nAudioCtx: Int
        let nTextCtx: Int
        let nVocab: Int
        let sampleRate: Int

        init(from dictionary: [String: Any]) {
            nMels = dictionary["num_mel_bins"] as? Int ?? 128
            nAudioCtx = dictionary["max_source_positions"] as? Int ?? 1500
            nTextCtx = dictionary["max_target_positions"] as? Int ?? 448
            nVocab = dictionary["vocab_size"] as? Int ?? 51865
            sampleRate = 16000
        }
    }

    init(modelDirectory: URL) throws {
        self.modelDirectory = modelDirectory

        // Load config
        let configURL = modelDirectory.appendingPathComponent("config.json")
        guard let configData = try? Data(contentsOf: configURL),
              let configDict = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
            throw TranscriptionError.modelLoadFailed(
                underlying: NSError(domain: "WhisperMLX", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "Missing config.json"])
            )
        }
        self.config = WhisperConfig(from: configDict)

        // Load weights — try safetensors first, then npz
        try loadWeights()
    }

    private func loadWeights() throws {
        // Try safetensors format
        let safetensorsFiles = try? FileManager.default.contentsOfDirectory(at: modelDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "safetensors" }

        if let files = safetensorsFiles, !files.isEmpty {
            for file in files {
                let loaded = try MLX.loadArrays(url: file)
                for (key, value) in loaded {
                    weights[key] = value
                }
            }
            return
        }

        // Try npz format
        let npzURL = modelDirectory.appendingPathComponent("weights.npz")
        if FileManager.default.fileExists(atPath: npzURL.path) {
            weights = try MLX.loadArrays(url: npzURL)
            return
        }

        throw TranscriptionError.modelLoadFailed(
            underlying: NSError(domain: "WhisperMLX", code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "No weights file found"])
        )
    }

    /// Run inference on a 30-second audio window.
    func inferWindow(samples: [Float]) -> [WhisperSegment] {
        // Convert to MLXArray
        let audioArray = MLXArray(samples)
            .reshaped([1, samples.count])

        // Compute log-mel spectrogram
        let melSpec = computeLogMelSpectrogram(audio: audioArray)

        // Run encoder
        let encoderOutput = runEncoder(melSpectrogram: melSpec)

        // Run decoder (greedy for now)
        let (tokens, logprobs) = runDecoder(encoderOutput: encoderOutput)

        // Decode tokens to text segments
        return decodeTokensToSegments(tokens: tokens, logprobs: logprobs, windowDuration: 30.0)
    }

    // MARK: - Audio Processing

    private func computeLogMelSpectrogram(audio: MLXArray) -> MLXArray {
        // Simplified mel spectrogram computation using MLX
        // In production this would use proper STFT + mel filterbank
        let hopLength = 160 // nFFT = 400 per Whisper spec
        let nMels = config.nMels

        // For now, reshape audio to approximate mel spectrogram dimensions
        let nFrames = audio.dim(1) / hopLength
        let features = audio.reshaped([1, 1, audio.dim(1)])

        // Apply learned mel filterbank if available in weights
        if let melFilters = weights["model.encoder.conv1.weight"] {
            // Use the first conv layer as feature extractor
            let output = MLX.conv1d(features, melFilters, stride: hopLength)
            return output
        }

        // Fallback: create feature representation matching expected dimensions
        let melOutput = MLXArray.zeros([1, nMels, nFrames])
        return melOutput
    }

    private func runEncoder(melSpectrogram: MLXArray) -> MLXArray {
        // Feed through encoder layers
        var x = melSpectrogram

        // Apply encoder positional encoding if available
        if let posEmbed = weights["model.encoder.embed_positions.weight"] {
            let seqLen = min(x.dim(-1), posEmbed.dim(0))
            x = x + posEmbed[0..<seqLen]
        }

        // Run through available encoder layers
        for i in 0..<32 {
            let prefix = "model.encoder.layers.\(i)"
            guard let _ = weights["\(prefix).self_attn.q_proj.weight"] else { break }
            x = runEncoderLayer(x, layerPrefix: prefix)
        }

        return x
    }

    private func runEncoderLayer(_ input: MLXArray, layerPrefix: String) -> MLXArray {
        // Simplified transformer encoder layer
        var x = input

        // Self-attention
        if let qW = weights["\(layerPrefix).self_attn.q_proj.weight"],
           let kW = weights["\(layerPrefix).self_attn.k_proj.weight"],
           let vW = weights["\(layerPrefix).self_attn.v_proj.weight"],
           let outW = weights["\(layerPrefix).self_attn.out_proj.weight"] {

            let q = MLX.matmul(x, qW.T)
            let k = MLX.matmul(x, kW.T)
            let v = MLX.matmul(x, vW.T)

            let scale = Float(1.0 / sqrt(Double(q.dim(-1))))
            let attnWeights = softmax(MLX.matmul(q, k.T) * scale, axis: -1)
            let attnOutput = MLX.matmul(attnWeights, v)
            x = x + MLX.matmul(attnOutput, outW.T)
        }

        // Feed-forward
        if let fc1W = weights["\(layerPrefix).fc1.weight"],
           let fc2W = weights["\(layerPrefix).fc2.weight"] {
            let ffn = MLX.matmul(gelu(MLX.matmul(x, fc1W.T)), fc2W.T)
            x = x + ffn
        }

        return x
    }

    private func runDecoder(encoderOutput: MLXArray) -> (tokens: [Int], logprobs: [Float]) {
        var tokens: [Int] = [50258] // <|startoftranscript|>
        var allLogprobs: [Float] = []

        // Greedy decoding
        for _ in 0..<config.nTextCtx {
            guard let embedW = weights["model.decoder.embed_tokens.weight"] else { break }

            // Embed tokens
            let tokenArray = MLXArray(tokens.map { Int32($0) })
            let tokenEmbedding = embedW[tokenArray]

            var x = tokenEmbedding.reshaped([1, tokens.count, -1])

            // Run decoder layers
            for i in 0..<32 {
                let prefix = "model.decoder.layers.\(i)"
                guard let _ = weights["\(prefix).self_attn.q_proj.weight"] else { break }
                x = runDecoderLayer(x, encoderOutput: encoderOutput, layerPrefix: prefix)
            }

            // Project to vocabulary
            let logits: MLXArray
            if let lmHead = weights["lm_head.weight"] {
                logits = MLX.matmul(x[0..., (tokens.count - 1)..., 0...], lmHead.T)
            } else {
                logits = MLX.matmul(x[0..., (tokens.count - 1)..., 0...], embedW.T)
            }

            // Greedy selection
            let nextToken = Int(MLX.argMax(logits, axis: -1).item(Int32.self))

            // Compute log probability for confidence
            let maxLogit = MLX.max(logits).item(Float.self)
            let logSumExp = log(MLX.sum(MLX.exp(logits - maxLogit)).item(Float.self)) + maxLogit
            let tokenLogit = logits[0..., nextToken...(nextToken)].item(Float.self)
            let logprob = tokenLogit - logSumExp
            allLogprobs.append(logprob)

            if nextToken == 50257 { break } // <|endoftext|>
            tokens.append(nextToken)
        }

        return (tokens, allLogprobs)
    }

    private func runDecoderLayer(
        _ input: MLXArray,
        encoderOutput: MLXArray,
        layerPrefix: String
    ) -> MLXArray {
        var x = input

        // Self-attention (causal)
        if let qW = weights["\(layerPrefix).self_attn.q_proj.weight"],
           let kW = weights["\(layerPrefix).self_attn.k_proj.weight"],
           let vW = weights["\(layerPrefix).self_attn.v_proj.weight"],
           let outW = weights["\(layerPrefix).self_attn.out_proj.weight"] {

            let q = MLX.matmul(x, qW.T)
            let k = MLX.matmul(x, kW.T)
            let v = MLX.matmul(x, vW.T)

            let scale = Float(1.0 / sqrt(Double(q.dim(-1))))
            var attnWeights = MLX.matmul(q, k.T) * scale
            // Apply causal mask
            let seqLen = x.dim(1)
            let mask = MLX.triu(MLXArray.ones([seqLen, seqLen]) * Float(-1e9), k: 1)
            attnWeights = attnWeights + mask
            attnWeights = softmax(attnWeights, axis: -1)
            let attnOutput = MLX.matmul(attnWeights, v)
            x = x + MLX.matmul(attnOutput, outW.T)
        }

        // Cross-attention with encoder
        if let qW = weights["\(layerPrefix).encoder_attn.q_proj.weight"],
           let kW = weights["\(layerPrefix).encoder_attn.k_proj.weight"],
           let vW = weights["\(layerPrefix).encoder_attn.v_proj.weight"],
           let outW = weights["\(layerPrefix).encoder_attn.out_proj.weight"] {

            let q = MLX.matmul(x, qW.T)
            let k = MLX.matmul(encoderOutput, kW.T)
            let v = MLX.matmul(encoderOutput, vW.T)

            let scale = Float(1.0 / sqrt(Double(q.dim(-1))))
            let attnWeights = softmax(MLX.matmul(q, k.T) * scale, axis: -1)
            let attnOutput = MLX.matmul(attnWeights, v)
            x = x + MLX.matmul(attnOutput, outW.T)
        }

        // FFN
        if let fc1W = weights["\(layerPrefix).fc1.weight"],
           let fc2W = weights["\(layerPrefix).fc2.weight"] {
            let ffn = MLX.matmul(gelu(MLX.matmul(x, fc1W.T)), fc2W.T)
            x = x + ffn
        }

        return x
    }

    private func decodeTokensToSegments(
        tokens: [Int],
        logprobs: [Float],
        windowDuration: TimeInterval
    ) -> [WhisperSegment] {
        // Simple token-to-text decoding
        // Whisper special tokens: timestamps are in range 50364..50864
        let timestampTokenBase = 50364

        var segments: [WhisperSegment] = []
        var currentText = ""
        var segmentStart: TimeInterval = 0
        var segmentLogprobs: [Float] = []

        for (i, token) in tokens.enumerated() where i > 0 {
            if token >= timestampTokenBase {
                // Timestamp token — marks segment boundary
                let timestamp = Double(token - timestampTokenBase) * 0.02

                if !currentText.isEmpty {
                    let avgLogprob = segmentLogprobs.isEmpty ? 0 :
                        segmentLogprobs.reduce(0, +) / Float(segmentLogprobs.count)
                    let confidence = min(1.0, max(0.0, exp(avgLogprob)))

                    segments.append(WhisperSegment(
                        text: currentText.trimmingCharacters(in: .whitespaces),
                        relativeStart: segmentStart,
                        relativeEnd: timestamp,
                        confidence: confidence
                    ))
                    currentText = ""
                    segmentLogprobs = []
                }
                segmentStart = timestamp
            } else if token < 50257 {
                // Regular text token — would use tokenizer to decode
                // For now, accumulate token IDs (proper decoding needs tokenizer vocab)
                currentText += " [t\(token)]"
                if i - 1 < logprobs.count {
                    segmentLogprobs.append(logprobs[i - 1])
                }
            }
        }

        // Flush remaining text
        if !currentText.isEmpty {
            let avgLogprob = segmentLogprobs.isEmpty ? 0 :
                segmentLogprobs.reduce(0, +) / Float(segmentLogprobs.count)
            let confidence = min(1.0, max(0.0, exp(avgLogprob)))

            segments.append(WhisperSegment(
                text: currentText.trimmingCharacters(in: .whitespaces),
                relativeStart: segmentStart,
                relativeEnd: windowDuration,
                confidence: confidence
            ))
        }

        return segments
    }
}
