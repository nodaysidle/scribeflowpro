# ScribeFlow Pro

## 🎯 Product Vision
A local-first, privacy-centric meeting intelligence hub for macOS that transforms live audio into an actionable knowledge base using Apple Silicon-optimized on-device ML, with zero cloud dependency and a Liquid-Glass visual architecture.

## ❓ Problem Statement
Knowledge workers rely on cloud-dependent transcription tools like Otter.ai and Fireflies that expose sensitive meeting content to third-party servers, incur recurring subscription costs, require constant internet connectivity, and introduce latency. High-security environments and privacy-conscious professionals have no viable local alternative that combines real-time transcription, intelligent summarization, and a searchable historical meeting database — all running entirely on-device.

## 🎯 Goals
- Deliver real-time, on-device audio transcription and speaker diarization using MLX-optimized Whisper models on Apple Silicon
- Provide instant, private meeting summarization and action-item extraction via locally-run LLMs through the MLX framework
- Build a searchable, persistent meeting knowledge base stored entirely in SwiftData on the user's machine
- Enable Context Injection — allowing the local LLM to reference historical meeting data when generating summaries and answering queries
- Achieve a responsive, low-memory-footprint UI using SwiftUI 6 with streaming token display and lazy-loaded conversation history
- Support offline operation with zero data leakage — no network calls after initial model download from Hugging Face
- Implement a Liquid-Glass visual architecture with high-diffusion blurs, dynamic mesh gradients, and organic shape animations tied to audio processing state

## 🚫 Non-Goals
- Cloud-based transcription, storage, or processing of any kind
- Cross-platform support (iOS, iPadOS, Windows, Linux) — macOS only
- Intel Mac support — Apple Silicon (M1/M2/M3/M4) is required
- Real-time video capture or screen recording
- Multi-user collaboration or shared meeting workspaces
- Building a custom ML training pipeline — only inference of pre-trained MLX-format models
- Calendar integration or automated meeting join functionality
- Heavy UI frameworks, Electron wrappers, or web-based rendering layers

## 👥 Target Users
- Privacy-conscious professionals who handle sensitive or proprietary meeting content and cannot risk cloud data exposure
- Executives and knowledge workers who need searchable, structured meeting archives with instant AI-powered recall
- Security-cleared personnel and defense/government contractors operating in air-gapped or high-security environments
- Independent consultants and freelancers seeking to eliminate recurring transcription subscription costs
- Software engineers and technical leads who want local-first tooling with no vendor lock-in, running on their M-series Macs

## 🧩 Core Features
- Real-Time On-Device Transcription: Captures system or microphone audio and transcribes it in real time using MLX-optimized Whisper models running on the M-series Neural Engine, with speaker diarization to distinguish participants
- Local LLM Summarization: Runs Llama 3, Mistral, Qwen, or Phi models locally via MLX Swift to generate structured meeting summaries, action items, and key decisions immediately after or during a session
- Context Injection Engine: Queries the SwiftData historical meeting database to inject relevant past context into LLM prompts, enabling the model to reference prior discussions, decisions, and action items when generating new summaries or answering user questions
- Meeting Knowledge Base: Persists all transcripts, summaries, speaker labels, and metadata in SwiftData with full-text search, date filtering, and participant-based retrieval — lazy-loaded for minimal memory impact
- Streaming Token UI: Displays LLM-generated text token-by-token in a StreamingText SwiftUI view for responsive, real-time feedback during summarization and Q&A interactions
- Liquid-Glass Interface: Implements a high-diffusion glassmorphism aesthetic with dynamic mesh gradients that shift based on speaker sentiment analysis, and organic SwiftUI 6 shape animations that represent active audio processing state
- Model Management: Downloads MLX-format models from Hugging Face on first use, stores them in ~/Models/, and provides a simple UI to select, switch, or remove installed models — no internet required after download
- Markdown Transcript Rendering: Displays transcripts and summaries using swift-markdown-ui with syntax highlighting for code blocks, structured formatting for action items, and clean typography for readability

## ⚙️ Non-Functional Requirements
- Privacy: Zero network calls during operation — all transcription, summarization, and storage happen entirely on-device after initial model download
- Performance: Real-time transcription latency under 2 seconds on M1 or later; LLM token generation at 20+ tokens/second for 7B models on 16GB RAM devices
- Memory: Application footprint stays under 500MB excluding loaded ML models; lazy loading for conversation history to avoid memory spikes
- Compatibility: macOS 15+ required; Apple Silicon (M1/M2/M3/M4) required; 16GB RAM minimum for 7B models, 32GB recommended for 13B models
- Architecture: Single-window SwiftUI 6 app using the Observation framework and Swift 6 Structured Concurrency (async/await) — no heavy frameworks or unnecessary dependencies
- Storage: SwiftData for structured data (conversations, settings, speaker profiles); file system at ~/Models/ for ML model binaries
- Responsiveness: UI must remain interactive during transcription and summarization — all ML inference runs on background actors with streamed results to the main thread
- Startup: Cold launch to ready state in under 3 seconds excluding model loading; model warm-up cached across sessions

## 📊 Success Metrics
- Transcription word error rate (WER) at or below 8% on English meeting audio using MLX Whisper large-v3
- End-to-end latency from speech to displayed transcript under 2 seconds on M1 or later
- LLM summarization completes within 30 seconds for a 60-minute meeting transcript on a 16GB M2 device
- Application RAM usage stays under 500MB (excluding loaded model weights) during active transcription sessions
- Context Injection relevance: 80%+ of injected historical references rated as relevant by users in manual review
- Zero outbound network requests detected during a full transcription-to-summary workflow (post model download)
- App cold start to interactive UI in under 3 seconds on M3 or later hardware
- User can search and retrieve any historical meeting by keyword, date, or participant in under 1 second from a database of 1000+ meetings

## 📌 Assumptions
- Users have macOS 15+ running on Apple Silicon (M1/M2/M3/M4) with at least 16GB of unified memory
- Users will download MLX-format models from Hugging Face during initial setup while connected to the internet
- The MLX Swift framework (apple/mlx-swift) provides stable, production-ready APIs for Whisper inference and LLM token generation
- MLX-optimized Whisper models achieve acceptable transcription accuracy for English-language meetings without fine-tuning
- 7B-parameter LLMs running on 16GB unified memory devices produce meeting summaries of sufficient quality for professional use
- Users accept that speaker diarization accuracy depends on audio quality and microphone configuration
- SwiftData can handle thousands of meeting records with full-text search without significant query latency
- The ~/Models/ directory convention is acceptable for storing multi-gigabyte model files on the user's machine

## ❓ Open Questions
- What is the specific speaker diarization strategy — will it use Whisper's built-in timestamp alignment, a separate pyannote-style MLX model, or manual speaker labeling?
- How should the app handle microphone permissions and system audio capture on macOS — Core Audio tap, ScreenCaptureKit, or a virtual audio device?
- What is the sentiment analysis approach for driving Liquid-Glass gradient shifts — keyword-based heuristics, a lightweight classifier, or LLM-based inference?
- Should the Context Injection engine use vector embeddings (requiring an embedding model) or keyword/BM25-style retrieval against SwiftData?
- What is the model update strategy — does the app check for newer MLX model versions on Hugging Face, or is it fully manual?
- How should the app handle meetings longer than the LLM's context window — sliding window, hierarchical summarization, or chunked processing?
- What audio formats and sources are supported — only live microphone input, or also pre-recorded audio file import?
- Is there a need for export functionality (PDF, Markdown, JSON) for sharing summaries outside the app while maintaining privacy?