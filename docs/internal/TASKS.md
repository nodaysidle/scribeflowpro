# Tasks Plan — ScribeFlow Pro

## 📌 Global Assumptions
- Target hardware is Apple Silicon Mac with minimum 16GB unified memory running macOS 15+
- MLX Swift (apple/mlx-swift) provides stable APIs for Whisper and LLM inference on Apple Silicon
- Hugging Face MLX-community hosts pre-converted Whisper and LLM models in MLX format
- SwiftData's #Predicate with localizedStandardContains provides adequate full-text search for up to 1000+ meetings
- 16GB unified memory can support one Whisper model (~1.5–3GB) and one 4-bit 7B LLM (~4GB) loaded simultaneously
- Users will grant microphone permission and manually select ~/Models/ directory for security-scoped bookmark on first use

## ⚠️ Risks
- **MLX Swift API instability:** apple/mlx-swift is relatively new; breaking API changes between versions could require significant rework of WhisperTranscriptionActor and LLMInferenceActor.
- **Unified memory exhaustion with concurrent models:** Running Whisper + LLM simultaneously on 16GB machines may trigger memory pressure warnings or OOM kills, especially with larger model variants.
- **Whisper real-time transcription latency on M1:** M1 minimum-spec hardware may not achieve real-time transcription with whisper-large-v3, causing buffer accumulation and degraded UX.
- **App Sandbox and ~/Models/ path conflict:** Storing models at ~/Models/ requires security-scoped bookmarks and user interaction via file picker, which adds friction and could confuse users.
- **Speaker diarization accuracy with gap heuristic:** Timestamp-gap heuristic for speaker diarization will produce incorrect labels in fast-paced conversations with short turn-taking gaps.

## 🧩 Epics
## Foundation & Audio Capture
**Goal:** Establish project scaffold with SwiftData, entitlements, and real-time microphone capture via AVAudioEngine on a dedicated actor

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Xcode project scaffold with SPM dependencies (3 hours)

Create macOS 15+ Swift 6 project, add apple/mlx-swift and gonzalezreal/swift-markdown-ui via SPM, configure App Sandbox entitlements (microphone, network.client, user-selected read-write), and set up NavigationSplitView shell.

**Acceptance Criteria**
- Project builds on Apple Silicon with macOS 15+ deployment target
- SPM resolves mlx-swift and swift-markdown-ui without errors
- App Sandbox entitlements include microphone, network.client, and files.user-selected.read-write
- Empty NavigationSplitView renders with sidebar and detail pane

**Dependencies**
_None_

### ✅ AudioCaptureActor with AVAudioEngine tap (8 hours)

Implement AudioCaptureActor as a Swift actor that starts AVAudioEngine, installs an input node tap, converts audio to 16kHz mono Float32, and emits buffers via AsyncStream with bufferingNewest(100) policy.

**Acceptance Criteria**
- startCapture() returns AsyncStream<AVAudioPCMBuffer> of 16kHz mono Float32 buffers
- stopCapture() completes the stream, stops the engine, and writes a temp .wav file
- Microphone permission is requested on first call and errors with .permissionDenied if declined
- Ring buffer caps in-memory audio at 60 seconds (~3.8MB)

**Dependencies**
- Xcode project scaffold with SPM dependencies

### ✅ Audio device enumeration (3 hours)

Implement listInputDevices() on AudioCaptureActor querying Core Audio for available input devices, returning AudioDevice structs with id, name, sampleRate, and isDefault flag.

**Acceptance Criteria**
- Returns all connected audio input devices as [AudioDevice]
- Identifies the system default device with isDefault: true
- Unit test verifies mapping from mock Core Audio device list

**Dependencies**
- AudioCaptureActor with AVAudioEngine tap

### ✅ Recording toolbar UI (4 hours)

Build RecordingToolbar with start/stop toggle button, device picker dropdown bound to listInputDevices(), and a recording duration timer display.

**Acceptance Criteria**
- Start button triggers AudioCaptureActor.startCapture and toggles to stop state
- Device picker lists available input devices and defaults to system device
- Duration timer updates every second during active recording

**Dependencies**
- Audio device enumeration

## Model Management
**Goal:** Download, verify, track, and delete MLX-format models from Hugging Face with resumable downloads and SwiftData persistence

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ InstalledModel SwiftData entity and ModelContainer setup (4 hours)

Define InstalledModel @Model with name, huggingFaceRepo, filePath, sizeBytes, lastUsed, modelType, and quantization. Configure ModelContainer with VersionedSchema V1 and create ~/Models/ directory on first launch.

**Acceptance Criteria**
- InstalledModel entity persists and is queryable via SwiftData FetchDescriptor
- ~/Models/ directory is created if absent on app launch
- VersionedSchema V1 includes InstalledModel with SchemaMigrationPlan stub

