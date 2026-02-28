import Foundation
import SwiftData
import os

struct MeetingSnippet: Sendable {
    let meetingID: PersistentIdentifier
    let title: String
    let date: Date
    let relevanceScore: Double
    let snippet: String
}

enum ContextInjectionError: Error, LocalizedError, Sendable {
    case swiftDataQueryFailed(underlying: any Error)
    case tokenizationUnavailable

    var errorDescription: String? {
        switch self {
        case .swiftDataQueryFailed(let error):
            "Meeting search failed: \(error.localizedDescription)"
        case .tokenizationUnavailable:
            "Cannot count tokens — no LLM model is loaded."
        }
    }
}

@Observable
@MainActor
final class ContextInjectionService {
    static let logger = Logger(subsystem: "com.scribeflowpro", category: "ContextInjection")

    /// Search past meetings by keywords, ranked by term-frequency.
    func searchMeetings(
        keywords: [String],
        limit: Int = 10,
        modelContext: ModelContext
    ) -> [MeetingSnippet] {
        guard !keywords.isEmpty else { return [] }

        Self.logger.debug("Searching meetings for keywords: \(keywords.joined(separator: ", "))")

        // Fetch all meetings (SwiftData #Predicate doesn't support dynamic OR over arrays easily)
        var descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 500

        guard let meetings = try? modelContext.fetch(descriptor) else { return [] }

        // Score and rank by keyword frequency
        var scored: [(meeting: Meeting, score: Double, bestSnippet: String)] = []

        for meeting in meetings {
            let searchText = (meeting.rawTranscript + " " + (meeting.summary ?? "")).lowercased()
            var hitCount = 0
            var bestMatchIndex: String.Index?

            for keyword in keywords {
                let lowKeyword = keyword.lowercased()
                var searchRange = searchText.startIndex..<searchText.endIndex
                while let range = searchText.range(of: lowKeyword, range: searchRange) {
                    hitCount += 1
                    if bestMatchIndex == nil {
                        bestMatchIndex = range.lowerBound
                    }
                    searchRange = range.upperBound..<searchText.endIndex
                }
            }

            guard hitCount > 0 else { continue }

            // Extract 200-char snippet around best match
            let snippet: String
            if let matchIdx = bestMatchIndex {
                let start = searchText.index(matchIdx, offsetBy: -100, limitedBy: searchText.startIndex) ?? searchText.startIndex
                let end = searchText.index(matchIdx, offsetBy: 100, limitedBy: searchText.endIndex) ?? searchText.endIndex
                snippet = String(searchText[start..<end])
            } else {
                snippet = String(searchText.prefix(200))
            }

            // TF-style score: hitCount normalized by document length
            let docLen = max(searchText.count, 1)
            let score = Double(hitCount) / log2(Double(docLen) + 1)

            scored.append((meeting, score, snippet))
        }

        // Sort by relevance
        scored.sort { $0.score > $1.score }

        return scored.prefix(limit).map { item in
            MeetingSnippet(
                meetingID: item.meeting.persistentModelID,
                title: item.meeting.title,
                date: item.meeting.date,
                relevanceScore: item.score,
                snippet: item.bestSnippet
            )
        }
    }
}
