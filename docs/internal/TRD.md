# Technical Requirements Document

## 🧭 System Context
ScribeFlow Pro is a single-process, single-window macOS application (macOS 15+, Apple Silicon only) built in Swift 6 and SwiftUI 6. It captures live audio, transcribes in real time via MLX-optimized Whisper, summarizes with locally-run LLMs via MLX Swift, and persists all data in SwiftData. Fully offline after initial model download from Hugging Face. No backend, no cloud, no network calls during operation. Layered architecture: UI Layer (SwiftUI 6 + Observation), Service Layer (Swift actors), Data Layer (SwiftData + file system). All ML inference on background actors using Structured Concurrency with streamed results to main thread.

## 🔌 API Contracts
### AudioCaptureActor.startCapture
- **Method:** ACTOR_METHOD
- **Path:** AudioCaptureActor.startCapture(inputDevice: AudioDevice?) -> AsyncStream<AVAudioPCMBuffer>
- **Auth:** macOS microphone permission (NSMicrophoneUsageDescription). Prompts user on first call via AVCaptureDevice.requestAccess(for: .audio).
- **Request:** Optional AudioDevice struct specifying input device (nil = system default). AudioDevice contains id: String, name: String, sampleRate: Double.
- **Response:** AsyncStream<AVAudioPCMBuffer> emitting 16kHz mono Float32 PCM buffers of 480 samples (~30ms) each. Stream completes when stopCapture() is called.
- **Errors:** AudioCaptureError.permissionDenied — microphone access not granted, AudioCaptureError.deviceUnavailable — selected input device not found or disconnected, AudioCaptureError.engineStartFailed(underlying: Error) — AVAudioEngine failed to start, AudioCaptureError.formatConversionFailed — cannot convert device format to 16kHz mono Float32

### AudioCaptureActor.stopCapture
- **Method:** ACTOR_METHOD
- **Path:** AudioCaptureActor.stopCapture() async
- **Auth:** None — only callable after startCapture.
- **Request:** No parameters.
- **Response:** Void. Completes the AsyncStream from startCapture, stops AVAudioEngine, releases audio tap. Saves raw audio to a temporary .wav file at FileManager.default.temporaryDirectory and returns the URL via a completion property audioFileURL: URL?.
- **Errors:** AudioCaptureError.notCapturing — stopCapture called without an active capture session

### AudioCaptureActor.listInputDevices
- **Method:** ACTOR_METHOD
- **Path:** AudioCaptureActor.listInputDevices() -> [AudioDevice]
- **Auth:** None.
- **Request:** No parameters.
- **Response:** Array of AudioDevice structs: [AudioDevice(id: String, name: String, sampleRate: Double, isDefault: Bool)]. Queries Core Audio via AVAudioSession or AudioObjectGetPropertyData for kAudioHardwarePropertyDevices.
- **Errors:** AudioCaptureError.deviceEnumerationFailed — Core Audio property query failed

### WhisperTranscriptionActor.transcribe
- **Method:** ACTOR_METHOD
- **Path:** WhisperTranscriptionActor.transcribe(audioStream: AsyncStream<AVAudioPCMBuffer>, modelID: String) -> AsyncStream<TranscriptChunk>
- **Auth:** None. Model must be downloaded and available at ~/Models/{modelID}/.
- **Request:** audioStream: AsyncStream<AVAudioPCMBuffer> from AudioCaptureActor. modelID: String identifying the Whisper model directory name (e.g., 'whisper-large-v3-mlx'). Internally accumulates buffers into 30-second sliding windows with 5-second overlap for continuous transcription.
- **Response:** AsyncStream<TranscriptChunk> where TranscriptChunk contains: text: String, startTime: TimeInterval, endTime: TimeInterval, speakerLabel: String (assigned via timestamp-gap heuristic: silence > 1.5s triggers speaker change, labels are 'Speaker A', 'Speaker B', etc.), confidence: Float (0.0–1.0 from Whisper logprobs), isFinal: Bool (true when the segment is confirmed after the next window overlaps).
- **Errors:** TranscriptionError.modelNotFound(modelID: String) — model directory does not exist at ~/Models/, TranscriptionError.modelLoadFailed(underlying: Error) — MLX failed to load Whisper weights, TranscriptionError.inferenceError(underlying: Error) — MLX inference threw during decoding, TranscriptionError.invalidAudioFormat — PCM buffer format does not match expected 16kHz mono Float32

### WhisperTranscriptionActor.loadModel
- **Method:** ACTOR_METHOD
- **Path:** WhisperTranscriptionActor.loadModel(modelID: String) async throws
- **Auth:** None.
- **Request:** modelID: String. Pre-loads the Whisper model into MLX unified memory before transcription starts. Called during app warm-up or when user switches model.
- **Response:** Void on success. Model weights loaded into MLX array cache. Subsequent transcribe() calls skip model loading.
- **Errors:** TranscriptionError.modelNotFound(modelID: String), TranscriptionError.modelLoadFailed(underlying: Error), TranscriptionError.insufficientMemory — estimated model size exceeds available unified memory

