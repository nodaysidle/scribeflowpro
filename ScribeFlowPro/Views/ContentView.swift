import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import os

struct ContentView: View {
    private static let logger = Logger(subsystem: "com.scribeflowpro", category: "ContentView")

    @Environment(\.modelContext) private var modelContext
    @Query private var allModels: [InstalledModel]
    @State private var selectedMeeting: Meeting?
    @State private var orchestrator = SessionOrchestrator()
    @State private var selectedDevice: AudioDevice?
    @State private var availableDevices: [AudioDevice] = []
    @State private var showSettings = false
    @State private var showModelManager = false
    @State private var showAudioImporter = false
    @State private var hasScannedModels = false
    @State private var modelManager = ModelManagerService()

    var body: some View {
        ZStack {
            LiquidGlassBackground()

            NavigationSplitView {
                MeetingSidebarView(selectedMeeting: $selectedMeeting)
            } detail: {
                detailContent
            }
            .toolbar {
                ToolbarItemGroup(placement: .secondaryAction) {
                    Button {
                        showAudioImporter = true
                    } label: {
                        Label("Import Audio", systemImage: "square.and.arrow.down")
                    }
                    .disabled(orchestrator.isRecording)

                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }

                    Button {
                        showModelManager = true
                    } label: {
                        Label("Models", systemImage: "arrow.down.circle")
                    }
                }

                RecordingToolbar(
                    isRecording: orchestrator.isRecording,
                    recordingStartTime: orchestrator.recordingStartDate,
                    selectedDevice: $selectedDevice,
                    availableDevices: availableDevices,
                    onToggleRecording: toggleRecording
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .sheet(isPresented: $showModelManager) {
            NavigationStack {
                ModelManagerView()
            }
        }
        .fileImporter(
            isPresented: $showAudioImporter,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: false
        ) { result in
            handleImportedAudio(result)
        }
        .onAppear {
            Self.logger.info("ContentView appeared, scanning models...")
            availableDevices = orchestrator.availableDevices
            selectedDevice = availableDevices.first(where: \.isDefault) ?? availableDevices.first
            if !hasScannedModels {
                scanForLocalModels()
                hasScannedModels = true
            }
        }
        .onChange(of: allModels.count) {
            Self.logger.info("Model count changed to: \(allModels.count)")
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch orchestrator.sessionState {
        case .recording:
            LiveTranscriptionView(chunks: orchestrator.liveChunks)
        case .processing:
            VStack(spacing: 12) {
                ProgressView("Saving meeting...")
                Text("Processing transcript and audio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .error(let message):
            ContentUnavailableView(
                "Error",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .idle:
            if let meeting = selectedMeeting {
                MeetingDetailView(meeting: meeting)
            } else {
                EmptyMeetingHero(
                    hasWhisperModel: allModels.contains { $0.modelType == .whisper },
                    hasLLMModel: allModels.contains { $0.modelType == .llm }
                )
            }
        }
    }

    private func scanForLocalModels() {
        modelManager.scanAndRegisterLocalModels(modelContext: modelContext)
    }

    private func handleImportedAudio(_ result: Result<[URL], any Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result {
                Self.logger.error("Audio import failed: \(error.localizedDescription)")
            }
            return
        }

        Task {
            if let meeting = await orchestrator.importAudioFile(url, modelContext: modelContext) {
                selectedMeeting = meeting
            }
        }
    }

    private func toggleRecording() {
        if orchestrator.isRecording {
            Task {
                let meeting = await orchestrator.stopSession(
                    title: nil,
                    modelContext: modelContext
                )
                if let meeting {
                    selectedMeeting = meeting
                }
            }
        } else {
            orchestrator.startSession(device: selectedDevice, modelContext: modelContext)
        }
    }
}

// MARK: - Empty State

private struct EmptyMeetingHero: View {
    let hasWhisperModel: Bool
    let hasLLMModel: Bool

    private let volt = Color(red: 0.78, green: 1.0, blue: 0.0)

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 58, weight: .semibold))
                .foregroundStyle(volt)
                .shadow(color: volt.opacity(0.35), radius: 18)

            VStack(spacing: 8) {
                Text("Offline meeting intelligence")
                    .font(.largeTitle.bold())
                Text("Record live audio or import a meeting file. Transcription and summaries stay on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            HStack(spacing: 12) {
                ReadinessPill(title: "Whisper", ready: hasWhisperModel)
                ReadinessPill(title: "Local LLM", ready: hasLLMModel)
                ReadinessPill(title: "Private storage", ready: true)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ReadinessPill: View {
    let title: String
    let ready: Bool

    var body: some View {
        Label(title, systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.caption.bold())
            .foregroundStyle(ready ? Color(red: 0.78, green: 1.0, blue: 0.0) : .orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.25), in: Capsule())
            .overlay(
                Capsule().stroke((ready ? Color(red: 0.78, green: 1.0, blue: 0.0) : .orange).opacity(0.35), lineWidth: 1)
            )
    }
}

// MARK: - Recording Toolbar

struct RecordingToolbar: ToolbarContent {
    let isRecording: Bool
    let recordingStartTime: Date?
    @Binding var selectedDevice: AudioDevice?
    let availableDevices: [AudioDevice]
    let onToggleRecording: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if isRecording, let startTime = recordingStartTime {
                RecordingPulseIndicator(isRecording: true)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = context.date.timeIntervalSince(startTime)
                    let minutes = Int(elapsed) / 60
                    let seconds = Int(elapsed) % 60
                    Text(String(format: "%02d:%02d", minutes, seconds))
                        .monospacedDigit()
                        .foregroundStyle(.red)
                        .font(.headline)
                }
            }

            if !availableDevices.isEmpty {
                Picker("Input", selection: $selectedDevice) {
                    ForEach(availableDevices) { device in
                        Text(device.name).tag(Optional(device))
                    }
                }
                .frame(maxWidth: 200)
                .disabled(isRecording)
            }

            Button {
                onToggleRecording()
            } label: {
                Label(
                    isRecording ? "Stop" : "Record",
                    systemImage: isRecording ? "stop.circle.fill" : "record.circle"
                )
                .foregroundStyle(isRecording ? .red : .primary)
            }
        }
    }
}