**Dependencies**
- Xcode project scaffold with SPM dependencies

### ✅ ModelManagerService download with resume and SHA256 verification (10 hours)

Implement downloadModel() using ephemeral URLSession with Range/If-Range headers for resumable downloads. Stream DownloadProgress via AsyncStream. Verify each file's SHA256 after download. Store to ~/Models/{repoName}/.

**Acceptance Criteria**
- Downloads all files from a Hugging Face repo to ~/Models/{repoName}/
- DownloadProgress stream reports per-file and overall progress accurately
- SHA256 mismatch triggers ModelManagerError.integrityCheckFailed
- Disk space is checked before download; insufficientDiskSpace error raised if < 2x model size

**Dependencies**
- InstalledModel SwiftData entity and ModelContainer setup

### ✅ Model deletion with unload coordination (4 hours)

Implement deleteModel() that unloads the model from WhisperTranscriptionActor or LLMInferenceActor if loaded, removes the directory from ~/Models/, and deletes the SwiftData entity.

**Acceptance Criteria**
- Model directory is removed from disk and InstalledModel entity deleted
- Active model is unloaded before deletion proceeds
- modelInUse error raised if model is actively running inference

**Dependencies**
- ModelManagerService download with resume and SHA256 verification

### ✅ ModelManagerView UI (6 hours)

Build ModelManagerView sheet displaying installed models with size, type, and last-used date. Show download progress bars for active downloads. Include delete button with confirmation and storage usage summary.

**Acceptance Criteria**
- Lists all installed models from SwiftData with metadata
- Active downloads show per-file and overall progress bars
- Delete requires confirmation and updates list on completion
- Storage usage report shows total and per-model breakdown

**Dependencies**
- Model deletion with unload coordination

## Transcription Pipeline
**Goal:** Run MLX-optimized Whisper inference on streamed audio with windowed processing, speaker diarization, and real-time transcript display

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ WhisperTranscriptionActor model loading (8 hours)

Implement loadModel() and unloadModel() on WhisperTranscriptionActor using MLX Swift to load Whisper weights from ~/Models/{modelID}/ into unified memory. Check available memory before loading.

**Acceptance Criteria**
- Model loads from disk into MLX unified memory and isModelLoaded returns true
- insufficientMemory error raised if estimated model size exceeds available unified memory
- unloadModel() frees MLX array cache and resets state
- modelNotFound error raised for missing model directory

**Dependencies**
- InstalledModel SwiftData entity and ModelContainer setup

### ✅ Windowed Whisper inference with overlap (12 hours)

Implement transcribe() that accumulates PCM buffers into 30-second windows with 5-second overlap, runs MLX Whisper inference per window, and emits TranscriptChunk via AsyncStream with timestamps, text, confidence, and isFinal flag.

**Acceptance Criteria**
- 30-second windows with 5-second overlap produce continuous transcription without gaps
- TranscriptChunk includes accurate startTime/endTime relative to session start
- Confidence scores derived from Whisper decoder logprobs are in 0.0–1.0 range
- isFinal is true only after the next overlapping window confirms the segment

**Dependencies**
- WhisperTranscriptionActor model loading

### ✅ Timestamp-gap speaker diarization heuristic (4 hours)

Assign speaker labels (Speaker A, Speaker B, etc.) to TranscriptChunks using a silence-gap heuristic: gaps > 1.5 seconds between segments trigger a speaker change.

**Acceptance Criteria**
- Speaker label changes when silence gap exceeds 1.5 seconds
- Speaker label persists through gaps ≤ 1.5 seconds
- Unit tests cover edge cases: zero-gap, simultaneous boundaries, long silence

**Dependencies**
- Windowed Whisper inference with overlap

### ✅ LiveTranscriptionView with real-time scrolling (5 hours)

Build LiveTranscriptionView that subscribes to AsyncStream<TranscriptChunk>, displays speaker-labeled segments with color badges, and auto-scrolls to the latest segment via ScrollViewReader.

**Acceptance Criteria**
- Transcript segments appear in real-time as chunks are emitted
- Each segment shows speaker label with distinct color badge
- View auto-scrolls to newest segment on each update
- Provisional (non-final) segments render with reduced opacity

**Dependencies**
- Timestamp-gap speaker diarization heuristic

## Data Layer & Persistence
**Goal:** Implement SwiftData entities for meetings, transcript segments, speaker profiles, and settings with full CRUD, filtering, pagination, and audio file persistence

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ SwiftData @Model entities and schema (5 hours)

Define Meeting, TranscriptSegment, SpeakerProfile, and AppSettings @Model entities with relationships (Meeting→TranscriptSegment cascade delete), indices on Meeting.date and Meeting.title, and singleton AppSettings enforcement.