### LLMInferenceActor.generate
- **Method:** ACTOR_METHOD
- **Path:** LLMInferenceActor.generate(prompt: String, maxTokens: Int, temperature: Float, stopSequences: [String]) -> AsyncStream<String>
- **Auth:** None. Model must be loaded via loadModel() first.
- **Request:** prompt: String (assembled by ContextInjectionService or SummarizationService). maxTokens: Int (default 2048, max 8192). temperature: Float (default 0.3 for summarization, 0.7 for Q&A). stopSequences: [String] (e.g., ['</summary>', '---'] for structured output termination).
- **Response:** AsyncStream<String> emitting individual tokens as they are generated. Stream completes when maxTokens reached, a stop sequence is encountered, or EOS token generated. Final token is an empty string sentinel.
- **Errors:** LLMError.noModelLoaded — generate called before loadModel(), LLMError.contextWindowExceeded(promptTokens: Int, maxContext: Int) — prompt exceeds model context window after tokenization, LLMError.inferenceError(underlying: Error) — MLX runtime error during generation, LLMError.cancelled — Task was cancelled via structured concurrency

### LLMInferenceActor.loadModel
- **Method:** ACTOR_METHOD
- **Path:** LLMInferenceActor.loadModel(modelID: String) async throws
- **Auth:** None.
- **Request:** modelID: String matching an InstalledModel name in SwiftData. Loads MLX-format weights from ~/Models/{modelID}/ into unified memory. Unloads any previously loaded model first.
- **Response:** Void on success. Reports loaded model metadata: contextWindowSize: Int, parameterCount: String, quantization: String.
- **Errors:** LLMError.modelNotFound(modelID: String), LLMError.modelLoadFailed(underlying: Error), LLMError.insufficientMemory, LLMError.unsupportedModelFormat — model directory lacks required config.json or weights

### LLMInferenceActor.tokenCount
- **Method:** ACTOR_METHOD
- **Path:** LLMInferenceActor.tokenCount(for text: String) async -> Int
- **Auth:** None. Model must be loaded.
- **Request:** text: String to tokenize.
- **Response:** Int — number of tokens the loaded model's tokenizer produces for the input text. Used by ContextInjectionService to budget context window.
- **Errors:** LLMError.noModelLoaded

### ContextInjectionService.assemblePrompt
- **Method:** SERVICE_METHOD
- **Path:** ContextInjectionService.assemblePrompt(task: PromptTask, currentTranscript: String, contextBudget: Int) async -> String
- **Auth:** None.
- **Request:** task: PromptTask enum (.summarize, .actionItems, .question(String), .custom(String)). currentTranscript: String (the full or chunked transcript text). contextBudget: Int (max tokens available for injected historical context, typically contextWindow - promptTemplate - currentTranscript - maxOutputTokens).
- **Response:** String — fully assembled prompt with system instruction, injected historical context snippets (ranked by keyword relevance, capped to contextBudget), and the current transcript. Format: [System Instruction]\n\n[Historical Context Block]\n\n[Current Transcript]\n\n[Task Instruction].
- **Errors:** ContextInjectionError.swiftDataQueryFailed(underlying: Error) — FetchDescriptor query failed, ContextInjectionError.tokenizationUnavailable — LLMInferenceActor not loaded, cannot count tokens

### ContextInjectionService.searchMeetings
- **Method:** SERVICE_METHOD
- **Path:** ContextInjectionService.searchMeetings(keywords: [String], limit: Int) async -> [MeetingSnippet]
- **Auth:** None.
- **Request:** keywords: [String] extracted from current transcript or user query. limit: Int (default 10). Performs SwiftData FetchDescriptor with #Predicate using case-insensitive contains matching on Meeting.rawTranscript and Meeting.summary fields. Results sorted by keyword hit count (BM25-style: tf = keyword frequency in document, no idf for simplicity).
- **Response:** Array of MeetingSnippet: [MeetingSnippet(meetingID: PersistentIdentifier, title: String, date: Date, relevanceScore: Double, snippet: String)]. snippet is a 200-character window around the best keyword match.
- **Errors:** ContextInjectionError.swiftDataQueryFailed(underlying: Error)

### ModelManagerService.downloadModel
- **Method:** SERVICE_METHOD
- **Path:** ModelManagerService.downloadModel(repo: String, revision: String?) -> AsyncStream<DownloadProgress>
- **Auth:** None for public Hugging Face repos. Optional HF_TOKEN environment variable for gated models.
- **Request:** repo: String (Hugging Face repo ID, e.g., 'mlx-community/whisper-large-v3-mlx'). revision: String? (git ref, default 'main'). Downloads all files from the repo to ~/Models/{repoName}/ using URLSession with resumable downloads (If-Range / Range headers). Creates ~/Models/ directory if it does not exist.
- **Response:** AsyncStream<DownloadProgress> where DownloadProgress contains: fileName: String, bytesDownloaded: Int64, totalBytes: Int64, overallProgress: Double (0.0–1.0), status: DownloadStatus (.downloading, .verifying, .completed, .failed(Error)). Stream completes when all files downloaded or an unrecoverable error occurs.
- **Errors:** ModelManagerError.networkUnavailable — no internet connection detected, ModelManagerError.repoNotFound(repo: String) — Hugging Face returned 404, ModelManagerError.downloadFailed(fileName: String, underlying: Error) — individual file download failed after 3 retries, ModelManagerError.insufficientDiskSpace(required: Int64, available: Int64), ModelManagerError.integrityCheckFailed(fileName: String) — SHA256 mismatch after download

