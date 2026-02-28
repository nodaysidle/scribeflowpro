import Foundation

struct TranscriptChunk: Sendable, Identifiable {
    let id: UUID
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    var speakerLabel: String
    let confidence: Float
    var isFinal: Bool

    init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        speakerLabel: String = "Speaker A",
        confidence: Float = 1.0,
        isFinal: Bool = false
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.speakerLabel = speakerLabel
        self.confidence = confidence
        self.isFinal = isFinal
    }
}

enum TranscriptionError: Error, LocalizedError, Sendable {
    case modelNotFound(modelID: String)
    case modelLoadFailed(underlying: any Error)
    case inferenceError(underlying: any Error)
    case invalidAudioFormat
    case insufficientMemory
    case noModelLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let modelID):
            "Model '\(modelID)' not found at ~/Models/."
        case .modelLoadFailed(let error):
            "Failed to load model: \(error.localizedDescription)"
        case .inferenceError(let error):
            "Transcription inference error: \(error.localizedDescription)"
        case .invalidAudioFormat:
            "Audio format does not match expected 16kHz mono Float32."
        case .insufficientMemory:
            "Insufficient memory to load the model."
        case .noModelLoaded:
            "No transcription model is loaded."
        }
    }
}
