import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import os

actor LLMInferenceActor {
    static let logger = Logger(subsystem: "com.scribeflowpro", category: "LLMInference")

    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?
    private var bridgeModelFolder: URL?
    private var usesMLXLMBridge = false

    private(set) var isModelLoaded = false
    private(set) var loadedModelID: String?
    private(set) var contextWindowSize: Int = 0

    // MARK: - Model Lifecycle

    func loadModel(modelID: String) async throws {
        if isModelLoaded {
            unloadModel()
        }

        guard let modelPath = ModelPathResolver.existingDirectory(for: modelID) else {
            throw LLMError.modelNotFound(modelID: modelID)
        }

        #if DEBUG
        FileHandle.standardError.write(Data("[SFP-LLM] Loading model from: \(modelPath.path)\n".utf8))
        #endif

        if Self.shouldUseBridge(for: modelPath) {
            self.modelContainer = nil
            self.bridgeModelFolder = modelPath
            self.usesMLXLMBridge = true
            self.isModelLoaded = true
            self.loadedModelID = modelID
            self.contextWindowSize = Self.readContextWindow(from: modelPath)
            #if DEBUG
            FileHandle.standardError.write(Data("[SFP-LLM] Using MLX-LM bridge for: \(modelPath.path)\n".utf8))
            #endif
            return
        }

        do {
            let configuration = ModelConfiguration(directory: modelPath)
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: configuration
            ) { progress in
                #if DEBUG
                FileHandle.standardError.write(
                    Data("[SFP-LLM] Loading: \(Int(progress.fractionCompleted * 100))%\n".utf8)
                )
                #endif
            }

            self.modelContainer = container
            self.isModelLoaded = true
            self.loadedModelID = modelID

            // Read context window from config
            self.contextWindowSize = Self.readContextWindow(from: modelPath)

            #if DEBUG
            FileHandle.standardError.write(
                Data("[SFP-LLM] Model loaded: \(modelID), context: \(contextWindowSize)\n".utf8)
            )
            #endif
        } catch {
            #if DEBUG
            FileHandle.standardError.write(Data("[SFP-LLM] Load FAILED: \(error)\n".utf8))
            #endif
            throw LLMError.modelLoadFailed(underlying: error)
        }
    }

    func unloadModel() {
        Self.logger.info("Unloading LLM")
        chatSession = nil
        modelContainer = nil
        bridgeModelFolder = nil
        usesMLXLMBridge = false
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
        if usesMLXLMBridge {
            do {
                let generated = try Self.generateWithMLXLMBridge(
                    prompt: prompt,
                    modelFolder: bridgeModelFolder,
                    maxTokens: maxTokens,
                    temperature: temperature
                )
                continuation.yield(generated)
            } catch {
                #if DEBUG
                FileHandle.standardError.write(Data("[SFP-LLM] Bridge generation error: \(error)\n".utf8))
                #endif
            }
            continuation.finish()
            return
        }

        guard let container = modelContainer else {
            #if DEBUG
            FileHandle.standardError.write(Data("[SFP-LLM] Generate: no model loaded\n".utf8))
            #endif
            continuation.finish()
            return
        }

        #if DEBUG
        FileHandle.standardError.write(
            Data("[SFP-LLM] Generating: prompt=\(prompt.count) chars, maxTokens=\(maxTokens)\n".utf8)
        )
        #endif

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
                    #if DEBUG
                    FileHandle.standardError.write(Data("[SFP-LLM] Generation cancelled\n".utf8))
                    #endif
                    break
                }

                generatedText += chunk
                tokenCount += 1
                continuation.yield(chunk)

                // Stop sequence check
                for stopSeq in stopSequences {
                    if generatedText.hasSuffix(stopSeq) {
                        #if DEBUG
                        FileHandle.standardError.write(
                            Data("[SFP-LLM] Stop sequence: \(stopSeq)\n".utf8)
                        )
                        #endif
                        os_signpost(.end, log: .default, name: "LLMGeneration", signpostID: signpostID)
                        continuation.finish()
                        return
                    }
                }
            }
        } catch {
            #if DEBUG
            FileHandle.standardError.write(Data("[SFP-LLM] Generation error: \(error)\n".utf8))
            #endif
        }

        os_signpost(.end, log: .default, name: "LLMGeneration", signpostID: signpostID)
        #if DEBUG
        FileHandle.standardError.write(Data("[SFP-LLM] Generated ~\(tokenCount) chunks\n".utf8))
        #endif
        continuation.finish()
    }

    // MARK: - MLX-LM Bridge

    private struct MLXLMBridgeOutput: Decodable {
        let text: String?
        let error: String?
    }

    private static func shouldUseBridge(for modelPath: URL) -> Bool {
        if ProcessInfo.processInfo.environment["SFP_FORCE_MLX_LM_BRIDGE"] == "1" {
            return true
        }
        return FileManager.default.fileExists(atPath: modelPath.appendingPathComponent("model.safetensors").path)
    }

    private static func readContextWindow(from modelPath: URL) -> Int {
        let configURL = modelPath.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: configURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return 4096
        }
        return dict["max_position_embeddings"] as? Int
            ?? dict["sliding_window"] as? Int
            ?? 4096
    }

    private static func generateWithMLXLMBridge(
        prompt: String,
        modelFolder: URL?,
        maxTokens: Int,
        temperature: Float
    ) throws -> String {
        guard let modelFolder else {
            throw LLMError.noModelLoaded
        }
        let bridge = try locateMLXLMBridge()
        let python = locateMLXBridgePython()
        let process = Process()
        process.executableURL = python
        process.arguments = [
            bridge.path,
            "--model", modelFolder.path,
            "--prompt", prompt,
            "--max-tokens", String(maxTokens),
            "--temperature", String(temperature)
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw LLMError.inferenceError(underlying: error)
        }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "MLX-LM bridge failed"
            throw LLMError.inferenceError(underlying: BridgeError(message))
        }

        do {
            let decoded = try JSONDecoder().decode(MLXLMBridgeOutput.self, from: outputData)
            if let error = decoded.error {
                throw LLMError.inferenceError(underlying: BridgeError(error))
            }
            return decoded.text ?? ""
        } catch let llmError as LLMError {
            throw llmError
        } catch {
            let raw = String(data: outputData, encoding: .utf8) ?? ""
            throw LLMError.inferenceError(underlying: BridgeError("Could not parse MLX-LM output: \(raw)"))
        }
    }

    private static func locateMLXLMBridge() throws -> URL {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        let candidates: [URL] = [
            env["SFP_MLX_LM_BRIDGE"].map(URL.init(fileURLWithPath:)),
            Bundle.main.resourceURL?.appendingPathComponent("Scripts/mlx_lm_generate.py"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Scripts/mlx_lm_generate.py")
        ].compactMap { $0 }
        if let match = candidates.first(where: { fm.fileExists(atPath: $0.path) }) {
            return match
        }
        throw LLMError.inferenceError(underlying: BridgeError("MLX-LM bridge script not found"))
    }

    private static func locateMLXBridgePython() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let explicit = env["SFP_MLX_LM_PYTHON"] ?? env["SFP_MLX_WHISPER_PYTHON"], !explicit.isEmpty {
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
}
