import Foundation

enum LLMError: Error, LocalizedError, Sendable {
    case noModelLoaded
    case modelNotFound(modelID: String)
    case modelLoadFailed(underlying: any Error)
    case insufficientMemory
    case unsupportedModelFormat
    case contextWindowExceeded(promptTokens: Int, maxContext: Int)
    case inferenceError(underlying: any Error)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            "No LLM model is loaded. Please load a model first."
        case .modelNotFound(let modelID):
            "Model '\(modelID)' not found at ~/Models/."
        case .modelLoadFailed(let error):
            "Failed to load LLM: \(error.localizedDescription)"
        case .insufficientMemory:
            "Insufficient memory to load the LLM model."
        case .unsupportedModelFormat:
            "Unsupported model format. Expected MLX-format weights with config.json."
        case .contextWindowExceeded(let prompt, let max):
            "Prompt (\(prompt) tokens) exceeds context window (\(max) tokens)."
        case .inferenceError(let error):
            "LLM inference error: \(error.localizedDescription)"
        case .cancelled:
            "Generation was cancelled."
        }
    }
}
