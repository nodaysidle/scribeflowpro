import Foundation
import SwiftData
import CryptoKit
import os

/// Hugging Face repo file metadata from the API.
private struct HFRepoFile: Decodable, Sendable {
    let rfilename: String
    let size: Int64
    let lfs: HFLfsInfo?

    struct HFLfsInfo: Decodable, Sendable {
        let sha256: String
        let size: Int64
    }
}

@Observable
@MainActor
final class ModelManagerService {
    static let logger = Logger(subsystem: "com.scribeflowpro", category: "ModelManager")

    var activeDownloads: [String: DownloadProgress] = [:]
    var isDownloading = false

    private let modelsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Models", isDirectory: true)

    // MARK: - Download

    func downloadModel(repo: String, modelContext: ModelContext) -> AsyncStream<DownloadProgress> {
        AsyncStream { continuation in
            Task {
                await self.performDownload(repo: repo, modelContext: modelContext, continuation: continuation)
            }
        }
    }

    private func performDownload(
        repo: String,
        modelContext: ModelContext,
        continuation: AsyncStream<DownloadProgress>.Continuation
    ) async {
        isDownloading = true
        defer { isDownloading = false }

        Self.logger.info("Starting download for repo: \(repo)")

        // 1. Fetch repo file listing from Hugging Face API
        let repoFiles: [HFRepoFile]
        do {
            repoFiles = try await fetchRepoFiles(repo: repo)
        } catch {
            let progress = DownloadProgress(
                fileName: "", bytesDownloaded: 0, totalBytes: 0,
                overallProgress: 0, status: .failed(error)
            )
            continuation.yield(progress)
            continuation.finish()
            return
        }

        guard !repoFiles.isEmpty else {
            let progress = DownloadProgress(
                fileName: "", bytesDownloaded: 0, totalBytes: 0,
                overallProgress: 0, status: .failed(ModelManagerError.repoNotFound(repo: repo))
            )
            continuation.yield(progress)
            continuation.finish()
            return
        }

        // 2. Check disk space
        let totalSize = repoFiles.reduce(Int64(0)) { $0 + ($1.lfs?.size ?? $1.size) }
        do {
            try checkDiskSpace(required: totalSize * 2)
        } catch {
            let progress = DownloadProgress(
                fileName: "", bytesDownloaded: 0, totalBytes: totalSize,
                overallProgress: 0, status: .failed(error)
            )
            continuation.yield(progress)
            continuation.finish()
            return
        }

        // 3. Create model directory
        let repoName = repo.replacingOccurrences(of: "/", with: "_")
        let modelDir = modelsDirectory.appendingPathComponent(repoName, isDirectory: true)
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // 4. Download each file
        var totalDownloaded: Int64 = 0
        let session = URLSession(configuration: .ephemeral)

        for (index, file) in repoFiles.enumerated() {
            let fileSize = file.lfs?.size ?? file.size
            let destURL = modelDir.appendingPathComponent(file.rfilename)

            // Create subdirectories if needed
            let parentDir = destURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

            // Skip if file already exists with correct size
            if let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path),
               let existingSize = attrs[.size] as? Int64,
               existingSize == fileSize {
                totalDownloaded += fileSize
                let progress = DownloadProgress(
                    fileName: file.rfilename,
                    bytesDownloaded: totalDownloaded,
                    totalBytes: totalSize,
                    overallProgress: Double(totalDownloaded) / Double(max(totalSize, 1)),
                    status: .completed
                )
                activeDownloads[file.rfilename] = progress
                continuation.yield(progress)
                continue
            }

            // Download with resume support
            let downloadURL = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file.rfilename)")!
            var request = URLRequest(url: downloadURL)

