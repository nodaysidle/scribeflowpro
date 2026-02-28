import SwiftUI
import SwiftData
import MarkdownUI

struct MeetingDetailView: View {
    let meeting: Meeting
    @Environment(\.modelContext) private var modelContext

    @State private var showSummaryStream = false
    @State private var streamedSummary = ""
    @State private var questionText = ""
    @State private var answerStream: AsyncStream<String>?
    @State private var streamedAnswer = ""

    private let summarizationService = SummarizationService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Metadata header
                metadataHeader

                Divider()

                // Summary section
                summarySection

                // Action items section
                actionItemsSection

                Divider()

                // Transcript
                transcriptSection
            }
            .padding()
        }
        .navigationTitle(meeting.title)
    }

    // MARK: - Sections

    @ViewBuilder
    private var metadataHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.date, style: .date)
                    .font(.subheadline)
                Text(meeting.date, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text("Duration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formattedDuration)
                    .font(.subheadline.monospaced())
            }

            if !meeting.participants.isEmpty {
                Divider().frame(height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Participants")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(meeting.participants.joined(separator: ", "))
                        .font(.subheadline)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Summary")
                    .font(.title3.bold())
                Spacer()

                if meeting.summary == nil && !showSummaryStream {
                    Button("Summarize") {
                        showSummaryStream = true
                        let stream = summarizationService.summarizeMeeting(
                            meeting: meeting,
                            modelContext: modelContext
                        )
                        Task {
                            for await token in stream {
                                streamedSummary += token
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if let summary = meeting.summary {
                Markdown(summary)
                    .markdownTextStyle {
                        FontSize(14)
                    }
            } else if showSummaryStream {
                if streamedSummary.isEmpty {
                    ProgressView("Generating summary...")
                        .controlSize(.small)
                } else {
                    Markdown(streamedSummary)
                        .markdownTextStyle {
                            FontSize(14)
                        }
                }
            } else {
                Text("No summary yet. Click Summarize to generate one.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actionItemsSection: some View {
        if let actionItems = meeting.actionItems, !actionItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Action Items")
                    .font(.title3.bold())

                Markdown(actionItems)
                    .markdownTextStyle {
                        FontSize(14)
                    }
            }
        }
    }

    @ViewBuilder
    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript")
                .font(.title3.bold())

            if meeting.segments.isEmpty {
                Text(meeting.rawTranscript)
                    .font(.body)
                    .textSelection(.enabled)
            } else {
                let sortedSegments = meeting.segments.sorted { $0.timestamp < $1.timestamp }

                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(sortedSegments) { segment in
                        TranscriptSegmentRow(segment: segment)
                    }
                }
            }
        }

        // Q&A section
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("Ask a Question")
                .font(.title3.bold())

            HStack {
                TextField("Ask about this meeting...", text: $questionText)
                    .textFieldStyle(.roundedBorder)

                Button("Ask") {
                    let question = questionText
                    questionText = ""
                    streamedAnswer = ""
                    answerStream = summarizationService.askQuestion(
                        question: question,
                        meeting: meeting,
                        modelContext: modelContext
                    )
                    Task {
                        guard let stream = answerStream else { return }
                        for await token in stream {
                            streamedAnswer += token
                        }
                    }
                }
                .disabled(questionText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !streamedAnswer.isEmpty {
                Markdown(streamedAnswer)
                    .markdownTextStyle {
                        FontSize(14)
                    }
                    .padding(.top, 4)
            }
        }
    }

    private var formattedDuration: String {
        let totalSeconds = Int(meeting.duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Transcript Segment Row

private struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(speakerColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(segment.speakerLabel)
                        .font(.caption.bold())
                        .foregroundStyle(speakerColor)

                    Text(formatTimestamp(segment.timestamp))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }

                Text(segment.text)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
    }

    private var speakerColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint]
        let index = speakerIndex(from: segment.speakerLabel)
        return colors[index % colors.count]
    }

    private func speakerIndex(from label: String) -> Int {
        guard let lastChar = label.last,
              let asciiValue = lastChar.asciiValue else { return 0 }
        return Int(asciiValue) - Int(Character("A").asciiValue!)
    }

    private func formatTimestamp(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
