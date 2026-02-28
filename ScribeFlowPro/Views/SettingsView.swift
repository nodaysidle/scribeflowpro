import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allModels: [InstalledModel]

    private var whisperModels: [InstalledModel] {
        allModels.filter { $0.modelType == .whisper }
    }

    private var llmModels: [InstalledModel] {
        allModels.filter { $0.modelType == .llm }
    }

    @State private var settings: AppSettings?
    @State private var availableDevices: [AudioDevice] = []
    private let audioCaptureActor = AudioCaptureActor()

    var body: some View {
        Form {
            audioSection
            modelsSection
            promptsSection
            contextSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 400)
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
        .task {
            settings = AppSettings.fetchOrCreate(in: modelContext)
            availableDevices = audioCaptureActor.listInputDevices()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var audioSection: some View {
        if let settings {
            Section("Audio Input") {
                Picker("Microphone", selection: Binding(
                    get: { settings.audioInputDeviceID },
                    set: { settings.audioInputDeviceID = $0 }
                )) {
                    Text("System Default").tag(String?.none)
                    ForEach(availableDevices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var modelsSection: some View {
        if let settings {
            Section("Models") {
                Picker("Whisper Model", selection: Binding(
                    get: { settings.selectedWhisperModelID },
                    set: { settings.selectedWhisperModelID = $0 }
                )) {
                    Text("None").tag(String?.none)
                    ForEach(whisperModels) { model in
                        Text(modelLabel(model)).tag(Optional(model.id.uuidString))
                    }
                }

                Picker("LLM Model", selection: Binding(
                    get: { settings.selectedLLMModelID },
                    set: { settings.selectedLLMModelID = $0 }
                )) {
                    Text("None").tag(String?.none)
                    ForEach(llmModels) { model in
                        Text(modelLabel(model)).tag(Optional(model.id.uuidString))
                    }
                }

                if whisperModels.isEmpty && llmModels.isEmpty {
                    Text("No models installed. Use the Model Manager to download models.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var promptsSection: some View {
        if let settings {
            Section("Prompt Templates") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Summarization Prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: Binding(
                        get: { settings.summarizationPromptTemplate },
                        set: { settings.summarizationPromptTemplate = $0 }
                    ))
                    .font(.body.monospaced())
                    .frame(minHeight: 80)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Action Items Prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: Binding(
                        get: { settings.actionItemsPromptTemplate },
                        set: { settings.actionItemsPromptTemplate = $0 }
                    ))
                    .font(.body.monospaced())
                    .frame(minHeight: 80)
                }
            }
        }
    }

    @ViewBuilder
    private var contextSection: some View {
        if let settings {
            Section("Context Injection") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Max Context Tokens: \(settings.maxContextInjectionTokens)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(settings.maxContextInjectionTokens) },
                            set: { settings.maxContextInjectionTokens = Int($0) }
                        ),
                        in: 500...4000,
                        step: 100
                    )
                }
            }
        }
    }

    private func modelLabel(_ model: InstalledModel) -> String {
        var label = model.name
        if let q = model.quantization {
            label += " (\(q))"
        }
        return label
    }
}
