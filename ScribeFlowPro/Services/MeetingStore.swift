import Foundation
import SwiftData
import os

struct MeetingFilter: Sendable {
    var dateRange: ClosedRange<Date>?
    var searchText: String?
    var participants: [String]?
}

enum MeetingSortOrder: Sendable {
    case dateDescending
    case dateAscending
    case durationDescending
    case titleAscending
}

enum MeetingStoreError: Error, LocalizedError, Sendable {
    case saveFailed(underlying: any Error)
    case audioFileCopyFailed(underlying: any Error)
    case meetingNotFound
    case deleteFailed(underlying: any Error)
    case fetchFailed(underlying: any Error)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let e): "Failed to save meeting: \(e.localizedDescription)"
        case .audioFileCopyFailed(let e): "Failed to copy audio file: \(e.localizedDescription)"
        case .meetingNotFound: "Meeting not found."
        case .deleteFailed(let e): "Failed to delete meeting: \(e.localizedDescription)"
        case .fetchFailed(let e): "Failed to fetch meetings: \(e.localizedDescription)"
        }
    }
}

@Observable
@MainActor
final class MeetingStore {
    static let logger = Logger(subsystem: "com.scribeflowpro", category: "DataLayer")

    private let audioDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("ScribeFlowPro", isDirectory: true)
            .appendingPathComponent("Audio", isDirectory: true)
    }()

    init() {
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Save

    func saveMeeting(
        title: String?,
        date: Date,
        duration: TimeInterval,
        rawTranscript: String,
        segments: [TranscriptChunk],
        audioTempURL: URL?,
        modelContext: ModelContext
    ) throws -> Meeting {
        let meeting = Meeting(
            title: title,
            date: date,
            duration: duration,
            rawTranscript: rawTranscript,
            participants: Array(Set(segments.map(\.speakerLabel)))
        )

        // Copy audio to persistent storage
        if let tempURL = audioTempURL {
            let destURL = audioDirectory.appendingPathComponent("\(meeting.id.uuidString).wav")
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: tempURL, to: destURL)
                meeting.audioFilePath = "ScribeFlowPro/Audio/\(meeting.id.uuidString).wav"
            } catch {
                throw MeetingStoreError.audioFileCopyFailed(underlying: error)
            }
        }

        modelContext.insert(meeting)

        // Create TranscriptSegments
        for chunk in segments {
            let segment = TranscriptSegment(
                timestamp: chunk.startTime,
                endTimestamp: chunk.endTime,
                speakerLabel: chunk.speakerLabel,
                text: chunk.text,
                confidence: chunk.confidence,
                meeting: meeting
            )
            modelContext.insert(segment)
        }

        do {
            try modelContext.save()
        } catch {
            throw MeetingStoreError.saveFailed(underlying: error)
        }

        Self.logger.info("Saved meeting: \(meeting.title), \(segments.count) segments")
        return meeting
    }

    // MARK: - Delete

    func deleteMeeting(_ meeting: Meeting, modelContext: ModelContext) throws {
        // Remove audio file
        if let audioPath = meeting.audioFilePath {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let audioURL = appSupport.appendingPathComponent(audioPath)
            try? FileManager.default.removeItem(at: audioURL)
        }

        // SwiftData cascade handles segments
        modelContext.delete(meeting)

        do {
            try modelContext.save()
        } catch {
            throw MeetingStoreError.deleteFailed(underlying: error)
        }

        Self.logger.info("Deleted meeting: \(meeting.title)")
    }

    // MARK: - Fetch

    func fetchMeetings(
        filter: MeetingFilter? = nil,
        sortBy: MeetingSortOrder = .dateDescending,
        limit: Int? = nil,
        offset: Int? = nil,
        modelContext: ModelContext
    ) -> [Meeting] {
        var descriptor = FetchDescriptor<Meeting>()

        // Sort
        switch sortBy {
        case .dateDescending:
            descriptor.sortBy = [SortDescriptor(\.date, order: .reverse)]
        case .dateAscending:
            descriptor.sortBy = [SortDescriptor(\.date, order: .forward)]
        case .durationDescending:
            descriptor.sortBy = [SortDescriptor(\.duration, order: .reverse)]
        case .titleAscending:
            descriptor.sortBy = [SortDescriptor(\.title, order: .forward)]
        }

        // Pagination
        if let limit { descriptor.fetchLimit = limit }
        if let offset { descriptor.fetchOffset = offset }

        // Filter — SwiftData predicates with optional chaining
        if let filter {
            if let search = filter.searchText, !search.isEmpty {
                descriptor.predicate = #Predicate<Meeting> { meeting in
                    meeting.title.localizedStandardContains(search) ||
                    meeting.rawTranscript.localizedStandardContains(search)
                }
            }
        }

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Self.logger.error("Fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Update

    func updateMeeting(
        _ meeting: Meeting,
        summary: String? = nil,
        actionItems: String? = nil,
        title: String? = nil,
        modelContext: ModelContext
    ) throws {
        if let summary { meeting.summary = summary }
        if let actionItems { meeting.actionItems = actionItems }
        if let title { meeting.title = title }

        do {
            try modelContext.save()
        } catch {
            throw MeetingStoreError.saveFailed(underlying: error)
        }
    }
}