### ModelManagerService.listInstalledModels
- **Method:** SERVICE_METHOD
- **Path:** ModelManagerService.listInstalledModels() async -> [InstalledModel]
- **Auth:** None.
- **Request:** No parameters. Queries SwiftData for all InstalledModel entities.
- **Response:** Array of InstalledModel entities with name, huggingFaceRepo, filePath, sizeBytes, lastUsed, modelType (.whisper, .llm).
- **Errors:** ModelManagerError.swiftDataQueryFailed(underlying: Error)

### ModelManagerService.deleteModel
- **Method:** SERVICE_METHOD
- **Path:** ModelManagerService.deleteModel(modelID: PersistentIdentifier) async throws
- **Auth:** None.
- **Request:** modelID: PersistentIdentifier of the InstalledModel to delete. Removes the model directory from ~/Models/ and deletes the SwiftData entity. If the model is currently loaded in WhisperTranscriptionActor or LLMInferenceActor, it is unloaded first.
- **Response:** Void on success. Reclaimed disk space reported via notification.
- **Errors:** ModelManagerError.modelNotFound, ModelManagerError.deletionFailed(underlying: Error) — file system removal failed, ModelManagerError.modelInUse — model is actively being used for inference; user must stop session first

### MeetingStore.saveMeeting
- **Method:** SERVICE_METHOD
- **Path:** MeetingStore.saveMeeting(_ meeting: Meeting) async throws
- **Auth:** None.
- **Request:** Meeting @Model instance with populated fields. Inserts into SwiftData ModelContext and saves. Associates TranscriptSegments via relationship. Copies temporary audio file to persistent storage at Application Support/ScribeFlowPro/Audio/{meetingID}.wav.
- **Response:** Void on success. Meeting persisted with PersistentIdentifier assigned by SwiftData.
- **Errors:** MeetingStoreError.saveFailed(underlying: Error) — SwiftData save threw, MeetingStoreError.audioFileCopyFailed(underlying: Error) — file copy to persistent storage failed

### MeetingStore.deleteMeeting
- **Method:** SERVICE_METHOD
- **Path:** MeetingStore.deleteMeeting(_ meetingID: PersistentIdentifier) async throws
- **Auth:** None.
- **Request:** meetingID: PersistentIdentifier. Deletes Meeting, cascades to TranscriptSegments, removes audio file from disk.
- **Response:** Void on success.
- **Errors:** MeetingStoreError.meetingNotFound, MeetingStoreError.deleteFailed(underlying: Error)

### MeetingStore.fetchMeetings
- **Method:** SERVICE_METHOD
- **Path:** MeetingStore.fetchMeetings(filter: MeetingFilter?, sortBy: MeetingSortOrder, limit: Int?, offset: Int?) async -> [Meeting]
- **Auth:** None.
- **Request:** filter: Optional MeetingFilter with dateRange: ClosedRange<Date>?, searchText: String?, participants: [String]?. sortBy: MeetingSortOrder enum (.dateDescending, .dateAscending, .durationDescending, .titleAscending). limit: Int? for pagination (default nil = all). offset: Int? for pagination.
- **Response:** Array of Meeting entities. Lazy-loaded — TranscriptSegments are faulted and loaded only on access.
- **Errors:** MeetingStoreError.fetchFailed(underlying: Error)

## 🧱 Modules
### AudioCapture
- **Responsibilities:**
- Capture live microphone audio via AVAudioEngine with an input node tap
- Convert captured audio to 16kHz mono Float32 PCM format for Whisper compatibility
- Enumerate available audio input devices via Core Audio
- Stream PCM buffers as AsyncStream to the transcription pipeline
- Handle microphone permission requests and denials gracefully
- Save raw captured audio to a temporary .wav file for later persistent storage
- Manage AVAudioEngine lifecycle (start, stop, reset) on a dedicated actor
- **Interfaces:**
- AudioCaptureActor: actor conforming to Sendable
- func startCapture(inputDevice: AudioDevice?) -> AsyncStream<AVAudioPCMBuffer>
- func stopCapture() async
- func listInputDevices() -> [AudioDevice]
- var isCapturing: Bool { get }
- var audioFileURL: URL? { get }
- struct AudioDevice: Sendable, Identifiable { id: String, name: String, sampleRate: Double, isDefault: Bool }
- **Dependencies:**
- AVFoundation
- CoreAudio

### Transcription
- **Responsibilities:**
- Load MLX-optimized Whisper model from local disk into unified memory
- Accept streamed PCM audio buffers and accumulate into 30-second inference windows
- Run Whisper inference via MLX Swift and emit timestamped transcript chunks
- Assign provisional speaker labels using timestamp-gap heuristics (>1.5s gap = new speaker)
- Provide confidence scores per segment derived from Whisper decoder logprobs
- Manage model lifecycle: load, warm-up, unload to free memory
- Stream TranscriptChunk results as AsyncStream with isFinal flag for confirmed segments
- **Interfaces:**
- WhisperTranscriptionActor: actor conforming to Sendable
- func loadModel(modelID: String) async throws
- func transcribe(audioStream: AsyncStream<AVAudioPCMBuffer>, modelID: String) -> AsyncStream<TranscriptChunk>
- func unloadModel() async
- var isModelLoaded: Bool { get }
- var loadedModelID: String? { get }
- struct TranscriptChunk: Sendable { text: String, startTime: TimeInterval, endTime: TimeInterval, speakerLabel: String, confidence: Float, isFinal: Bool }
- **Dependencies:**
- MLXSwift (apple/mlx-swift)
- AudioCapture

