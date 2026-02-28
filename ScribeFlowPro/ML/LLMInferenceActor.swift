import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import os

actor LLMInferenceActor {
    static let logger = Logger(subsystem: "com.scribeflowpro", category: "LLMInference")

    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?

    private(set) var isModelLoaded = false
    private(set) var loadedModelID: String?
    private(set) var contextWindowSize: Int = 0

    // MARK: - Model Lifecycle

    func loadModel(modelID: String) async throws {
        if isModelLoaded {
            unloadModel()
        }

        let modelsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Models", isDirectory: true)
        let modelPath = modelsDir.appendingPathComponent(modelID, isDirectory: true)

        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw LLMError.modelNotFound(modelID: modelID)
        }

        FileHandle.standardError.write(Data("[SFP-LLM] Loading model from: \(modelPath.path)\n".utf8))

        do {
            let configuration = ModelConfiguration(directory: modelPath)
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: configuration
            ) { progress in
                FileHandle.standardError.write(
                    Data("[SFP-LLM] Loading: \(Int(progress.fractionCompleted * 100))%\n".utf8)
                )
            }

            self.modelContainer = container
            self.isModelLoaded = true
            self.loadedModelID = modelID

            // Read context window from config
            let configURL = modelPath.appendingPathComponent("config.json")
            if let data = try? Data(contentsOf: configURL),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.contextWindowSize = dict["max_position_embeddings"] as? Int ?? 4096
            } else {
                self.contextWindowSize = 4096
            }

            FileHandle.standardError.write(
                Data("[SFP-LLM] Model loaded: \(modelID), context: \(contextWindowSize)\n".utf8)
            )
        } catch {
            FileHandle.standardError.write(Data("[SFP-LLM] Load FAILED: \(error)\n".utf8))
            throw LLMError.modelLoadFailed(underlying: error)
        }
    }

    func unloadModel() {
        Self.logger.info("Unloading LLM")
        chatSession = nil
        modelContainer = nil
        isModelLoaded = false
        loadedModelID = nil
        contextWindowSize = 0
        MLX.Memory.cacheLimit = 0
        Self.logger.info("LLM unloaded")
    }

    // MARK: - Token Count

    func tokenCount(for text: String) async -> Int {
        guard let container = modelContainer else { return text.count / 4 }
        let tokenizer = await container.tokenizer
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
        guard let container = modelContainer else {
            FileHandle.standardError.write(Data("[SFP-LLM] Generate: no model loaded\n".utf8))
            continuation.finish()
            return
        }

        FileHandle.standardError.write(
            Data("[SFP-LLM] Generating: prompt=\(prompt.count) chars, maxTokens=\(maxTokens)\n".utf8)
        )

        let signpostID = OSSignpostID(log: .default)
        os_signpost(.begin, log: .default, name: "LLMGeneration", signpostID: signpostID)

        var params = GenerateParameters()
        params.temperature = temperature
        params.maxTokens = maxTokens

        let session = ChatSession(
            container,
            generateParameters: params
        )

        var generatedText = ""
        var tokenCount = 0

        do {
            let stream = session.streamResponse(to: prompt)
            for try await chunk in stream {
                guard !Task.isCancelled else {
                    FileHandle.standardError.write(Data("[SFP-LLM] Generation cancelled\n".utf8))
                    break
                }

                generatedText += chunk
                tokenCount += 1
                continuation.yield(chunk)

                // Stop sequence check
                for stopSeq in stopSequences {
                    if generatedText.hasSuffix(stopSeq) {
                        FileHandle.standardError.write(
                            Data("[SFP-LLM] Stop sequence: \(stopSeq)\n".utf8)
                        )
                        os_signpost(.end, log: .default, name: "LLMGeneration", signpostID: signpostID)
                        continuation.finish()
                        return
                    }
                }
            }
        } catch {
            FileHandle.standardError.write(Data("[SFP-LLM] Generation error: \(error)\n".utf8))
        }

        os_signpost(.end, log: .default, name: "LLMGeneration", signpostID: signpostID)
        FileHandle.standardError.write(Data("[SFP-LLM] Generated ~\(tokenCount) chunks\n".utf8))
        continuation.finish()
    }
}
