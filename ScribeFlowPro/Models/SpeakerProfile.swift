import Foundation
import SwiftData

@Model
final class SpeakerProfile {
    @Attribute(.unique) var id: UUID
    var label: String
    var displayName: String
    var colorHex: String

    init(
        id: UUID = UUID(),
        label: String,
        displayName: String,
        colorHex: String = "007AFF"
    ) {
        self.id = id
        self.label = label
        self.displayName = displayName
        self.colorHex = colorHex
    }
}
