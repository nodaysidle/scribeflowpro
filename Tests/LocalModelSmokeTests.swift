import Foundation
import Testing
@testable import ScribeFlowPro

@Test func localMLXModelsSmoke() async throws {
    guard ProcessInfo.processInfo.environment["SFP_LOCAL_MODEL_SMOKE"] == "1" else {
        return
    }

    let whisperID = ProcessInfo.processInfo.environment["SFP_SMOKE_WHISPER_MODEL"]
        ?? "mlx-community/whisper-tiny-mlx-q4"
    let llmID = ProcessInfo.processInfo.environment["SFP_SMOKE_LLM_MODEL"]
        ?? "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
    let audioPath = ProcessInfo.processInfo.environment["SFP_SMOKE_AUDIO"]
        ?? "/tmp/scribeflowpro-smoke.wav"

    #expect(ModelPathResolver.existingDirectory(for: whisperID) != nil)
    #expect(ModelPathResolver.existingDirectory(for: llmID) != nil)

    let whisper = WhisperTranscriptionActor()
    try await whisper.loadModel(modelID: whisperID)
    let chunks = try await whisper.transcribe(audioFileURL: URL(fileURLWithPath: audioPath))
    let transcript = chunks.map(\.text).joined(separator: " ").lowercased()
    print("SFP_SMOKE_TRANSCRIPT=\(transcript)")
    #expect(transcript.contains("scribe") || transcript.contains("flow") || transcript.contains("offline"))

    let llm = LLMInferenceActor()
    try await llm.loadModel(modelID: llmID)
    let prompt = "Summarize this meeting transcript in one short sentence: ScribeFlow Pro verified offline transcription and local summarization."
    let stream = await llm.generate(prompt: prompt, maxTokens: 64, temperature: 0.0)
    var summary = ""
    for await token in stream {
        summary += token
    }
    print("SFP_SMOKE_SUMMARY=\(summary)")
    #expect(!summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}
