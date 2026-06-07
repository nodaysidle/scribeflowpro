# Agent Prompts — ScribeFlow Pro

## Global Rules

### Do
- Use Swift 6 strict concurrency with actors for all audio/ML operations
- Target macOS 15+ with Apple Silicon (M1+) as minimum requirement
- Use SwiftData VersionedSchema V1 for all persistence with cascade delete rules
- Stream all ML inference tokens via AsyncStream for responsive UI
- Use os.Logger with per-module categories and os_signpost for performance tracing

### Don't
- Do NOT use any cloud services or network calls except Hugging Face model downloads
- Do NOT introduce frameworks outside the specified stack (no CoreData, no Combine publishers)
- Do NOT load Whisper and LLM models eagerly on launch — defer until user action
- Do NOT store sensitive transcript text in os.Logger at .info level — use .debug behind #if DEBUG
- Do NOT use ObservableObject — use @Observable from the Observation framework exclusively

---

## Task Prompts
### Task 1: Foundation: Project Scaffold, SwiftData Schema, and Audio Capture

**Role:** Expert Swift 6 / macOS Audio Engineer
**Goal:** Create Xcode project with SwiftData schema, audio capture actor, and NavigationSplitView shell

**Context**
Establish the macOS app scaffold with SPM dependencies, define all SwiftData @Model entities (Meeting, TranscriptSegment, SpeakerProfile, AppSettings, InstalledModel) under VersionedSchema V1, and implement AudioCaptureActor with AVAudioEngine tap producing 16kHz mono Float32 AsyncStream buffers. This task lays the groundwork for every subsequent feature.

**Files to Create**
- ScribeFlowPro/ScribeFlowProApp.swift
- ScribeFlowPro/Models/Meeting.swift
- ScribeFlowPro/Models/TranscriptSegment.swift
- ScribeFlowPro/Models/SpeakerProfile.swift
- ScribeFlowPro/Models/AppSettings.swift
- ScribeFlowPro/Models/InstalledModel.swift
- ScribeFlowPro/Audio/AudioCaptureActor.swift
- ScribeFlowPro/Views/ContentView.swift

**Files to Modify**
- Package.swift
- ScribeFlowPro/ScribeFlowPro.entitlements

**Steps**
1. Create a Swift 6 macOS 15+ project with Package.swift adding apple/mlx-swift and gonzalezreal/swift-markdown-ui as SPM dependencies. Configure App Sandbox entitlements for com.apple.security.device.audio-input, com.apple.security.network.client, and com.apple.security.files.user-selected.read-write.
2. Define all five @Model entities under a VersionedSchema V1: Meeting (id, title, date, duration, rawTranscript, summary, actionItems, audioFilePath) with @Relationship(.cascade) to [TranscriptSegment]; TranscriptSegment (id, startTime, endTime, speakerLabel, text, confidence, isFinal); SpeakerProfile (id, label, displayName, colorHex); AppSettings (id, selectedDeviceID, whisperModelID, llmModelID, promptTemplate, maxContextTokens) with singleton fetch-or-create; InstalledModel (id, name, huggingFaceRepo, filePath, sizeBytes, lastUsed, modelType enum .whisper/.llm, quantization). Add indices on Meeting.date and Meeting.title.
3. Implement AudioCaptureActor as a Swift actor. startCapture() requests microphone permission, configures AVAudioEngine with input node tap converting to 16kHz mono Float32 via AVAudioConverter, and returns AsyncStream<AVAudioPCMBuffer> with .bufferingNewest(100). Cap ring buffer at 60 seconds (~3.8MB). Throw AudioCaptureError.permissionDenied if microphone access is declined.
4. Implement stopCapture() that removes the tap, stops the engine, finishes the AsyncStream continuation, and writes accumulated audio to a temp .wav file. Add listInputDevices() querying Core Audio kAudioHardwarePropertyDevices to return [AudioDevice] structs with id, name, sampleRate, and isDefault flag.
5. Build ContentView as NavigationSplitView with a sidebar placeholder (MeetingSidebarView stub) and detail pane. Add RecordingToolbar at the top with a start/stop toggle button bound to AudioCaptureActor, a Picker for audio devices from listInputDevices(), and a Text timer updating every second during recording. Configure ModelContainer in ScribeFlowProApp with all five entity types and create ~/Models/ directory on first launch.

**Validation**
`swift build 2>&1 | tail -5`

---

