# ScribeFlow Pro — User Guide

## What is ScribeFlow Pro?

ScribeFlow Pro is a fully offline macOS app that records meetings, transcribes them using on-device Whisper AI, and generates summaries with a local LLM. Everything runs on your Mac — no cloud, no subscriptions, no data leaves your machine.

**Requirements:** macOS 15+, Apple Silicon (M1 or later), 16GB RAM recommended.

---

## Getting Started

### 1. Launch the App

Open **ScribeFlow Pro** from `/Applications` or Spotlight. On first launch:
- You'll be asked to grant **microphone permission** — required for recording.
- The app creates a `~/Models/` directory for storing ML models.
- An empty meeting library appears in the sidebar.

### 2. Download ML Models

Before you can transcribe or summarize, you need to download models:

1. Click the **arrow-down icon** (Models) in the toolbar
2. In the Model Manager sheet, enter a Hugging Face repo ID:
   - **For transcription:** `mlx-community/whisper-large-v3-mlx` (~3GB)
   - **For summarization:** `mlx-community/Llama-3.2-3B-Instruct-4bit` (~2GB)
3. Click **Download** and wait for the progress bar to complete
4. Models are saved to `~/Models/` and verified with SHA256 checksums

### 3. Configure Settings

Click the **gear icon** in the toolbar to open Settings:

| Setting | What it does |
|---------|-------------|
| **Microphone** | Choose which audio input device to use |
| **Whisper Model** | Select the installed Whisper model for transcription |
| **LLM Model** | Select the installed LLM for summarization and Q&A |
| **Summarization Prompt** | Customize the system prompt for meeting summaries |
| **Action Items Prompt** | Customize the system prompt for action item extraction |
| **Max Context Tokens** | How much historical meeting context to inject (500–4000) |

---

## Recording a Meeting

1. Select your microphone from the **Input** dropdown in the toolbar
2. Click the **Record** button (circle icon)
3. A red pulse indicator and timer appear while recording
4. If a Whisper model is loaded, live transcription appears in the detail pane with speaker labels
5. Click **Stop** (square icon) to end recording

When you stop:
- The audio is saved as a `.wav` file
- The transcript and segments are persisted to your meeting library
- The meeting appears in the sidebar

---

## Reviewing Meetings

Click any meeting in the sidebar to see:

- **Metadata header** — date, time, duration, participants
- **Summary** — markdown-rendered summary (click "Summarize" to generate)
- **Action Items** — extracted checklist items
- **Transcript** — full transcript with speaker labels and timestamps
- **Ask a Question** — type a question about the meeting for AI-powered answers

### Generating a Summary

1. Open a meeting from the sidebar
2. Click the **Summarize** button
3. Tokens stream in real-time as the LLM generates the summary
4. The summary is automatically saved to the meeting

For long meetings, the transcript is automatically chunked and summarized in pieces, then merged into a single coherent summary.

### Asking Questions

1. Type your question in the "Ask about this meeting..." field
2. Click **Ask**
3. The answer streams in, drawing from both the current transcript and relevant historical meetings

---

## Managing Models

Open the Model Manager (arrow-down toolbar icon) to:

- **View installed models** with size, type, and last-used date
- **Download new models** by entering a Hugging Face repo ID
- **Delete models** you no longer need (with confirmation)
- **Check storage** — see total and per-model disk usage

### Recommended Models

| Purpose | Repo ID | Size |
|---------|---------|------|
| Transcription (best quality) | `mlx-community/whisper-large-v3-mlx` | ~3 GB |
| Transcription (faster, less RAM) | `mlx-community/whisper-medium-mlx` | ~1.5 GB |
| Summarization (good balance) | `mlx-community/Llama-3.2-3B-Instruct-4bit` | ~2 GB |

---

## Keyboard & UI Tips

- **Search meetings** — use the search bar in the sidebar to filter by title or transcript content
- **Select text** — all transcript text supports text selection for copy/paste
- **Animated background** — the subtle Liquid Glass gradient is GPU-accelerated and adds zero CPU overhead

---

## Data & Privacy

- **100% offline** — no internet required after downloading models
- **Local storage** — meetings are stored via SwiftData (SQLite) in your app's container
- **Audio files** — saved to `~/Library/Application Support/ScribeFlowPro/Audio/`
- **ML models** — stored at `~/Models/`
- **Temp files** — recording temp files older than 24 hours are auto-cleaned on launch

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| No microphone listed | Check System Settings > Privacy > Microphone |
| "No models installed" | Open Model Manager and download at least one Whisper + one LLM model |
| Summarize button does nothing | Ensure an LLM model is selected in Settings |
| High memory usage | Use smaller model variants (whisper-medium, 3B LLM) |
| App won't launch | Requires macOS 15+ on Apple Silicon |
