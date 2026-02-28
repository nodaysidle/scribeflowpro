import Foundation
import SwiftData
import os

enum SessionState: Sendable {
    case idle
    case recording
    case processing
    case error(String)
}

@Observable
@MainActor
final class SessionOrchestrator {
    static let logger = Logger(subsystem: "com.scribeflowpro", category: "SessionOrchestrator")

    private(set) var sessionState: SessionState = .idle
    private(set) var liveChunks: [TranscriptChunk] = []
    private(set) var recordingStartDate: Date?

    private let audioCaptureActor = AudioCaptureActor()
    private let whisperActor = WhisperTranscriptionActor()
    private let diarizer = SpeakerDiarizer()
    private let meetingStore = MeetingStore()

    private var sessionTask: Task<Void, Never>?
    private var currentSpeakerIndex = 0
    private var lastEndTime: TimeInterval = 0

    var isRecording: Bool {
        if case .recording = sessionState { return true }
        return false
    }

    var availableDevices: [AudioDevice] {
        audioCaptureActor.listInputDevices()
    }

    // MARK: - Model Management

    func loadWhisperModel(modelID: String) async throws {
        try await whisperActor.loadModel(modelID: modelID)
    }

    var isWhisperLoaded: Bool {
        get async { await whisperActor.isModelLoaded }
    }

    // MARK: - Session Lifecycle

    func startSession(device: AudioDevice?, modelContext: ModelContext) {
        guard case .idle = sessionState else {
            Self.logger.warning("startSession called in non-idle state")
            return
        }

        Self.logger.info("Starting recording session")
        liveChunks = []
        currentSpeakerIndex = 0
        lastEndTime = 0
        recordingStartDate = Date()
        sessionState = .recording

        sessionTask = Task {
            do {
                let audioStream = try await audioCaptureActor.startCapture(inputDevice: device)

                let whisperLoaded = await whisperActor.isModelLoaded
                if whisperLoaded {
                    let chunkStream = await whisperActor.transcribe(audioStream: audioStream)

                    for await chunk in chunkStream {
                        guard !Task.isCancelled else { break }

                        let labeled = diarizer.assignSpeaker(
                            chunk: chunk,
                            currentSpeakerIndex: &currentSpeakerIndex,
                            lastEndTime: &lastEndTime
                        )
                        liveChunks.append(labeled)
                    }
                } else {
                    // No Whisper model — just capture audio, no live transcription
                    Self.logger.info("No Whisper model loaded — audio-only recording")
                    for await _ in audioStream {
                        guard !Task.isCancelled else { break }
                    }
                }
            } catch {
                Self.logger.error("Session error: \(error.localizedDescription)")
                sessionState = .error(error.localizedDescription)
            }
        }
    }

    func stopSession(title: String?, modelContext: ModelContext) async -> Meeting? {
        guard case .recording = sessionState else {
            Self.logger.warning("stopSession called in non-recording state")
            return nil
        }

        Self.logger.info("Stopping recording session")
        sessionState = .processing

        sessionTask?.cancel()
        sessionTask = nil

        await audioCaptureActor.stopCapture()

        let duration: TimeInterval
        if let start = recordingStartDate {
            duration = Date().timeIntervalSince(start)
        } else {
            duration = 0
        }

        let rawTranscript = liveChunks.map(\.text).joined(separator: " ")
        let audioURL = await audioCaptureActor.audioFileURL

        do {
            let meeting = try meetingStore.saveMeeting(
                title: title,
                date: recordingStartDate ?? Date(),
                duration: duration,
                rawTranscript: rawTranscript,
                segments: liveChunks,
                audioTempURL: audioURL,
                modelContext: modelContext
            )

            Self.logger.info("Session saved: \(meeting.title), \(self.liveChunks.count) segments")

            liveChunks = []
            recordingStartDate = nil
            sessionState = .idle

            return meeting
        } catch {
            Self.logger.error("Failed to save session: \(error.localizedDescription)")
            sessionState = .error("Failed to save: \(error.localizedDescription)")
            return nil
        }
    }

    func cancelSession() async {
        sessionTask?.cancel()
        sessionTask = nil
        await audioCaptureActor.stopCapture()
        liveChunks = []
        recordingStartDate = nil
        sessionState = .idle
        Self.logger.info("Session cancelled")
    }
}