### Task 2: Model Management: Download, Verify, and Track MLX Models

**Role:** Expert Swift Networking and File System Engineer
**Goal:** Implement ModelManagerService with resumable downloads, integrity checks, and management UI

**Context**
Build the model lifecycle system: download MLX-format models from Hugging Face with resumable transfers and SHA256 verification, persist metadata in SwiftData InstalledModel, and provide a SwiftUI management sheet. Models are stored at ~/Models/{repoName}/ using security-scoped bookmarks.

**Files to Create**
- ScribeFlowPro/Services/ModelManagerService.swift
- ScribeFlowPro/Services/ModelManagerError.swift
- ScribeFlowPro/Views/ModelManagerView.swift

**Files to Modify**
- ScribeFlowPro/Models/InstalledModel.swift

**Steps**
1. Implement ModelManagerService as an @Observable class. Add downloadModel(repo: String) that creates an ephemeral URLSession, fetches the Hugging Face repo file listing, and downloads each file to ~/Models/{repoName}/ using Range/If-Range headers for resume support. Emit DownloadProgress (fileName, fileProgress, overallProgress, bytesDownloaded, totalBytes) via AsyncStream. Check available disk space before starting — throw .insufficientDiskSpace if free space < 2x total model size.
2. After each file download completes, compute SHA256 using CryptoKit and compare against the expected hash from the repo manifest. Throw ModelManagerError.integrityCheckFailed(fileName) on mismatch. On success of all files, create an InstalledModel SwiftData entity with name, huggingFaceRepo, filePath, sizeBytes, modelType (.whisper or .llm inferred from repo name), and quantization string parsed from config.json.
3. Implement deleteModel(model: InstalledModel) that first checks if the model is actively loaded in WhisperTranscriptionActor or LLMInferenceActor (via a shared ModelLoadState registry). If loaded and idle, unload it first. If actively running inference, throw .modelInUse. Remove the ~/Models/{repoName}/ directory and delete the SwiftData entity.
4. Build ModelManagerView as a .sheet presenting a List of installed models from @Query. Each row shows model name, type badge (.whisper/.llm), size formatted as GB, and last-used date. Active downloads show ProgressView bars with per-file and overall progress. Delete button triggers .confirmationDialog before calling deleteModel().
5. Add a storage summary section at the bottom of ModelManagerView showing total ~/Models/ disk usage and per-model breakdown as a simple bar chart using SwiftUI rectangles. Include a 'Download Model' button that presents a text field for Hugging Face repo ID (e.g., mlx-community/whisper-large-v3-mlx) and starts the download pipeline.

**Validation**
`swift build 2>&1 | tail -5`

---

### Task 3: Transcription Pipeline: Whisper Inference, Diarization, and Live UI

**Role:** Expert MLX Swift / On-Device ML Engineer
**Goal:** Run real-time Whisper transcription with speaker labels and streaming transcript view

**Context**
Implement WhisperTranscriptionActor using MLX Swift to run Whisper inference on 30-second windowed audio with 5-second overlap. Add timestamp-gap speaker diarization heuristic and build LiveTranscriptionView with real-time auto-scrolling speaker-labeled segments.

**Files to Create**
- ScribeFlowPro/ML/WhisperTranscriptionActor.swift
- ScribeFlowPro/ML/TranscriptChunk.swift
- ScribeFlowPro/ML/SpeakerDiarizer.swift
- ScribeFlowPro/Views/LiveTranscriptionView.swift

**Files to Modify**
_None_

