import Foundation

struct AudioDevice: Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let sampleRate: Double
    let isDefault: Bool
}