### LLMInference
- **Responsibilities:**
- Load MLX-format LLM weights (Llama 3, Mistral, Qwen, Phi) into unified memory
- Tokenize input prompts using the model's bundled tokenizer
- Generate tokens via autoregressive MLX inference on background actor
- Stream generated tokens as AsyncStream<String> for real-time UI display
- Enforce context window limits and report token counts for prompt budgeting
- Support stop sequences for structured output termination
- Handle model unloading and switching without memory leaks
- **Interfaces:**
- LLMInferenceActor: actor conforming to Sendable
- func loadModel(modelID: String) async throws
- func generate(prompt: String, maxTokens: Int, temperature: Float, stopSequences: [String]) -> AsyncStream<String>
- func tokenCount(for text: String) async -> Int
- func unloadModel() async
- var isModelLoaded: Bool { get }
- var loadedModelID: String? { get }
- var contextWindowSize: Int { get }
- **Dependencies:**
- MLXSwift (apple/mlx-swift)

### ContextInjection
- **Responsibilities:**
- Extract keywords from current transcript or user query for historical search
- Query SwiftData for relevant past meetings using keyword-based full-text matching
- Rank search results using BM25-style term frequency scoring
- Assemble LLM prompts with system instructions, historical context snippets, current transcript, and task instruction
- Budget injected context tokens to stay within the model's context window
- Support multiple prompt tasks: summarization, action items, Q&A, custom queries
- **Interfaces:**
- ContextInjectionService: @Observable class
- func assemblePrompt(task: PromptTask, currentTranscript: String, contextBudget: Int) async -> String
- func searchMeetings(keywords: [String], limit: Int) async -> [MeetingSnippet]
- enum PromptTask: Sendable { case summarize, actionItems, question(String), custom(String) }
- struct MeetingSnippet: Sendable { meetingID: PersistentIdentifier, title: String, date: Date, relevanceScore: Double, snippet: String }
- **Dependencies:**
- LLMInference
- DataLayer (SwiftData)

### ModelManager
- **Responsibilities:**
- Download MLX-format models from Hugging Face Hub to ~/Models/ with resumable downloads
- Track installed models, sizes, types, and last-used timestamps in SwiftData
- Verify download integrity via SHA256 checksums
- Provide model selection, deletion, and storage usage reporting
- Manage ~/Models/ directory creation and cleanup
- Coordinate with WhisperTranscriptionActor and LLMInferenceActor to unload models before deletion
- **Interfaces:**
- ModelManagerService: @Observable class
- func downloadModel(repo: String, revision: String?) -> AsyncStream<DownloadProgress>
- func deleteModel(modelID: PersistentIdentifier) async throws
- func listInstalledModels() async -> [InstalledModel]
- func storageUsage() async -> StorageReport
- struct DownloadProgress: Sendable { fileName: String, bytesDownloaded: Int64, totalBytes: Int64, overallProgress: Double, status: DownloadStatus }
- enum DownloadStatus: Sendable { case downloading, verifying, completed, failed(Error) }
- struct StorageReport: Sendable { totalBytes: Int64, modelBreakdown: [(name: String, bytes: Int64)] }
- **Dependencies:**
- Foundation (URLSession)
- DataLayer (SwiftData)
- Transcription (for unload coordination)
- LLMInference (for unload coordination)

### DataLayer
- **Responsibilities:**
- Define SwiftData @Model entities: Meeting, TranscriptSegment, SpeakerProfile, AppSettings, InstalledModel
- Configure ModelContainer with VersionedSchema and SchemaMigrationPlan
- Provide MeetingStore for CRUD operations with SwiftData FetchDescriptors
- Manage cascade delete rules for Meeting → TranscriptSegment relationship
- Handle audio file persistence at Application Support/ScribeFlowPro/Audio/
- Support pagination and filtering via predicate-based queries
- Enforce singleton pattern for AppSettings entity
- **Interfaces:**
- MeetingStore: @Observable class
- func saveMeeting(_ meeting: Meeting) async throws
- func deleteMeeting(_ meetingID: PersistentIdentifier) async throws
- func fetchMeetings(filter: MeetingFilter?, sortBy: MeetingSortOrder, limit: Int?, offset: Int?) async -> [Meeting]
- func updateMeeting(_ meetingID: PersistentIdentifier, summary: String?, actionItems: String?, title: String?) async throws
- func getSettings() async -> AppSettings
- func updateSettings(_ settings: AppSettings) async throws
- struct MeetingFilter: Sendable { dateRange: ClosedRange<Date>?, searchText: String?, participants: [String]? }
- enum MeetingSortOrder: Sendable { case dateDescending, dateAscending, durationDescending, titleAscending }
- **Dependencies:**
- SwiftData
- Foundation (FileManager)

