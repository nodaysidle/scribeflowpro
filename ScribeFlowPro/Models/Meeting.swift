import Foundation
import SwiftData

@Model
final class Meeting {
    @Attribute(.unique) var id: UUID
    var title: String
    var date: Date
    var duration: TimeInterval
    var audioFilePath: String?
    var rawTranscript: String
    var summary: String?
    var actionItems: String?
    var participants: [String]

    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.meeting)
    var segments: [TranscriptSegment]

    init(
        id: UUID = UUID(),
        title: String? = nil,
        date: Date = Date(),
        duration: TimeInterval = 0,
        audioFilePath: String? = nil,
        rawTranscript: String = "",
        summary: String? = nil,
        actionItems: String? = nil,
        participants: [String] = []
    ) {
        self.id = id
        self.title = title ?? "Meeting — \(Self.dateFormatter.string(from: date))"
        self.date = date
        self.duration = duration
        self.audioFilePath = audioFilePath
        self.rawTranscript = rawTranscript
        self.summary = summary
        self.actionItems = actionItems
        self.participants = participants
        self.segments = []
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