**Acceptance Criteria**
- All five @Model entities (including InstalledModel) compile under VersionedSchema V1
- Meeting→TranscriptSegment relationship uses cascade delete rule
- Meeting.date and Meeting.title are indexed
- AppSettings fetch-or-create logic enforces singleton

**Dependencies**
- InstalledModel SwiftData entity and ModelContainer setup

### ✅ MeetingStore CRUD with filtering and pagination (8 hours)

Implement MeetingStore with saveMeeting, deleteMeeting, fetchMeetings (with MeetingFilter, MeetingSortOrder, limit/offset), and updateMeeting. Copy audio files to Application Support/ScribeFlowPro/Audio/.

**Acceptance Criteria**
- saveMeeting persists Meeting with TranscriptSegments and copies audio to persistent path
- fetchMeetings supports date range, search text, participants filters with correct predicates
- Pagination via limit/offset returns correct slices
- deleteMeeting cascades to segments and removes audio file from disk

**Dependencies**
- SwiftData @Model entities and schema

### ✅ MeetingSidebarView with @Query lazy loading (5 hours)

Build MeetingSidebarView using @Query with FetchDescriptor limited to 50 meetings initially. Implement infinite scroll to load next pages. Show meeting title, date, and duration in each row.

**Acceptance Criteria**
- Initial load fetches only 50 meetings via fetchLimit
- Scrolling to bottom triggers next page fetch
- Each row displays title, formatted date, and duration
- Selecting a row navigates to MeetingDetailView in the detail pane

**Dependencies**
- MeetingStore CRUD with filtering and pagination

### ✅ MeetingDetailView with markdown-rendered summary (5 hours)

Build MeetingDetailView showing formatted transcript with speaker labels, markdown-rendered summary and action items via swift-markdown-ui, and meeting metadata header.

**Acceptance Criteria**
- Transcript displays with speaker-labeled segments and timestamps
- Summary renders as markdown with proper heading and list formatting
- Action items section renders markdown checklist
- Meeting metadata (date, duration, participants) shown in header

**Dependencies**
- MeetingSidebarView with @Query lazy loading

### ✅ SettingsView with app configuration (5 hours)

Build SettingsView sheet with audio input device picker, Whisper model selector, LLM model selector, summarization prompt template editor, and maxContextInjectionTokens slider. Persist to AppSettings singleton.

**Acceptance Criteria**
- Device picker shows available audio inputs from AudioCaptureActor
- Model selectors list installed models filtered by type (.whisper, .llm)
- Prompt template editor saves to AppSettings on change
- All settings persist across app restarts via SwiftData

**Dependencies**
- SwiftData @Model entities and schema

## LLM Inference & Context Injection
**Goal:** Run local LLM generation via MLX Swift with token streaming, keyword-based historical meeting search, and context-aware prompt assembly

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ LLMInferenceActor model loading and token counting (8 hours)

Implement LLMInferenceActor with loadModel() loading MLX-format LLM weights, unloadModel(), and tokenCount() using the model's bundled tokenizer. Report contextWindowSize after load.

**Acceptance Criteria**
- loadModel loads weights into unified memory and exposes contextWindowSize
- tokenCount returns accurate count matching the model's tokenizer
- noModelLoaded error raised if generate or tokenCount called before load
- Previously loaded model is unloaded before loading a new one

**Dependencies**
- InstalledModel SwiftData entity and ModelContainer setup

### ✅ LLM token generation with stop sequences (10 hours)

Implement generate() on LLMInferenceActor that runs autoregressive MLX inference and emits tokens via AsyncStream<String>. Support maxTokens, temperature, and stop sequences. Respect Task cancellation.

**Acceptance Criteria**
- Tokens stream individually via AsyncStream for responsive UI
- Generation stops at maxTokens, EOS token, or matching stop sequence
- contextWindowExceeded error raised if prompt exceeds context window
- Task.isCancelled is checked per token and terminates cleanly

**Dependencies**
- LLMInferenceActor model loading and token counting

### ✅ StreamingTextView for token-by-token display (3 hours)

Build a generic StreamingTextView that accepts AsyncStream<String>, appends each token to a @State String, and auto-scrolls to bottom. Include subtle typing animation.

**Acceptance Criteria**
- Text updates character-by-character as tokens arrive from the stream
- ScrollViewReader auto-scrolls to bottom on each append
- View handles stream completion gracefully

**Dependencies**
- LLM token generation with stop sequences

### ✅ ContextInjectionService keyword search and BM25 ranking (6 hours)

Implement searchMeetings() querying SwiftData with #Predicate localizedStandardContains for keyword matching. Rank results by term-frequency scoring. Return MeetingSnippets with 200-char context windows.

**Acceptance Criteria**
- Keywords match against Meeting.rawTranscript and Meeting.summary fields
- Results sorted by keyword hit count in descending relevance order
- Snippets show 200-character window around best keyword match
- Unit tests verify ranking with known test meetings