### UILayer
- **Responsibilities:**
- Render single-window NavigationSplitView with sidebar (meeting history) and detail pane
- Display real-time streaming transcription via StreamingText view subscribed to AsyncSequence
- Show LLM output token-by-token using StreamingText view with typing animation
- Provide recording controls (start/stop, device selection) in the toolbar
- Display meeting review with formatted transcript, summary, and action items using swift-markdown-ui
- Present model management sheet with download progress, installed models, and storage usage
- Present settings sheet for audio input, prompt template, and model selection
- Implement Liquid-Glass aesthetic with subtle MeshGradient background shifts and opacity transitions
- Lazy-load meeting list via @Query with SwiftData FetchDescriptor pagination
- **Interfaces:**
- ScribeFlowApp: @main App struct with WindowGroup
- ContentView: NavigationSplitView root
- MeetingSidebarView: List with @Query lazy-loaded meetings
- LiveTranscriptionView: real-time transcript display with speaker labels
- MeetingDetailView: review mode with markdown-rendered summary
- StreamingTextView: generic view accepting AsyncStream<String> for token-by-token display
- ModelManagerView: sheet with download progress and installed model list
- SettingsView: sheet with audio device picker, model selector, prompt template editor
- RecordingToolbar: toolbar content with start/stop button and status indicator
- **Dependencies:**
- AudioCapture
- Transcription
- LLMInference
- ContextInjection
- ModelManager
- DataLayer
- swift-markdown-ui (gonzalezreal/swift-markdown-ui)

### SessionOrchestrator
- **Responsibilities:**
- Coordinate end-to-end meeting recording sessions: start capture → stream to transcription → collect segments → persist meeting
- Manage the pipeline of audio capture → transcription → optional real-time summarization
- Handle chunked summarization for transcripts exceeding LLM context window
- Trigger post-meeting summarization and action item extraction
- Coordinate model warm-up on app launch or before recording starts
- Manage structured concurrency task groups for parallel pipelines
- Handle cancellation and cleanup when user stops a session mid-recording
- **Interfaces:**
- SessionOrchestrator: @Observable class
- func startSession(inputDevice: AudioDevice?, whisperModelID: String) async throws
- func stopSession() async throws -> Meeting
- func summarizeMeeting(_ meeting: Meeting, llmModelID: String, task: PromptTask) -> AsyncStream<String>
- func askQuestion(about meeting: Meeting, question: String, llmModelID: String) -> AsyncStream<String>
- var sessionState: SessionState { get }
- enum SessionState: Sendable { case idle, recording(duration: TimeInterval), processing, error(Error) }
- **Dependencies:**
- AudioCapture
- Transcription
- LLMInference
- ContextInjection
- DataLayer

## 🗃 Data Model Notes
- @Model Meeting: id (UUID, auto-generated), title (String, default 'Meeting — {date formatted}'), date (Date), duration (TimeInterval), audioFilePath (String, relative path under Application Support/ScribeFlowPro/Audio/), rawTranscript (String, concatenated text of all segments), summary (String?, nil until summarization runs), actionItems (String?, markdown-formatted list), participants ([String], derived from unique speaker labels). Indexed on: date, title.

- @Model TranscriptSegment: id (UUID, auto-generated), timestamp (TimeInterval, start time in seconds from meeting start), endTimestamp (TimeInterval), speakerLabel (String, e.g., 'Speaker A'), text (String, the transcribed text), confidence (Float, 0.0–1.0), meeting (Meeting, inverse relationship, @Relationship(deleteRule: .cascade on Meeting side)).

- @Model SpeakerProfile: id (UUID), label (String, e.g., 'Speaker A'), displayName (String, user-editable friendly name), colorHex (String, 6-char hex for UI badge color). Standalone entity — referenced by TranscriptSegment.speakerLabel string match, not a SwiftData relationship. Reusable across meetings.

- @Model AppSettings: id (UUID, singleton), selectedWhisperModelID (String?), selectedLLMModelID (String?), audioInputDeviceID (String?), summarizationPromptTemplate (String, default system prompt for summarization), actionItemsPromptTemplate (String, default prompt for action item extraction), maxContextInjectionTokens (Int, default 2048). Singleton enforced by app logic — fetch first or create if empty.

- @Model InstalledModel: id (UUID), name (String, display name), huggingFaceRepo (String, e.g., 'mlx-community/whisper-large-v3-mlx'), filePath (String, absolute path to ~/Models/{name}/), sizeBytes (Int64), lastUsed (Date?), modelType (ModelType enum: .whisper, .llm), quantization (String?, e.g., '4bit', '8bit', nil for full precision).

- All @Model entities use SwiftData's auto-generated PersistentIdentifier. No manual primary key management.

- VersionedSchema V1 defines all initial entities. SchemaMigrationPlan with empty stages for V1. Future versions add stages to the plan for non-destructive migrations.

- ModelContainer configured with: ModelConfiguration(isStoredInMemoryOnly: false), groupContainer: .none (app-scoped storage in Application Support). AutosaveEnabled = true. No CloudKit integration.

- Audio files stored outside SwiftData at: FileManager.default.urls(for: .applicationSupportDirectory)[0]/ScribeFlowPro/Audio/{meetingID}.wav. Meeting.audioFilePath stores the relative path for portability.

