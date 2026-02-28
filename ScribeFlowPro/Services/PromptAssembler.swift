import Foundation

enum PromptTask: Sendable {
    case summarize
    case actionItems
    case question(String)
    case custom(String)
}

struct PromptAssembler {

    /// Assemble a full prompt in [System][Historical Context][Transcript][Task] format,
    /// truncating historical context to stay within `contextBudget` tokens.
    ///
    /// - Parameters:
    ///   - task: The type of prompt to generate
    ///   - transcript: Current meeting transcript
    ///   - snippets: Historical meeting snippets ranked by relevance
    ///   - contextBudget: Max tokens for historical context section
    ///   - tokenCounter: Closure that counts tokens in a string (from LLMInferenceActor)
    static func assemblePrompt(
        task: PromptTask,
        transcript: String,
        snippets: [MeetingSnippet] = [],
        contextBudget: Int = 2048,
        tokenCounter: ((String) -> Int)? = nil
    ) -> String {
        let countTokens = tokenCounter ?? { $0.count / 4 } // rough fallback

        // 1. System instruction
        let systemInstruction = systemPrompt(for: task)

        // 2. Historical context — fit within budget
        let historicalContext = buildHistoricalContext(
            snippets: snippets,
            budget: contextBudget,
            tokenCounter: countTokens
        )

        // 3. Task instruction
        let taskInstruction = taskPrompt(for: task)

        // 4. Assemble
        var parts: [String] = []
        parts.append(systemInstruction)

        if !historicalContext.isEmpty {
            parts.append("## Relevant Historical Context\n\n\(historicalContext)")
        }

        parts.append("## Current Transcript\n\n\(transcript)")
        parts.append(taskInstruction)

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Private

    private static func systemPrompt(for task: PromptTask) -> String {
        switch task {
        case .summarize:
            "You are a meeting assistant. Analyze the transcript and produce a clear, structured summary with key points, decisions, and takeaways."
        case .actionItems:
            "You are a meeting assistant. Extract all action items from the transcript. Format each as a checkbox list item with the responsible person if mentioned."
        case .question:
            "You are a meeting assistant with access to the current transcript and relevant historical meeting context. Answer the user's question accurately based on the available information."
        case .custom:
            "You are a meeting assistant. Follow the user's instructions carefully based on the provided transcript."
        }
    }

    private static func taskPrompt(for task: PromptTask) -> String {
        switch task {
        case .summarize:
            "## Task\n\nSummarize the meeting above into key points, decisions made, and important discussion topics."
        case .actionItems:
            "## Task\n\nExtract all action items from the transcript above. Format as a markdown checklist."
        case .question(let q):
            "## Question\n\n\(q.prefix(500))"
        case .custom(let instruction):
            "## Task\n\n\(instruction.prefix(500))"
        }
    }

    private static func buildHistoricalContext(
        snippets: [MeetingSnippet],
        budget: Int,
        tokenCounter: (String) -> Int
    ) -> String {
        guard !snippets.isEmpty else { return "" }

        var result = ""
        var tokensUsed = 0
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        for snippet in snippets {
            let entry = "**\(snippet.title)** (\(dateFormatter.string(from: snippet.date))): \(snippet.snippet)\n\n"
            let entryTokens = tokenCounter(entry)

            if tokensUsed + entryTokens > budget {
                break
            }

            result += entry
            tokensUsed += entryTokens
        }

        return result
    }
}