**Dependencies**
- MeetingStore CRUD with filtering and pagination

### ✅ Prompt assembly with context budgeting (6 hours)

Implement assemblePrompt() that builds prompts for each PromptTask case (.summarize, .actionItems, .question, .custom), injects ranked historical snippets within token budget, and formats as [System][Context][Transcript][Task].

**Acceptance Criteria**
- Assembled prompt follows [System][Historical Context][Transcript][Task] format
- Historical context is truncated to stay within contextBudget token limit
- All four PromptTask cases produce correctly structured prompts
- Unit test verifies token budget enforcement via mocked tokenCount

**Dependencies**
- ContextInjectionService keyword search and BM25 ranking
- LLMInferenceActor model loading and token counting

## Session Orchestration & Polish
**Goal:** Wire the full capture→transcribe→persist→summarize pipeline, add Liquid-Glass UI, and harden for distribution

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ SessionOrchestrator end-to-end pipeline (10 hours)

Implement SessionOrchestrator coordinating startSession (audio capture → Whisper transcription → segment collection) and stopSession (persist meeting, stop streams). Use structured concurrency TaskGroup for parallel pipelines.

**Acceptance Criteria**
- startSession chains AudioCaptureActor → WhisperTranscriptionActor and collects segments
- stopSession persists Meeting with all TranscriptSegments and audio file
- Cancellation propagates cleanly through all async streams
- sessionState observable reflects idle, recording, processing, and error states

**Dependencies**
- Prompt assembly with context budgeting
- LiveTranscriptionView with real-time scrolling
- MeetingStore CRUD with filtering and pagination

### ✅ Post-meeting summarization and Q&A (8 hours)

Implement summarizeMeeting() with chunked summarization for long transcripts (chunk → summarize each → merge pass) and askQuestion() that uses ContextInjectionService for cross-meeting Q&A. Wire into MeetingDetailView.

**Acceptance Criteria**
- Summarization streams tokens to MeetingDetailView via StreamingTextView
- Long transcripts are chunked and summarized sequentially to cap memory
- Q&A answers reference historical meetings when relevant context exists
- Summary and action items are saved back to the Meeting entity

**Dependencies**
- SessionOrchestrator end-to-end pipeline

### ✅ Liquid-Glass MeshGradient background and animations (5 hours)

Implement MeshGradient background with 3x3 animated control points using easeInOut(duration: 3) repeatForever. Add subtle opacity transitions on view state changes and organic shape animations on the recording indicator.

**Acceptance Criteria**
- MeshGradient renders behind main content with smooth animated control points
- Animation is GPU-accelerated with zero measurable CPU overhead
- Recording indicator pulses with organic shape animation during capture
- Visual polish matches Liquid-Glass aesthetic without heavy RAM usage

**Dependencies**
- SessionOrchestrator end-to-end pipeline

### ✅ os.Logger instrumentation and performance profiling (6 hours)

Add os.Logger with per-module categories across all actors and services. Add os_signpost intervals for Whisper inference, LLM generation, and SwiftData queries. Profile with Instruments to verify <2s transcription latency and 20+ tok/s generation.

**Acceptance Criteria**
- All modules log lifecycle events at .info and errors at .error with session UUID
- os_signpost intervals appear in Instruments for inference and query operations
- Transcript text is only logged at .debug behind #if DEBUG
- Performance targets validated: <2s transcription latency, 20+ tok/s on M4

**Dependencies**
- Post-meeting summarization and Q&A

### ✅ Integration testing, hardening, and distribution packaging (12 hours)

Run full E2E test suite (recording, summarization, context Q&A, offline, large history). Fix edge cases. Implement temp file cleanup on launch. Code sign, notarize, and package as .dmg.

**Acceptance Criteria**
- All E2E scenarios pass: record, summarize, cross-meeting Q&A, offline, 500+ meetings
- Orphaned temp audio files older than 24 hours cleaned on launch
- App is code signed and notarized for macOS distribution
- Cold launch completes in under 3 seconds with deferred model loading

**Dependencies**
- os.Logger instrumentation and performance profiling
- Liquid-Glass MeshGradient background and animations

## ❓ Open Questions
- Should the default Whisper model be whisper-large-v3-mlx (~3GB) for accuracy or whisper-medium-mlx (~1.5GB) for memory headroom alongside a 7B LLM?
- Should the app support ScreenCaptureKit for system audio (e.g., Zoom call recording) in V1, or defer to a future release?
- Should models be stored inside the sandboxed app container by default, or at ~/Models/ requiring a security-scoped bookmark?
- Should real-time summarization during recording be supported in V1, or only post-meeting summarization?
- What maximum meeting duration should be enforced, given unbounded .wav file growth on disk?