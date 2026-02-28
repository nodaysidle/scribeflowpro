import Foundation
import SwiftData

enum ModelType: String, Codable, Sendable {
    case whisper
    case llm
}

@Model
final class InstalledModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var huggingFaceRepo: String
    var filePath: String
    var sizeBytes: Int64
    var lastUsed: Date?
    var modelType: ModelType
    var quantization: String?

    init(
        id: UUID = UUID(),
        name: String,
        huggingFaceRepo: String,
        filePath: String,
        sizeBytes: Int64,
        lastUsed: Date? = nil,
        modelType: ModelType,
        quantization: String? = nil
    ) {
        self.id = id
        self.name = name
        self.huggingFaceRepo = huggingFaceRepo
        self.filePath = filePath
        self.sizeBytes = sizeBytes
        self.lastUsed = lastUsed
        self.modelType = modelType
        self.quantization = quantization
    }
}