**Steps**
1. Implement WhisperTranscriptionActor as a Swift actor. loadModel(modelPath: String) loads MLX Whisper weights from ~/Models/{modelID}/ using MLX Swift APIs into unified memory. Check os_proc_available_memory() before loading — throw .insufficientMemory if estimated model size exceeds 80% of available memory. unloadModel() calls MLX.GPU.set(cacheLimit: 0) equivalent and nils model references. Expose isModelLoaded and modelInfo properties.
2. Implement transcribe(audioStream: AsyncStream<AVAudioPCMBuffer>) that accumulates PCM buffers into 30-second windows with 5-second overlap. For each window, convert to MLXArray of Float32 samples and run Whisper inference (encode → decode with beam search). Emit TranscriptChunk (id, startTime, endTime, text, confidence from decoder logprobs normalized to 0.0-1.0, speakerLabel, isFinal) via AsyncStream. Set isFinal=true only after the next overlapping window confirms the segment text is stable.
3. Implement SpeakerDiarizer as a struct with assignSpeaker(chunks: [TranscriptChunk]) -> [TranscriptChunk]. Use silence-gap heuristic: if gap between consecutive chunk endTime and next startTime exceeds 1.5 seconds, increment speaker label (Speaker A → Speaker B, cycling through a configurable max of 8 speakers). Maintain current speaker state across calls for streaming use.
4. Build LiveTranscriptionView accepting an AsyncStream<TranscriptChunk> binding. Use ScrollViewReader with ScrollView containing LazyVStack of transcript segment rows. Each row shows a colored Circle badge per speaker label, the speaker name, timestamp range formatted as mm:ss, and the transcript text. Non-final segments (isFinal=false) render at 0.6 opacity. Auto-scroll to the latest segment ID using .onChange of the segments array count.
5. Wire LiveTranscriptionView into the main ContentView detail pane, shown during active recording sessions. Pass the TranscriptChunk stream from WhisperTranscriptionActor through SpeakerDiarizer. Add a small status indicator showing Whisper model name and inference latency per chunk.

**Validation**
`swift build 2>&1 | tail -5`

---

### Task 4: LLM Inference, Context Injection, and Data Persistence Layer

**Role:** Expert Swift LLM Integration and Data Architecture Engineer
**Goal:** Enable local LLM generation with cross-meeting context injection and full meeting persistence UI

**Context**
Implement LLMInferenceActor for local LLM generation with token streaming, build ContextInjectionService for keyword-based historical meeting search with BM25-style ranking, assemble context-budgeted prompts, and complete MeetingStore CRUD with MeetingSidebarView and MeetingDetailView.

**Files to Create**
- ScribeFlowPro/ML/LLMInferenceActor.swift
- ScribeFlowPro/Services/ContextInjectionService.swift
- ScribeFlowPro/Services/PromptAssembler.swift
- ScribeFlowPro/Services/MeetingStore.swift
- ScribeFlowPro/Views/MeetingSidebarView.swift
- ScribeFlowPro/Views/MeetingDetailView.swift
- ScribeFlowPro/Views/StreamingTextView.swift
- ScribeFlowPro/Views/SettingsView.swift

**Files to Modify**
_None_

**Steps**
1. Implement LLMInferenceActor as a Swift actor. loadModel(modelPath: String) loads MLX-format LLM weights and bundled tokenizer. Expose contextWindowSize and tokenCount(text: String) -> Int. generate(prompt: String, maxTokens: Int, temperature: Double, stopSequences: [String]) runs autoregressive MLX inference, emitting tokens via AsyncStream<String>. Check Task.isCancelled per token. Throw .contextWindowExceeded if prompt tokens exceed contextWindowSize. Unload previous model before loading new one.
2. Implement ContextInjectionService with searchMeetings(keywords: [String], limit: Int) querying SwiftData using #Predicate with localizedStandardContains on Meeting.rawTranscript and Meeting.summary. Rank by keyword hit count (term-frequency). Return [MeetingSnippet] with meetingID, title, date, snippet (200-char window around best keyword match), and relevanceScore. Implement PromptAssembler.assemblePrompt(task: PromptTask, transcript: String, snippets: [MeetingSnippet], contextBudget: Int) formatting as [System][Historical Context][Transcript][Task] with token-budgeted context truncation. PromptTask cases: .summarize, .actionItems, .question(String), .custom(String).
3. Implement MeetingStore as an @Observable class. saveMeeting(title, date, duration, rawTranscript, segments, audioTempURL) copies audio to ~/Library/Application Support/ScribeFlowPro/Audio/{uuid}.wav, creates Meeting and TranscriptSegment entities via SwiftData. fetchMeetings(filter: MeetingFilter, sort: MeetingSortOrder, limit: Int, offset: Int) supports date range, search text, and participant filters. deleteMeeting cascades to segments and removes the audio file.
4. Build MeetingSidebarView using @Query with FetchDescriptor(fetchLimit: 50, sortBy: [SortDescriptor(\.date, order: .reverse)]). Each row shows meeting title, formatted date, and duration. Implement infinite scroll by detecting last-item appearance and increasing fetchLimit. On row tap, set selectedMeeting binding for NavigationSplitView detail. Build MeetingDetailView showing metadata header (date, duration, participant count), scrollable transcript with speaker-labeled segments and timestamps, and markdown-rendered summary/action items sections using MarkdownUI.
5. Build StreamingTextView accepting AsyncStream<String>, appending tokens to @State text with ScrollViewReader auto-scroll. Build SettingsView as .sheet with Picker for audio device (from AudioCaptureActor.listInputDevices()), Picker for Whisper model (InstalledModel where modelType == .whisper), Picker for LLM model (modelType == .llm), TextEditor for prompt template, and Slider for maxContextInjectionTokens (500-4000). Persist all to AppSettings singleton via SwiftData.

