import Foundation

enum ModelManagerError: Error, LocalizedError, Sendable {
    case networkUnavailable
    case repoNotFound(repo: String)
    case downloadFailed(fileName: String, underlying: any Error)
    case insufficientDiskSpace(required: Int64, available: Int64)
    case integrityCheckFailed(fileName: String)
    case modelNotFound
    case deletionFailed(underlying: any Error)
    case modelInUse
    case swiftDataQueryFailed(underlying: any Error)

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            "No internet connection available."
        case .repoNotFound(let repo):
            "Repository '\(repo)' not found on Hugging Face."
        case .downloadFailed(let fileName, let error):
            "Download failed for '\(fileName)': \(error.localizedDescription)"
        case .insufficientDiskSpace(let required, let available):
            "Insufficient disk space. Required: \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)), Available: \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))"
        case .integrityCheckFailed(let fileName):
            "Integrity check failed for '\(fileName)'. The file may be corrupted."
        case .modelNotFound:
            "Model not found."
        case .deletionFailed(let error):
            "Failed to delete model: \(error.localizedDescription)"
        case .modelInUse:
            "Model is currently in use. Stop the active session before deleting."
        case .swiftDataQueryFailed(let error):
            "Database query failed: \(error.localizedDescription)"
        }
    }
}

enum DownloadStatus: Sendable {
    case downloading
    case verifying
    case completed
    case failed(any Error)
}

struct DownloadProgress: Sendable {
    let fileName: String
    let bytesDownloaded: Int64
    let totalBytes: Int64
    let overallProgress: Double
    let status: DownloadStatus
}

struct StorageReport: Sendable {
    let totalBytes: Int64
    let modelBreakdown: [(name: String, bytes: Int64)]
}
