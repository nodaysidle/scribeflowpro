import SwiftData

enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Meeting.self,
            TranscriptSegment.self,
            SpeakerProfile.self,
            AppSettings.self,
            InstalledModel.self,
        ]
    }
}

enum ScribeFlowMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