## 🔐 Validation & Security
- Microphone permission: Check AVCaptureDevice.authorizationStatus(for: .audio) before starting capture. Request access if .notDetermined. Show alert directing user to System Settings > Privacy & Security > Microphone if .denied or .restricted.
- Model path validation: All file paths for model loading are resolved relative to ~/Models/ and validated with FileManager.fileExists. Directory traversal prevented by stripping path components containing '..' before resolution.
- Input sanitization for LLM prompts: User-provided question text in PromptTask.question(String) is truncated to 500 characters and stripped of control characters before prompt assembly. No injection risk since the LLM is local and non-networked, but prevents prompt bloat.
- SwiftData predicate injection: All SwiftData queries use #Predicate macros with compile-time type safety. No raw string predicates or NSPredicate(format:) with user input.
- Disk space validation: Before model download, check available disk space via FileManager.attributesOfFileSystem. Require 2x the estimated model size to account for temporary download files. Before audio recording, verify at least 500MB free.
- No outbound network requests during operation: URLSession configuration for model downloads uses a separate ephemeral session. The app's default URLSession is never configured. In release builds, a DEBUG assertion verifies no URLSession task is created outside ModelManagerService.
- Audio file cleanup: Temporary audio files in FileManager.temporaryDirectory are cleaned up in stopCapture() after successful copy to persistent storage. A background cleanup task on app launch removes orphaned temp audio files older than 24 hours.
- App Sandbox: The app runs sandboxed with entitlements for: com.apple.security.device.microphone (audio capture), com.apple.security.files.user-selected.read-write (~/Models/ access via security-scoped bookmark), com.apple.security.network.client (model download only).
- No telemetry, no analytics, no crash reporting services. Zero data exfiltration by design.

## 🧯 Error Handling Strategy
All errors are modeled as typed Swift enums conforming to Error and LocalizedError. Each module defines its own error enum (AudioCaptureError, TranscriptionError, LLMError, ContextInjectionError, ModelManagerError, MeetingStoreError). Errors propagate via Swift's native throw/try/catch through async actor boundaries. The SessionOrchestrator catches all service-layer errors and maps them to user-facing SessionState.error(Error) state, which the UI observes reactively. Non-recoverable errors (model load failure, disk full) present an alert with a localized description and a suggested action (e.g., 'Free disk space' or 'Re-download model'). Recoverable errors (transient inference errors, audio glitches) are logged and retried once before surfacing. Structured Concurrency task cancellation is propagated cleanly — all AsyncStream producers check for Task.isCancelled and terminate gracefully. SwiftData save errors trigger a retry-once strategy before alerting the user. No error is silently swallowed — all catch blocks either rethrow, retry, or report to the UI layer.

## 🔭 Observability
- **Logging:** os.Logger with subsystem 'com.scribeflowpro' and per-module categories: 'AudioCapture', 'Transcription', 'LLMInference', 'ContextInjection', 'ModelManager', 'DataLayer', 'Session'. Log levels: .debug for streaming buffer counts and token rates, .info for session lifecycle events (start/stop recording, model load/unload), .error for all caught errors with localizedDescription and underlying error chain. All logs viewable in Console.app with subsystem filter. No log data written to disk files — only os_log to unified logging system. Sensitive transcript text is never logged at .info or above; only at .debug level behind #if DEBUG.
- **Tracing:** No distributed tracing (single-process app). Session-level tracing via a sessionID (UUID) generated at startSession() and attached to all os.Logger messages for that session as metadata. Enables filtering all logs for a single recording session in Console.app. SignpostID-based os_signpost intervals for performance-critical sections: audio buffer processing, Whisper inference per window, LLM token generation per prompt. Viewable in Instruments > os_signpost.
- **Metrics:**
- Transcription latency: TimeInterval from audio buffer delivery to TranscriptChunk emission, logged per chunk at .debug level
- Token generation rate: tokens/second measured per generate() call, logged at .info level on stream completion
- Model load time: TimeInterval for loadModel() calls, logged at .info level
- Session duration: total recording time logged at .info on session stop
- Memory pressure: ProcessInfo.processInfo.physicalMemory vs. model size estimates, checked before model load and logged at .info
- SwiftData query duration: TimeInterval for fetchMeetings and searchMeetings, logged at .debug level
- Download throughput: bytes/second during model downloads, reported via DownloadProgress stream

## ⚡ Performance Notes
- Audio capture runs on a dedicated AudioCaptureActor to avoid blocking the main thread. AVAudioEngine tap callback dispatches buffers to the actor's AsyncStream continuation with .bufferingPolicy(.bufferingNewest(100)) to drop old buffers under backpressure rather than accumulating unbounded memory.
- Whisper inference processes 30-second audio windows. At ~1.5s inference time per window on M1, this provides real-time transcription with margin. The 5-second overlap between windows ensures no speech is lost at boundaries. On M4, inference drops to ~0.8s per window.
- LLM token generation targets 20+ tokens/second for 4-bit quantized 7B models on 16GB unified memory. The AsyncStream emits tokens individually for responsive UI updates. No batching of token emissions.
- StreamingTextView uses a @State String that appends each token via .task modifier observing the AsyncStream. SwiftUI diffing is efficient for append-only text mutations. The view uses a ScrollViewReader to auto-scroll to bottom on each token append.
- Meeting list sidebar uses @Query with FetchDescriptor configured with fetchLimit and fetchOffset for pagination. Only 50 meetings loaded initially; infinite scroll triggers next page fetch. TranscriptSegments are not fetched until the user selects a meeting (lazy faulting).
- Model loading into MLX unified memory is a one-time cost per session (5-15 seconds for 7B models). The app pre-loads the default Whisper model on launch in a background task. LLM model is loaded on first summarization request and kept in memory for subsequent uses.
- Chunked summarization for long transcripts: chunks are processed sequentially (not in parallel) to avoid doubling memory usage from concurrent LLM inference. Each chunk summary is ~200 tokens; the final merge pass concatenates chunk summaries and runs one more generation.
- MeshGradient background for Liquid-Glass effect uses SwiftUI's built-in MeshGradient view with 3x3 control points. Animation uses .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) on point positions — GPU-accelerated, zero CPU overhead, negligible memory impact.
- Circular buffer for audio: AudioCaptureActor maintains a ring buffer of the last 60 seconds of PCM data (16kHz * 60s * 4 bytes = ~3.8MB). This caps memory usage regardless of recording duration. Older data is written to the temp .wav file incrementally.
- SwiftData keyword search uses #Predicate with .localizedStandardContains() which leverages SQLite FTS under the hood. For 1000+ meetings, query returns in <1 second. No additional indexing infrastructure needed.
- Application cold launch target of <3 seconds achieved by deferring model loading to post-UI-render. The main window renders immediately with an empty state; model warm-up happens in a concurrent background task with a subtle loading indicator.

