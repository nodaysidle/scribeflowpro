import Foundation
import SwiftData

@Model
final class TranscriptSegment {
    @Attribute(.unique) var id: UUID
    var timestamp: TimeInterval
    var endTimestamp: TimeInterval
    var speakerLabel: String
    var text: String
    var confidence: Float

    var meeting: Meeting?

    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        endTimestamp: TimeInterval,
        speakerLabel: String,
        text: String,
        confidence: Float = 1.0,
        meeting: Meeting? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.endTimestamp = endTimestamp
        self.speakerLabel = speakerLabel
        self.text = text
        self.confidence = confidence
        self.meeting = meeting
    }
}
