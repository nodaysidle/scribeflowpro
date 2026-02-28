import SwiftUI
import SwiftData

@main
struct ScribeFlowProApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        createModelsDirectoryIfNeeded()
        cleanupOldTempFiles()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { scanForLocalModels() }
        }
        .modelContainer(modelContainer)
    }

    @MainActor
    private func scanForLocalModels() {
        let context = modelContainer.mainContext
        let scanner = ModelManagerService()
        scanner.scanAndRegisterLocalModels(modelContext: context)
    }

    private func createModelsDirectoryIfNeeded() {
        let modelsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Models", isDirectory: true)
        if !FileManager.default.fileExists(atPath: modelsURL.path) {
            try? FileManager.default.createDirectory(at: modelsURL, withIntermediateDirectories: true)
        }
    }

    private func cleanupOldTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for file in files where file.pathExtension == "wav" {
            guard let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
                  let created = attrs.creationDate,
                  created < cutoff else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