## 🧪 Testing Strategy
### Unit
- TranscriptChunk speaker diarization: Test timestamp-gap heuristic with mock audio timestamps. Verify speaker label changes on gaps >1.5s and label continuity within gaps. Edge cases: simultaneous end/start, zero-gap, very long silence.
- ContextInjectionService.searchMeetings: Test BM25-style ranking with mock SwiftData container containing known meetings. Verify keyword matching, relevance ordering, snippet extraction window, and result limit enforcement.
- ContextInjectionService.assemblePrompt: Test prompt assembly for each PromptTask case. Verify token budget adherence by mocking LLMInferenceActor.tokenCount. Verify historical context truncation when budget is tight.
- LLMInferenceActor.tokenCount: Test tokenization accuracy against known model tokenizer outputs for edge cases: empty string, Unicode, very long input, special characters.
- MeetingStore CRUD: Test save, fetch, update, delete with in-memory SwiftData ModelConfiguration. Verify cascade delete removes TranscriptSegments. Verify filter and sort combinations. Verify AppSettings singleton enforcement.
- ModelManagerService path validation: Test that model paths are correctly resolved under ~/Models/ and that path traversal attempts with '..' are sanitized.
- AudioDevice enumeration: Mock Core Audio device list and verify AudioCaptureActor.listInputDevices() returns correctly mapped AudioDevice structs.
- MeetingFilter predicate generation: Test that MeetingFilter produces correct #Predicate for each filter combination: date range only, search text only, participants only, all combined, none.
- DownloadProgress calculation: Test overallProgress computation across multiple files with varying sizes. Verify progress monotonically increases and reaches 1.0 on completion.
- Error enum localizedDescription: Verify all error cases in every error enum return meaningful, user-facing localized descriptions.
### Integration
- Audio → Transcription pipeline: Feed a known .wav file (short speech sample) through AudioCaptureActor → WhisperTranscriptionActor and verify TranscriptChunk output contains expected words within ±2 second timestamps. Requires MLX Whisper tiny model in test fixtures.
- Transcription → Persistence pipeline: Stream TranscriptChunks from a mock transcription actor into MeetingStore. Verify Meeting and TranscriptSegment entities are correctly persisted and queryable in SwiftData.
- ContextInjection → LLM pipeline: Seed SwiftData with 5 known meetings. Call assemblePrompt() with a query matching one meeting. Feed assembled prompt to LLMInferenceActor.generate() with a small test model. Verify output stream produces non-empty tokens. Requires MLX Phi-2 tiny model in test fixtures.
- ModelManager download → install: Test downloadModel() against a mock HTTP server serving a small test model. Verify files are written to ~/Models/, InstalledModel entity is created in SwiftData, and SHA256 verification passes.
- SessionOrchestrator end-to-end: Start a session with a test audio file, run through the full pipeline (capture → transcription → persistence → summarization). Verify Meeting entity has populated rawTranscript and summary fields. Longest-running integration test (~30 seconds).
- SwiftData migration: Create a V1 database with sample data, apply V2 schema migration, verify all existing data is preserved and new fields have correct defaults.
### E2E
- Full recording session: Launch app, select microphone, start recording, speak for 30 seconds, stop recording. Verify: transcript appears in real time, meeting appears in sidebar, audio file saved, transcript segments persisted. Manual test with physical microphone.
- Post-meeting summarization: After recording a meeting, click 'Summarize'. Verify: LLM output streams token-by-token in the detail pane, summary is saved to the meeting, action items are extracted if present in the transcript.
- Context Injection Q&A: Record two meetings on related topics. In the second meeting's detail view, ask a question that requires context from the first meeting. Verify: answer references information from the first meeting's transcript.
- Model lifecycle: Download a Whisper model from Hugging Face (tiny model for test speed). Verify download progress UI. Select the model. Record a meeting. Delete the model. Verify model removed from disk and UI. Re-download and verify functionality restored.
- Offline operation: Disable network (airplane mode or firewall rule). Launch app. Record a meeting. Transcribe. Summarize. Search history. Verify all features work without any network error alerts.
- Large meeting history: Seed the database with 500+ meetings. Verify sidebar loads quickly with lazy pagination. Search across all meetings. Verify search returns in <1 second. Select a meeting with a long transcript (1 hour+). Verify detail pane loads without memory spike.