**Validation**
`swift build 2>&1 | tail -5`

---

### Task 5: Session Orchestration, Summarization, and Liquid-Glass Polish

**Role:** Expert Swift Concurrency Architect and macOS Distribution Engineer
**Goal:** Complete the capture-to-summary pipeline with Liquid-Glass UI and distribution packaging

**Context**
Wire the full end-to-end pipeline via SessionOrchestrator using structured concurrency. Add post-meeting chunked summarization and cross-meeting Q&A. Apply Liquid-Glass MeshGradient visual design. Instrument with os.Logger/os_signpost and prepare for distribution.

**Files to Create**
- ScribeFlowPro/Services/SessionOrchestrator.swift
- ScribeFlowPro/Services/SummarizationService.swift
- ScribeFlowPro/Views/LiquidGlassBackground.swift
- ScribeFlowPro/Utilities/Logger+Extensions.swift

**Files to Modify**
- ScribeFlowPro/Views/ContentView.swift
- ScribeFlowPro/Views/MeetingDetailView.swift
- ScribeFlowPro/ScribeFlowProApp.swift

**Steps**
1. Implement SessionOrchestrator as an @Observable class with @Published sessionState: SessionState (.idle, .recording, .processing, .error(Error)). startSession() launches a TaskGroup: one child task runs AudioCaptureActor.startCapture() piping buffers to WhisperTranscriptionActor.transcribe() through SpeakerDiarizer, collecting TranscriptChunks into an actor-isolated array. stopSession() cancels the group, calls AudioCaptureActor.stopCapture(), persists via MeetingStore.saveMeeting() with all collected segments and the temp audio file. Ensure cancellation propagates cleanly through all AsyncStreams.
2. Implement SummarizationService with summarizeMeeting(meeting: Meeting) that checks rawTranscript token count via LLMInferenceActor.tokenCount(). If within context window, assemble single prompt via PromptAssembler(.summarize) and stream via LLMInferenceActor.generate(). If exceeding context window, chunk transcript into context-sized pieces, summarize each sequentially, then run a merge-summarization pass on combined chunk summaries. askQuestion(question: String, meeting: Meeting) uses ContextInjectionService to find relevant historical snippets, assembles prompt via PromptAssembler(.question), and streams the answer. Save summary and action items back to Meeting entity. Wire into MeetingDetailView with a 'Summarize' button and a question TextField that streams responses into StreamingTextView.
3. Implement LiquidGlassBackground as a View wrapping MeshGradient with 3x3 control points. Animate control point positions using withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) on appear. Use translucent blues, purples, and teals at low saturation. Apply .blur(radius: 40) and .opacity(0.3) to keep it subtle. Add a RecordingPulseIndicator that uses a custom Shape with TimelineView animating organic blob control points during .recording state. Apply LiquidGlassBackground as the base layer behind NavigationSplitView in ContentView with .ignoresSafeArea().
4. Add os.Logger static instances per module (AudioCaptureActor.logger, WhisperTranscriptionActor.logger, LLMInferenceActor.logger, SessionOrchestrator.logger, ModelManagerService.logger) using OSLog subsystem 'com.scribeflowpro' with per-module categories. Add os_signpost(.begin/.end) intervals around Whisper inference windows, LLM token generation calls, and SwiftData batch queries. Log lifecycle events at .info, errors at .error with session UUID context. Transcript text logged only at .debug inside #if DEBUG.
5. Add temp file cleanup in ScribeFlowProApp.init(): scan NSTemporaryDirectory() for .wav files older than 24 hours and delete them. Ensure ModelContainer is configured with all entity types and ~/Models/ directory exists. Update ContentView to bind SessionOrchestrator state to RecordingToolbar and conditionally show LiveTranscriptionView (during recording) or MeetingDetailView (when meeting selected). Add .onAppear to MeetingSidebarView to load initial meetings. Verify full build compiles cleanly with swift build.

**Validation**
`swift build 2>&1 | tail -5`