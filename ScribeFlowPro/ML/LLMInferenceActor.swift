import Foundation
import MLX
import MLXNN
import MLXRandom
import Tokenizers
import os

actor LLMInferenceActor {
    static let logger = Logger(subsystem: "com.scribeflowpro", category: "LLMInference")

    private var weights: [String: MLXArray] = [:]
    private var tokenizer: Tokenizer?
    private var config: LLMConfig?

    private(set) var isModelLoaded = false
    private(set) var loadedModelID: String?
    private(set) var contextWindowSize: Int = 0

    // MARK: - Model Lifecycle

    func loadModel(modelID: String) async throws {
        // Unload previous model first
        if isModelLoaded {
            unloadModel()
        }

        let modelsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Models", isDirectory: true)
        let modelPath = modelsDir.appendingPathComponent(modelID, isDirectory: true)

        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw LLMError.modelNotFound(modelID: modelID)
        }

        Self.logger.info("Loading LLM from: \(modelPath.path)")

        // Load config.json
        let configURL = modelPath.appendingPathComponent("config.json")
        guard let configData = try? Data(contentsOf: configURL),
              let configDict = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
            throw LLMError.unsupportedModelFormat
        }

        let loadedConfig = LLMConfig(from: configDict)
        self.config = loadedConfig
        self.contextWindowSize = loadedConfig.maxPositionEmbeddings

        // Load weights from safetensors
        do {
            let files = try FileManager.default.contentsOfDirectory(at: modelPath, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "safetensors" }

            guard !files.isEmpty else {
                throw LLMError.unsupportedModelFormat
            }

            for file in files {
                let loaded = try MLX.loadArrays(url: file)
                for (key, value) in loaded {
                    weights[key] = value
                }
            }
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.modelLoadFailed(underlying: error)
        }

        // Load tokenizer from local model folder
        do {
            self.tokenizer = try await AutoTokenizer.from(modelFolder: modelPath)
        } catch {
            Self.logger.warning("Failed to load tokenizer: \(error.localizedDescription)")
        }

        isModelLoaded = true
        loadedModelID = modelID

        Self.logger.info("LLM loaded: \(modelID), context window: \(loadedConfig.maxPositionEmbeddings)")
    }

    func unloadModel() {
        Self.logger.info("Unloading LLM")
        weights.removeAll()
        tokenizer = nil
        config = nil
        isModelLoaded = false
        loadedModelID = nil
        contextWindowSize = 0
        MLX.Memory.cacheLimit = 0
        Self.logger.info("LLM unloaded")
    }

    // MARK: - Token Count

    func tokenCount(for text: String) -> Int {
        guard let tokenizer else { return text.count / 4 } // rough estimate fallback
        let encoded = tokenizer.encode(text: text)
        return encoded.count
    }

    // MARK: - Generation

    func generate(
        prompt: String,
        maxTokens: Int = 2048,
        temperature: Float = 0.3,
        stopSequences: [String] = []
    ) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                await self.runGeneration(
                    prompt: prompt,
                    maxTokens: maxTokens,
                    temperature: temperature,
                    stopSequences: stopSequences,
                    continuation: continuation
                )
            }
        }
    }

    private func runGeneration(
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        stopSequences: [String],
        continuation: AsyncStream<String>.Continuation
    ) async {
        guard isModelLoaded, !weights.isEmpty else {
            Self.logger.error("Generate called without loaded model")
            continuation.finish()
            return
        }

        guard let config else {
            continuation.finish()
            return
        }

        // Tokenize prompt
        guard let tokenizer else {
            Self.logger.error("No tokenizer available")
            continuation.finish()
            return
        }
        let promptTokens = tokenizer.encode(text: prompt)

        if promptTokens.count > self.contextWindowSize {
            Self.logger.error("Prompt exceeds context window: \(promptTokens.count) > \(self.contextWindowSize)")
            continuation.finish()
            return
        }

        Self.logger.info("Generating: prompt=\(promptTokens.count) tokens, maxTokens=\(maxTokens)")

        let signpostID = OSSignpostID(log: .default)
        os_signpost(.begin, log: .default, name: "LLMGeneration", signpostID: signpostID)

        var tokens = promptTokens
        var generatedText = ""
        var generatedCount = 0

        for _ in 0..<maxTokens {
            guard !Task.isCancelled else {
                Self.logger.info("Generation cancelled")
                break
            }

            // Build input embedding
            guard let embedW = weights["model.embed_tokens.weight"] ?? weights["model.decoder.embed_tokens.weight"] else {
                break
            }

            let inputIDs = MLXArray(tokens.suffix(self.contextWindowSize).map { Int32($0) })
            var hidden = embedW[inputIDs].reshaped([1, inputIDs.dim(0), -1])

            // Run through transformer layers
            for i in 0..<config.numHiddenLayers {
                let prefix = "model.layers.\(i)"
                guard weights["\(prefix).self_attn.q_proj.weight"] != nil else { break }
                hidden = runTransformerLayer(hidden, layerPrefix: prefix, config: config)
            }

            // Layer norm
            if let normW = weights["model.norm.weight"] {
                hidden = rmsNorm(hidden, weight: normW, eps: config.rmsNormEps)
            }

            // Project to vocab — use last position only
            let lastHidden = hidden[0..., (hidden.dim(1) - 1)..., 0...]
            let logits: MLXArray
            if let lmHead = weights["lm_head.weight"] {
                logits = MLX.matmul(lastHidden, lmHead.T)
            } else {
                logits = MLX.matmul(lastHidden, embedW.T)
            }

            // Sample or greedy
            let nextToken: Int
            if temperature < 0.01 {
                nextToken = Int(MLX.argMax(logits, axis: -1).item(Int32.self))
            } else {
                let scaledLogits = logits / temperature
                let probs = softmax(scaledLogits, axis: -1)
                let sampled = MLXRandom.categorical(MLX.log(probs))
                nextToken = Int(sampled.item(Int32.self))
            }

            // EOS check
            let eosTokenID = config.eosTokenID
            if nextToken == eosTokenID { break }

            tokens.append(nextToken)
            generatedCount += 1

            // Decode token to text
            let tokenText = tokenizer.decode(tokens: [nextToken])
            generatedText += tokenText
            continuation.yield(tokenText)

            // Stop sequence check
            for stopSeq in stopSequences {
                if generatedText.hasSuffix(stopSeq) {
                    Self.logger.info("Stop sequence matched: \(stopSeq)")
                    os_signpost(.end, log: .default, name: "LLMGeneration", signpostID: signpostID)
                    continuation.finish()
                    return
                }
            }
        }

        os_signpost(.end, log: .default, name: "LLMGeneration", signpostID: signpostID)
        Self.logger.info("Generated \(generatedCount) tokens")
        continuation.finish()
    }

    // MARK: - Transformer

    private func runTransformerLayer(
        _ input: MLXArray,
        layerPrefix: String,
        config: LLMConfig
    ) -> MLXArray {
        var x = input

        // Pre-attention RMS norm
        if let normW = weights["\(layerPrefix).input_layernorm.weight"] {
            let normed = rmsNorm(x, weight: normW, eps: config.rmsNormEps)

            // Self-attention
            if let qW = weights["\(layerPrefix).self_attn.q_proj.weight"],
               let kW = weights["\(layerPrefix).self_attn.k_proj.weight"],
               let vW = weights["\(layerPrefix).self_attn.v_proj.weight"],
               let oW = weights["\(layerPrefix).self_attn.o_proj.weight"] {

                let q = MLX.matmul(normed, qW.T)
                let k = MLX.matmul(normed, kW.T)
                let v = MLX.matmul(normed, vW.T)

                let scale = Float(1.0 / sqrt(Double(config.headDim)))
                var scores = MLX.matmul(q, k.T) * scale

                // Causal mask
                let seqLen = normed.dim(1)
                if seqLen > 1 {
                    let mask = MLX.triu(MLXArray.ones([seqLen, seqLen]) * Float(-1e9), k: 1)
                    scores = scores + mask
                }

                let attnWeights = softmax(scores, axis: -1)
                let attnOut = MLX.matmul(attnWeights, v)
                x = x + MLX.matmul(attnOut, oW.T)
            }
        }

        // Post-attention RMS norm + FFN
        if let normW = weights["\(layerPrefix).post_attention_layernorm.weight"] {
            let normed = rmsNorm(x, weight: normW, eps: config.rmsNormEps)

            if let gateW = weights["\(layerPrefix).mlp.gate_proj.weight"],
               let upW = weights["\(layerPrefix).mlp.up_proj.weight"],
               let downW = weights["\(layerPrefix).mlp.down_proj.weight"] {
                let gate = MLX.matmul(normed, gateW.T)
                let up = MLX.matmul(normed, upW.T)
                let ffnOut = MLX.matmul(silu(gate) * up, downW.T)
                x = x + ffnOut
            }
        }

        return x
    }

    private func rmsNorm(_ x: MLXArray, weight: MLXArray, eps: Float) -> MLXArray {
        let variance = MLX.mean(x * x, axis: -1, keepDims: true)
        let normed = x * MLX.rsqrt(variance + eps)
        return normed * weight
    }

    private func silu(_ x: MLXArray) -> MLXArray {
        x * sigmoid(x)
    }
}

// MARK: - Config

struct LLMConfig {
    let vocabSize: Int
    let hiddenSize: Int
    let numHiddenLayers: Int
    let numAttentionHeads: Int
    let numKeyValueHeads: Int
    let intermediateSize: Int
    let maxPositionEmbeddings: Int
    let rmsNormEps: Float
    let eosTokenID: Int
    let headDim: Int

    init(from dict: [String: Any]) {
        vocabSize = dict["vocab_size"] as? Int ?? 32000
        hiddenSize = dict["hidden_size"] as? Int ?? 4096
        numHiddenLayers = dict["num_hidden_layers"] as? Int ?? 32
        numAttentionHeads = dict["num_attention_heads"] as? Int ?? 32
        numKeyValueHeads = dict["num_key_value_heads"] as? Int ?? numAttentionHeads
        intermediateSize = dict["intermediate_size"] as? Int ?? 11008
        maxPositionEmbeddings = dict["max_position_embeddings"] as? Int ?? 4096
        rmsNormEps = Float(dict["rms_norm_eps"] as? Double ?? 1e-5)
        eosTokenID = dict["eos_token_id"] as? Int ?? 2
        headDim = hiddenSize / numAttentionHeads
    }
}
