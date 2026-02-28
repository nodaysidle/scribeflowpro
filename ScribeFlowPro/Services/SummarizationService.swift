import Foundation
import SwiftData
import os

@Observable
@MainActor
final class SummarizationService {
    static let logger = Logger(subsystem: "com.scribeflowpro", category: "Summarization")

    private let llmActor = LLMInferenceActor()
    private let contextService = ContextInjectionService()
    private let meetingStore = MeetingStore()

    private(set) var isSummarizing = false
    private(set) var isAnswering = false

    // MARK: - Summarize Meeting

    func summarizeMeeting(
        meeting: Meeting,
        modelContext: ModelContext
    ) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task { @MainActor in
                await self.runSummarization(
                    meeting: meeting,
                    modelContext: modelContext,
                    continuation: continuation
                )
            }
        }
    }

    private func runSummarization(
        meeting: Meeting,
        modelContext: ModelContext,
        continuation: AsyncStream<String>.Continuation
    ) async {
        guard await llmActor.isModelLoaded else {
            Self.logger.error("Summarization called without loaded LLM")
            continuation.finish()
            return
        }

        isSummarizing = true
        defer { isSummarizing = false }

        let transcript = meeting.rawTranscript
        let tokenCount = await llmActor.tokenCount(for: transcript)
        let contextWindow = await llmActor.contextWindowSize

        // Reserve tokens for system prompt + task instruction + generation
        let reservedTokens = 512
        let availableForTranscript = contextWindow - reservedTokens

        Self.logger.info("Summarizing: \(tokenCount) tokens, context window: \(contextWindow)")

        var fullSummary = ""

        if tokenCount <= availableForTranscript {
            // Single-pass summarization
            let prompt = PromptAssembler.assemblePrompt(
                task: .summarize,
                transcript: transcript,
                tokenCounter: { text in
                    // Synchronous fallback since we can't await inside closure
                    text.count / 4
                }
            )

            let stream = await llmActor.generate(prompt: prompt, maxTokens: 2048, temperature: 0.3)
            for await token in stream {
                fullSummary += token
                continuation.yield(token)
            }
        } else {
            // Chunked summarization: split, summarize each, merge
            let chunks = chunkTranscript(transcript, maxTokens: availableForTranscript)
            Self.logger.info("Chunked summarization: \(chunks.count) chunks")

            var chunkSummaries: [String] = []

            for (index, chunk) in chunks.enumerated() {
                let prompt = PromptAssembler.assemblePrompt(
                    task: .custom("Summarize part \(index + 1) of \(chunks.count) of this meeting transcript. Focus on key points and decisions."),
                    transcript: chunk
                )

                var chunkSummary = ""
                let stream = await llmActor.generate(prompt: prompt, maxTokens: 1024, temperature: 0.3)
                for await token in stream {
                    chunkSummary += token
                }
                chunkSummaries.append(chunkSummary)
            }

            // Merge pass
            let mergeTranscript = chunkSummaries.enumerated()
                .map { "**Part \($0.offset + 1):**\n\($0.element)" }
                .joined(separator: "\n\n")

            let mergePrompt = PromptAssembler.assemblePrompt(
                task: .custom("Merge these partial meeting summaries into a single coherent summary with key points, decisions, and takeaways."),
                transcript: mergeTranscript
            )

            let mergeStream = await llmActor.generate(prompt: mergePrompt, maxTokens: 2048, temperature: 0.3)
            for await token in mergeStream {
                fullSummary += token
                continuation.yield(token)
            }
        }

        // Save summary to meeting
        do {
            try meetingStore.updateMeeting(
                meeting,
                summary: fullSummary,
                modelContext: modelContext
            )
            Self.logger.info("Summary saved for meeting: \(meeting.title)")
        } catch {
            Self.logger.error("Failed to save summary: \(error.localizedDescription)")
        }

        continuation.finish()
    }

    // MARK: - Extract Action Items

    func extractActionItems(
        meeting: Meeting,
        modelContext: ModelContext
    ) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task { @MainActor in
                guard await self.llmActor.isModelLoaded else {
                    continuation.finish()
                    return
                }

                let prompt = PromptAssembler.assemblePrompt(
                    task: .actionItems,
                    transcript: meeting.rawTranscript
                )

                var fullResult = ""
                let stream = await self.llmActor.generate(prompt: prompt, maxTokens: 1024, temperature: 0.2)
                for await token in stream {
                    fullResult += token
                    continuation.yield(token)
                }

                do {
                    try self.meetingStore.updateMeeting(
                        meeting,
                        actionItems: fullResult,
                        modelContext: modelContext
                    )
                } catch {
                    Self.logger.error("Failed to save action items: \(error.localizedDescription)")
                }

                continuation.finish()
            }
        }
    }

    // MARK: - Ask Question

    func askQuestion(
        question: String,
        meeting: Meeting,
        modelContext: ModelContext
    ) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task { @MainActor in
                guard await self.llmActor.isModelLoaded else {
                    Self.logger.error("Q&A called without loaded LLM")
                    continuation.finish()
                    return
                }

                self.isAnswering = true
                defer { self.isAnswering = false }

                // Search for relevant historical context
                let keywords = question
                    .components(separatedBy: .whitespaces)
                    .filter { $0.count > 2 }

                let snippets = self.contextService.searchMeetings(
                    keywords: keywords,
                    limit: 5,
                    modelContext: modelContext
                )

                let tokenCounter: (String) -> Int = { text in
                    text.count / 4 // synchronous fallback
                }

                let prompt = PromptAssembler.assemblePrompt(
                    task: .question(question),
                    transcript: meeting.rawTranscript,
                    snippets: snippets,
                    contextBudget: 2048,
                    tokenCounter: tokenCounter
                )

                let stream = await self.llmActor.generate(prompt: prompt, maxTokens: 1024, temperature: 0.3)
                for await token in stream {
                    continuation.yield(token)
                }

                continuation.finish()
            }
        }
    }

    // MARK: - LLM Model

    func loadLLM(modelID: String) async throws {
        try await llmActor.loadModel(modelID: modelID)
    }

    var isLLMLoaded: Bool {
        get async { await llmActor.isModelLoaded }
    }

    // MARK: - Private

    private func chunkTranscript(_ transcript: String, maxTokens: Int) -> [String] {
        let words = transcript.components(separatedBy: .whitespaces)
        let wordsPerChunk = maxTokens * 3 // rough: 1 token ≈ 0.75 words → 3 words ≈ 4 tokens → use 3x for safety

        var chunks: [String] = []
        var currentStart = 0

        while currentStart < words.count {
            let end = min(currentStart + wordsPerChunk, words.count)
            let chunk = words[currentStart..<end].joined(separator: " ")
            chunks.append(chunk)
            currentStart = end
        }

        return chunks
    }
}
