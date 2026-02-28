import SwiftUI

struct LiveTranscriptionView: View {
    let chunks: [TranscriptChunk]
    var whisperModelName: String? = nil
    var inferenceLatency: TimeInterval? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("Live Transcription")
                    .font(.subheadline.bold())

                Spacer()

                if let modelName = whisperModelName {
                    Text(modelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let latency = inferenceLatency {
                    Text("\(String(format: "%.1f", latency))s/window")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Transcript content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(chunks) { chunk in
                            TranscriptChunkRow(chunk: chunk)
                                .id(chunk.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: chunks.count) { _, _ in
                    if let lastID = chunks.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Chunk Row

private struct TranscriptChunkRow: View {
    let chunk: TranscriptChunk

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Speaker badge
            Circle()
                .fill(speakerColor)
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(chunk.speakerLabel)
                        .font(.caption.bold())
                        .foregroundStyle(speakerColor)

                    Text(formatTimeRange(start: chunk.startTime, end: chunk.endTime))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }

                Text(chunk.text)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
        .opacity(chunk.isFinal ? 1.0 : 0.6)
    }

    private var speakerColor: Color {
        let colors: [Color] = [
            .blue, .green, .orange, .purple,
            .pink, .teal, .indigo, .mint,
        ]
        let index = speakerIndex(from: chunk.speakerLabel)
        return colors[index % colors.count]
    }

    private func speakerIndex(from label: String) -> Int {
        // "Speaker A" -> 0, "Speaker B" -> 1, etc.
        guard let lastChar = label.last,
              let asciiValue = lastChar.asciiValue else { return 0 }
        return Int(asciiValue) - Int(Character("A").asciiValue!)
    }

    private func formatTimeRange(start: TimeInterval, end: TimeInterval) -> String {
        let startMin = Int(start) / 60
        let startSec = Int(start) % 60
        let endMin = Int(end) / 60
        let endSec = Int(end) % 60
        return String(format: "%02d:%02d – %02d:%02d", startMin, startSec, endMin, endSec)
    }
}