## 🚀 Rollout Plan
- Phase 0 — Project Setup (Week 1): Create Xcode project with Swift 6 and macOS 15+ target. Configure SPM dependencies: apple/mlx-swift, gonzalezreal/swift-markdown-ui. Set up SwiftData ModelContainer with V1 VersionedSchema. Create ~/Models/ directory structure. Configure App Sandbox entitlements. Set up basic NavigationSplitView shell with empty sidebar and detail pane.

- Phase 1 — Audio Capture (Week 2): Implement AudioCaptureActor with AVAudioEngine microphone tap. Implement format conversion to 16kHz mono Float32. Implement device enumeration. Implement AsyncStream buffer delivery. Add recording toolbar UI with start/stop button and device picker. Write unit tests for device enumeration and format conversion. Integration test with .wav file output.

- Phase 2 — Model Management (Week 3): Implement ModelManagerService with Hugging Face download (resumable, progress tracking, SHA256 verification). Implement InstalledModel SwiftData entity and CRUD. Implement model deletion with file cleanup. Build ModelManagerView sheet with download progress bars and installed model list. Write unit tests for path validation and progress calculation. Integration test with mock HTTP server.

- Phase 3 — Whisper Transcription (Week 4-5): Implement WhisperTranscriptionActor with MLX Whisper model loading and inference. Implement 30-second windowed processing with 5-second overlap. Implement timestamp-gap speaker diarization heuristic. Implement TranscriptChunk AsyncStream output. Build LiveTranscriptionView with real-time scrolling transcript. Write unit tests for diarization heuristic. Integration test with known audio file and tiny Whisper model.

- Phase 4 — Data Layer & Persistence (Week 5-6): Implement all SwiftData @Model entities: Meeting, TranscriptSegment, SpeakerProfile, AppSettings. Implement MeetingStore with full CRUD, filtering, sorting, pagination. Implement audio file persistence at Application Support path. Implement cascade delete and singleton AppSettings. Build MeetingSidebarView with @Query lazy loading. Build MeetingDetailView with markdown rendering. Write comprehensive unit tests for MeetingStore. Integration test for transcription → persistence pipeline.

- Phase 5 — LLM Inference (Week 7-8): Implement LLMInferenceActor with MLX LLM model loading, tokenization, and generation. Implement AsyncStream token streaming with stop sequence support. Implement context window management and token counting. Build StreamingTextView for token-by-token display. Write unit tests for token counting. Integration test with small test model.

- Phase 6 — Context Injection & Summarization (Week 8-9): Implement ContextInjectionService with keyword extraction, BM25-style search, and prompt assembly. Implement chunked summarization for long transcripts. Implement PromptTask handling for summarize, actionItems, question, and custom tasks. Build Q&A UI in MeetingDetailView. Write unit tests for search ranking and prompt assembly. Integration test for full context injection → LLM pipeline.

- Phase 7 — Session Orchestration (Week 9-10): Implement SessionOrchestrator coordinating end-to-end session flow. Implement structured concurrency task group management. Implement cancellation and cleanup. Implement post-meeting summarization trigger. Wire all services together through the orchestrator. Write integration test for full end-to-end session. Run all e2e test scenarios.

- Phase 8 — Polish & Liquid-Glass UI (Week 10-11): Implement MeshGradient background with animated control points. Add subtle opacity transitions and organic shape animations. Implement settings sheet with prompt template editor. Add speaker profile management (rename, color assignment). Performance profiling with Instruments: verify <2s transcription latency, 20+ tok/s generation, <500MB RAM excluding models. Fix any identified performance regressions.

- Phase 9 — Testing, Hardening & Distribution (Week 12): Run full e2e test suite including offline operation and large meeting history stress test. Fix all identified bugs. Add error recovery for all edge cases. Code sign and notarize the app. Create .dmg distribution. Write minimal user guide. Final performance validation on M1 (minimum spec) and M4 (target spec) hardware.

## ❓ Open Questions
- Which specific MLX Whisper model variant should be the recommended default? whisper-large-v3-mlx requires ~3GB RAM and provides best accuracy, but whisper-medium-mlx at ~1.5GB may be better for 16GB machines running a 7B LLM simultaneously. Need to profile peak memory with both models loaded.
- Should the app support ScreenCaptureKit for system audio capture (e.g., recording a Zoom call's audio output) in addition to microphone input? This would require the com.apple.security.screen-capture entitlement and user permission, but would enable recording remote participants without a physical microphone.
- How should the app handle the transition from recording to summarization when the user wants real-time summarization during the meeting? Options: (A) summarize periodically every N minutes during recording (requires running Whisper and LLM concurrently, ~10GB+ RAM), or (B) summarize only after recording stops (simpler, lower memory). The ARD is ambiguous on this.
- What is the maximum supported meeting duration? A 3-hour meeting at 16kHz mono produces ~345MB of audio data. The circular buffer design caps in-memory audio at 60 seconds, but the .wav file grows unbounded. Should we enforce a maximum or rely on disk space checks?
- Should speaker diarization labels persist across meetings for the same physical speaker? Currently SpeakerProfile is standalone and speakers are matched by label string. A more sophisticated approach would use voice embeddings for automatic speaker recognition across sessions, but this requires an additional ML model.
- The ARD specifies ~/Models/ for model storage, but this is outside the App Sandbox's default container. Should we use a security-scoped bookmark for ~/Models/ (requires user approval via file picker on first use), or store models inside the app's sandboxed container at ~/Library/Containers/com.scribeflowpro/Data/Models/ (no user interaction but less discoverable)?