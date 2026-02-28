import Foundation

/// Assigns speaker labels to transcript chunks using a silence-gap heuristic.
///
/// When the gap between consecutive chunks exceeds `gapThreshold` seconds,
/// the speaker label increments (Speaker A → Speaker B → ... → Speaker H),
/// cycling through a maximum of `maxSpeakers`.
struct SpeakerDiarizer: Sendable {
    let gapThreshold: TimeInterval
    let maxSpeakers: Int

    private static let speakerLabels = [
        "Speaker A", "Speaker B", "Speaker C", "Speaker D",
        "Speaker E", "Speaker F", "Speaker G", "Speaker H",
    ]

    init(gapThreshold: TimeInterval = 1.5, maxSpeakers: Int = 8) {
        self.gapThreshold = gapThreshold
        self.maxSpeakers = min(maxSpeakers, Self.speakerLabels.count)
    }

    /// Assigns speaker labels to a batch of chunks based on timing gaps.
    ///
    /// Maintains state across calls via `currentSpeakerIndex` and `lastEndTime`.
    /// Returns a new array of chunks with speaker labels assigned.
    func assignSpeakers(
        chunks: [TranscriptChunk],
        currentSpeakerIndex: inout Int,
        lastEndTime: inout TimeInterval
    ) -> [TranscriptChunk] {
        var result: [TranscriptChunk] = []

        for var chunk in chunks {
            if lastEndTime > 0 {
                let gap = chunk.startTime - lastEndTime
                if gap > gapThreshold {
                    currentSpeakerIndex = (currentSpeakerIndex + 1) % maxSpeakers
                }
            }

            chunk.speakerLabel = Self.speakerLabels[currentSpeakerIndex]
            lastEndTime = chunk.endTime
            result.append(chunk)
        }

        return result
    }

    /// Convenience for processing a single chunk in a streaming context.
    func assignSpeaker(
        chunk: TranscriptChunk,
        currentSpeakerIndex: inout Int,
        lastEndTime: inout TimeInterval
    ) -> TranscriptChunk {
        assignSpeakers(
            chunks: [chunk],
            currentSpeakerIndex: &currentSpeakerIndex,
            lastEndTime: &lastEndTime
        )[0]
    }
}