            // Check for partial download
            var existingBytes: Int64 = 0
            if FileManager.default.fileExists(atPath: destURL.path),
               let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path),
               let size = attrs[.size] as? Int64 {
                existingBytes = size
                request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
            }

            do {
                // Emit downloading status
                let dlProgress = DownloadProgress(
                    fileName: file.rfilename,
                    bytesDownloaded: totalDownloaded + existingBytes,
                    totalBytes: totalSize,
                    overallProgress: Double(totalDownloaded + existingBytes) / Double(max(totalSize, 1)),
                    status: .downloading
                )
                activeDownloads[file.rfilename] = dlProgress
                continuation.yield(dlProgress)

                let (tempURL, response) = try await session.download(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    throw ModelManagerError.downloadFailed(
                        fileName: file.rfilename,
                        underlying: URLError(.badServerResponse)
                    )
                }

                // Move downloaded file to destination
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destURL)

                // 5. Verify SHA256
                if let expectedHash = file.lfs?.sha256 {
                    let verifyProgress = DownloadProgress(
                        fileName: file.rfilename,
                        bytesDownloaded: totalDownloaded + fileSize,
                        totalBytes: totalSize,
                        overallProgress: Double(totalDownloaded + fileSize) / Double(max(totalSize, 1)),
                        status: .verifying
                    )
                    activeDownloads[file.rfilename] = verifyProgress
                    continuation.yield(verifyProgress)

                    let actualHash = try computeSHA256(for: destURL)
                    if actualHash != expectedHash {
                        try? FileManager.default.removeItem(at: destURL)
                        throw ModelManagerError.integrityCheckFailed(fileName: file.rfilename)
                    }
                }

                totalDownloaded += fileSize
                let completedProgress = DownloadProgress(
                    fileName: file.rfilename,
                    bytesDownloaded: totalDownloaded,
                    totalBytes: totalSize,
                    overallProgress: Double(totalDownloaded) / Double(max(totalSize, 1)),
                    status: .completed
                )
                activeDownloads[file.rfilename] = completedProgress
                continuation.yield(completedProgress)

                Self.logger.info("Downloaded \(index + 1)/\(repoFiles.count): \(file.rfilename)")

            } catch {
                let failedProgress = DownloadProgress(
                    fileName: file.rfilename,
                    bytesDownloaded: totalDownloaded,
                    totalBytes: totalSize,
                    overallProgress: Double(totalDownloaded) / Double(max(totalSize, 1)),
                    status: .failed(error)
                )
                activeDownloads[file.rfilename] = failedProgress
                continuation.yield(failedProgress)
                continuation.finish()
                return
            }
        }

        // 6. Create InstalledModel entity
        let modelType: ModelType = repo.lowercased().contains("whisper") ? .whisper : .llm
        let quantization = parseQuantization(from: modelDir)
        let installedModel = InstalledModel(
            name: repoName,
            huggingFaceRepo: repo,
            filePath: modelDir.path,
            sizeBytes: totalSize,
            modelType: modelType,
            quantization: quantization
        )
        modelContext.insert(installedModel)
        try? modelContext.save()

        Self.logger.info("Model installed: \(repoName) (\(totalSize) bytes)")

        activeDownloads.removeAll()
        continuation.finish()
    }

    // MARK: - Delete

    func deleteModel(_ model: InstalledModel, modelContext: ModelContext) throws {
        Self.logger.info("Deleting model: \(model.name)")

        let modelURL = URL(fileURLWithPath: model.filePath)
        do {
            if FileManager.default.fileExists(atPath: modelURL.path) {
                try FileManager.default.removeItem(at: modelURL)
            }
        } catch {
            throw ModelManagerError.deletionFailed(underlying: error)
        }

        modelContext.delete(model)
        try? modelContext.save()

        Self.logger.info("Model deleted: \(model.name)")
    }

    // MARK: - Storage

    func storageUsage(modelContext: ModelContext) -> StorageReport {
        let descriptor = FetchDescriptor<InstalledModel>()
        let models = (try? modelContext.fetch(descriptor)) ?? []

        let breakdown = models.map { (name: $0.name, bytes: $0.sizeBytes) }
        let total = breakdown.reduce(Int64(0)) { $0 + $1.bytes }

        return StorageReport(totalBytes: total, modelBreakdown: breakdown)
    }

    // MARK: - Private Helpers

    private func fetchRepoFiles(repo: String) async throws -> [HFRepoFile] {
        let urlString = "https://huggingface.co/api/models/\(repo)"
        guard let url = URL(string: urlString) else {
            throw ModelManagerError.repoNotFound(repo: repo)
        }

        let session = URLSession(configuration: .ephemeral)
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelManagerError.networkUnavailable
        }

        if httpResponse.statusCode == 404 {
            throw ModelManagerError.repoNotFound(repo: repo)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ModelManagerError.networkUnavailable
        }

        struct HFModelResponse: Decodable {
            let siblings: [HFRepoFile]?
        }

        let modelResponse = try JSONDecoder().decode(HFModelResponse.self, from: data)
        return modelResponse.siblings ?? []
    }

    private func checkDiskSpace(required: Int64) throws {
        let attrs = try FileManager.default.attributesOfFileSystem(
            forPath: modelsDirectory.path
        )
        guard let available = attrs[.systemFreeSize] as? Int64 else { return }

        if available < required {
            throw ModelManagerError.insufficientDiskSpace(required: required, available: available)
        }
    }

    private func computeSHA256(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1MB chunks
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: bufferSize)
            guard !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func parseQuantization(from modelDir: URL) -> String? {
        let configURL = modelDir.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let quantConfig = json["quantization_config"] as? [String: Any],
           let bits = quantConfig["bits"] as? Int {
            return "\(bits)bit"
        }

        return nil
    }
}
