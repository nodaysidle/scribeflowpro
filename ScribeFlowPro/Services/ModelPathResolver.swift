import Foundation

enum ModelPathResolver {
    static let modelsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Models", isDirectory: true)

    static func storageDirectory(for repo: String, in baseDirectory: URL = modelsDirectory) -> URL {
        baseDirectory.appendingPathComponent(flattenedModelID(repo), isDirectory: true)
    }

    static func existingDirectory(for modelID: String, in baseDirectory: URL = modelsDirectory) -> URL? {
        candidateDirectories(for: modelID, in: baseDirectory).first { candidate in
            FileManager.default.fileExists(atPath: candidate.path)
        }
    }

    static func candidateDirectories(for modelID: String, in baseDirectory: URL = modelsDirectory) -> [URL] {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var candidates: [URL] = []
        if trimmed.hasPrefix("/") {
            candidates.append(URL(fileURLWithPath: trimmed, isDirectory: true))
        }

        candidates.append(baseDirectory.appendingPathComponent(trimmed, isDirectory: true))
        candidates.append(storageDirectory(for: trimmed, in: baseDirectory))

        if trimmed.contains("_") {
            candidates.append(baseDirectory.appendingPathComponent(trimmed.replacingOccurrences(of: "_", with: "/"), isDirectory: true))
        }

        var seen = Set<String>()
        return candidates.filter { url in
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }

    static func flattenedModelID(_ modelID: String) -> String {
        modelID.replacingOccurrences(of: "/", with: "_")
    }

    static func repoID(from modelDirectory: URL, orgName: String?) -> String {
        if let orgName {
            return "\(orgName)/\(modelDirectory.lastPathComponent)"
        }
        return modelDirectory.lastPathComponent.replacingOccurrences(of: "_", with: "/")
    }
}
