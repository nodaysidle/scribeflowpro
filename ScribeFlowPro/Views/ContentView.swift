import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedMeeting: Meeting?
    @State private var orchestrator = SessionOrchestrator()
    @State private var selectedDevice: AudioDevice?
    @State private var availableDevices: [AudioDevice] = []
    @State private var showSettings = false
    @State private var showModelManager = false

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
        .task {
            availableDevices = orchestrator.availableDevices
            selectedDevice = availableDevices.first(where: \.isDefault) ?? availableDevices.first
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
                ContentUnavailableView(
                    "No Meeting Selected",
                    systemImage: "waveform",
                    description: Text("Select a meeting from the sidebar or start recording.")
                )
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
