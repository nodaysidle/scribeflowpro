import os

extension Logger {
    static let audio = Logger(subsystem: "com.scribeflowpro", category: "AudioCapture")
    static let transcription = Logger(subsystem: "com.scribeflowpro", category: "Transcription")
    static let llm = Logger(subsystem: "com.scribeflowpro", category: "LLMInference")
    static let session = Logger(subsystem: "com.scribeflowpro", category: "SessionOrchestrator")
    static let models = Logger(subsystem: "com.scribeflowpro", category: "ModelManager")
    static let data = Logger(subsystem: "com.scribeflowpro", category: "DataLayer")
    static let summarization = Logger(subsystem: "com.scribeflowpro", category: "Summarization")
}
