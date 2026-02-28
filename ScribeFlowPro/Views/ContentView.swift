import SwiftUI
import SwiftData
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
    @State private var hasScannedModels = false

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
                ContentUnavailableView(
                    "No Meeting Selected",
                    systemImage: "waveform",
                    description: Text("Select a meeting from the sidebar or start recording.")
                )
            }
        }
    }

    private func scanForLocalModels() {
        let modelsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Models", isDirectory: true)

        Self.logger.warning("Scan: modelsDir=\(modelsDir.path)")

        let fm = FileManager.default
        guard fm.fileExists(atPath: modelsDir.path) else {
            Self.logger.warning("Scan: ~/Models does not exist")
            return
        }

        let descriptor = FetchDescriptor<InstalledModel>()
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let existingPaths = Set(existing.map { $0.filePath })
        Self.logger.warning("Scan: \(existing.count) already registered")

        guard let topDirs = try? fm.contentsOfDirectory(
            at: modelsDir, includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            Self.logger.warning("Scan: failed to list ~/Models")
            return
        }

        Self.logger.warning("Scan: \(topDirs.count) top-level entries")

        var registered = 0
        for orgDir in topDirs {
            guard (try? orgDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

            let subdirs = (try? fm.contentsOfDirectory(at: orgDir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []

            for modelDir in subdirs {
                guard (try? modelDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                guard fm.fileExists(atPath: modelDir.appendingPathComponent("config.json").path) else { continue }
                guard !existingPaths.contains(modelDir.path) else { continue }

                let repo = "\(orgDir.lastPathComponent)/\(modelDir.lastPathComponent)"
                let modelType: ModelType = repo.lowercased().contains("whisper") ? .whisper : .llm

                var totalSize: Int64 = 0
                if let enumerator = fm.enumerator(at: modelDir, includingPropertiesForKeys: [.fileSizeKey]) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        if let sz = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                            totalSize += Int64(sz)
                        }
                    }
                }

                var quantization: String?
                if let data = try? Data(contentsOf: modelDir.appendingPathComponent("config.json")),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let qConfig = json["quantization_config"] as? [String: Any],
                   let bits = qConfig["bits"] as? Int {
                    quantization = "\(bits)bit"
                }

                let model = InstalledModel(
                    name: repo,
                    huggingFaceRepo: repo,
                    filePath: modelDir.path,
                    sizeBytes: totalSize,
                    modelType: modelType,
                    quantization: quantization
                )
                modelContext.insert(model)
                registered += 1
                Self.logger.warning("Scan: registered \(repo) (\(modelType.rawValue))")
            }
        }

        if registered > 0 {
            try? modelContext.save()
        }
        Self.logger.warning("Scan: done, registered \(registered) new models")
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
