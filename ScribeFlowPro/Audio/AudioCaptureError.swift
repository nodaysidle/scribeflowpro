import Foundation

enum AudioCaptureError: Error, LocalizedError, Sendable {
    case permissionDenied
    case deviceUnavailable
    case engineStartFailed(underlying: any Error)
    case formatConversionFailed
    case notCapturing
    case deviceEnumerationFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Microphone access was denied. Please enable it in System Settings > Privacy & Security > Microphone."
        case .deviceUnavailable:
            "The selected audio input device is unavailable."
        case .engineStartFailed(let error):
            "Audio engine failed to start: \(error.localizedDescription)"
        case .formatConversionFailed:
            "Unable to convert audio to the required format."
        case .notCapturing:
            "No active capture session to stop."
        case .deviceEnumerationFailed:
            "Failed to enumerate audio input devices."
        }
    }
}
