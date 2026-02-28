import Foundation
import SwiftData

@Model
final class AppSettings {
    @Attribute(.unique) var id: UUID
    var selectedWhisperModelID: String?
    var selectedLLMModelID: String?
    var audioInputDeviceID: String?
    var summarizationPromptTemplate: String
    var actionItemsPromptTemplate: String
    var maxContextInjectionTokens: Int

    init(
        id: UUID = UUID(),
        selectedWhisperModelID: String? = nil,
        selectedLLMModelID: String? = nil,
        audioInputDeviceID: String? = nil,
        summarizationPromptTemplate: String = "You are a meeting assistant. Summarize the following meeting transcript into key points, decisions, and action items.",
        actionItemsPromptTemplate: String = "Extract all action items from the following meeting transcript. Format each as a checkbox list item.",
        maxContextInjectionTokens: Int = 2048
    ) {
        self.id = id
        self.selectedWhisperModelID = selectedWhisperModelID
        self.selectedLLMModelID = selectedLLMModelID
        self.audioInputDeviceID = audioInputDeviceID
        self.summarizationPromptTemplate = summarizationPromptTemplate
        self.actionItemsPromptTemplate = actionItemsPromptTemplate
        self.maxContextInjectionTokens = maxContextInjectionTokens
    }

    @MainActor
    static func fetchOrCreate(in context: ModelContext) -> AppSettings {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let settings = AppSettings()
        context.insert(settings)
        return settings
    }
}
