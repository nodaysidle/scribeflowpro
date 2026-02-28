import SwiftUI
import SwiftData

struct ModelManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var installedModels: [InstalledModel]

    @State private var modelManager = ModelManagerService()
    @State private var repoInput = ""
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: InstalledModel?
    @State private var downloadError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Model Manager")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            // Model list
            List {
                if !modelManager.activeDownloads.isEmpty {
                    Section("Active Downloads") {
                        ForEach(Array(modelManager.activeDownloads.values), id: \.fileName) { progress in
                            DownloadProgressRow(progress: progress)
                        }
                    }
                }

                Section("Installed Models") {
                    if installedModels.isEmpty {
                        ContentUnavailableView(
                            "No Models",
                            systemImage: "arrow.down.circle",
                            description: Text("Download a model to get started.")
                        )
                    } else {
                        ForEach(installedModels) { model in
                            InstalledModelRow(model: model) {
                                modelToDelete = model
                                showDeleteConfirmation = true
                            }
                        }
                    }
                }

                Section("Storage") {
                    StorageSummaryView(
                        report: modelManager.storageUsage(modelContext: modelContext)
                    )
                }
            }
            .listStyle(.inset)

            Divider()

            // Download form
            HStack {
                TextField("Hugging Face repo (e.g. mlx-community/whisper-large-v3-mlx)", text: $repoInput)
                    .textFieldStyle(.roundedBorder)

                Button("Download") {
                    startDownload()
                }
                .disabled(repoInput.trimmingCharacters(in: .whitespaces).isEmpty || modelManager.isDownloading)
            }
            .padding()

            if let error = downloadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .confirmationDialog(
            "Delete Model",
            isPresented: $showDeleteConfirmation,
            presenting: modelToDelete
        ) { model in
            Button("Delete \(model.name)", role: .destructive) {
                deleteModel(model)
            }
        } message: { model in
            Text("This will permanently remove \(model.name) (\(ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file))) from disk.")
        }
    }

    private func startDownload() {
        let repo = repoInput.trimmingCharacters(in: .whitespaces)
        guard !repo.isEmpty else { return }
        downloadError = nil

        let stream = modelManager.downloadModel(repo: repo, modelContext: modelContext)
        Task {
            for await progress in stream {
                if case .failed(let error) = progress.status {
                    downloadError = error.localizedDescription
                }
            }
            repoInput = ""
        }
    }

    private func deleteModel(_ model: InstalledModel) {
        do {
            try modelManager.deleteModel(model, modelContext: modelContext)
        } catch {
            downloadError = error.localizedDescription
        }
        modelToDelete = nil
    }
}

// MARK: - Subviews

private struct DownloadProgressRow: View {
    let progress: DownloadProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(progress.fileName)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Spacer()
                statusBadge
            }

            ProgressView(value: progress.overallProgress)
                .tint(statusColor)

            HStack {
                Text(ByteCountFormatter.string(fromByteCount: progress.bytesDownloaded, countStyle: .file))
                Text("/")
                Text(ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch progress.status {
        case .downloading:
            Text("Downloading")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue.opacity(0.15), in: Capsule())
        case .verifying:
            Text("Verifying")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.15), in: Capsule())
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var statusColor: Color {
        switch progress.status {
        case .downloading: .blue
        case .verifying: .orange
        case .completed: .green
        case .failed: .red
        }
    }
}

private struct InstalledModelRow: View {
    let model: InstalledModel
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.headline)

                    Text(model.modelType == .whisper ? "Whisper" : "LLM")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            model.modelType == .whisper
                                ? Color.purple.opacity(0.15)
                                : Color.blue.opacity(0.15),
                            in: Capsule()
                        )

                    if let q = model.quantization {
                        Text(q)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Text(ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let lastUsed = model.lastUsed {
                        Text("Used \(lastUsed, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

private struct StorageSummaryView: View {
    let report: StorageReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Total Usage")
                    .font(.subheadline.bold())
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: report.totalBytes, countStyle: .file))
                    .font(.subheadline.monospaced())
            }

            if !report.modelBreakdown.isEmpty {
                ForEach(report.modelBreakdown, id: \.name) { item in
                    HStack {
                        Text(item.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()

                        // Bar proportional to total
                        let fraction = report.totalBytes > 0
                            ? CGFloat(item.bytes) / CGFloat(report.totalBytes)
                            : 0

                        RoundedRectangle(cornerRadius: 2)
                            .fill(.blue.opacity(0.3))
                            .frame(width: max(4, fraction * 150), height: 8)

                        Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
        }
    }
}
