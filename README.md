# ScribeFlow Pro

> Offline meeting transcription and local summaries for macOS.

![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-black?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-orange?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)

![ScribeFlow Pro screenshot](docs/20260228_053941.png)

## Overview

ScribeFlow Pro is a native macOS app for recording or importing meeting audio, transcribing it locally with Whisper, and producing local LLM summaries. No cloud transcription, no telemetry, no account.

## Features

- Live microphone recording
- Audio and video file import
- Local meeting library with transcript and detail view
- Local Whisper transcription from installed `mlx-community` models
- Local MLX LLM summarization from installed `mlx-community` models
- Model path detection under `~/Models/`
- Packaged `.app` with bundled MLX bridge scripts
- One-command local MLX runtime setup

## Technology

| Area | Technology |
|------|------------|
| Language | Swift 6 |
| Interface | SwiftUI (dark with Volt `#C8FF00` accent) |
| Build | Swift Package Manager |
| Transcription | mlx-community/whisper (local MLX) |
| Summarization | mlx-community LLM (local MLX) |
| Storage | SwiftData |

## Requirements

- macOS 15 or later
- Apple Silicon recommended
- Xcode command line tools

## Installation

1. Download `ScribeFlowPro-<version>.zip` from [GitHub Releases](https://github.com/nodaysidle/scribeflowpro/releases/tag/v1.0.0)
   - SHA256: `beffaccfe10ab571f0d6237c56fd1b0e88adebeccb98029e51a479bfc24ee279`
2. Unzip and copy `ScribeFlowPro.app` to `/Applications`
3. Run the bundled setup once:

```bash
/Applications/ScribeFlowPro.app/Contents/Resources/Scripts/setup_mlx_runtime.sh
```

4. Open the app:

```bash
open /Applications/ScribeFlowPro.app
```

The setup script creates:

```text
~/Library/Application Support/ScribeFlowPro/venv
~/Models/mlx-community_whisper-tiny-mlx-q4
~/Models/mlx-community_Qwen2.5-0.5B-Instruct-4bit
```

## Configuration

ScribeFlow Pro resolves both Hugging Face layouts:

```text
~/Models/mlx-community/whisper-tiny-mlx-q4
~/Models/mlx-community_whisper-tiny-mlx-q4
~/Models/mlx-community/Qwen2.5-0.5B-Instruct-4bit
~/Models/mlx-community_Qwen2.5-0.5B-Instruct-4bit
```

Recommended starter models:

- Transcription: `mlx-community/whisper-tiny-mlx-q4`
- Summarization/Q&A: `mlx-community/Qwen2.5-0.5B-Instruct-4bit`

## Development

```bash
swift test
swift build -c release
Scripts/package_app.sh release
```

### Local model smoke test

```bash
say -v Samantha -o /tmp/scribeflowpro-smoke.aiff 'Scribe Flow Pro offline transcription smoke test. The local model should hear this sentence.'
ffmpeg -y -i /tmp/scribeflowpro-smoke.aiff -ar 16000 -ac 1 /tmp/scribeflowpro-smoke.wav
Scripts/setup_mlx_runtime.sh
SFP_LOCAL_MODEL_SMOKE=1 \
SFP_SMOKE_WHISPER_MODEL='mlx-community/whisper-tiny-mlx-q4' \
SFP_SMOKE_LLM_MODEL='mlx-community/Qwen2.5-0.5B-Instruct-4bit' \
SFP_SMOKE_AUDIO=/tmp/scribeflowpro-smoke.wav \
swift test --filter localMLXModelsSmoke
```

Expected output includes `SFP_SMOKE_TRANSCRIPT` and `SFP_SMOKE_SUMMARY` lines.

### Create a distributable zip

```bash
VERSION=$(grep MARKETING_VERSION version.env | cut -d= -f2)
rm -rf dist
mkdir -p dist/ScribeFlowPro
cp -R ScribeFlowPro.app dist/ScribeFlowPro/
cp README.md dist/ScribeFlowPro/
ditto -c -k --keepParent dist/ScribeFlowPro "dist/ScribeFlowPro-${VERSION}.zip"
shasum -a 256 "dist/ScribeFlowPro-${VERSION}.zip"
```

## Privacy

ScribeFlow Pro does not use telemetry, analytics, remote transcription, or hosted summarization. Network access is only used when explicitly downloading local models. After setup, transcription and summarization run on your Mac.

## Architecture

```text
ScribeFlowPro/
├── Audio/                  CoreAudio/AVFoundation capture
├── ML/                     Whisper and LLM actors
├── Models/                 SwiftData entities
├── Services/               Session, model, prompt, storage services
├── Views/                  SwiftUI app UI
└── Utilities/              Logging and helpers
```

Key implementation rules:

- Swift actors isolate audio and ML work
- SwiftData owns persisted meeting state
- Imported audio is copied into Application Support and deleted with its meeting
- Local model path resolution accepts nested and flat Hugging Face layouts
- SwiftPM packaging creates and ad-hoc signs `ScribeFlowPro.app`
- MLX bridge scripts are bundled inside the app resources

## Status

Active — v1.0.0. Local-first transcription and summarization. Ad-hoc signed.

## Contributing

This repository is not currently accepting external contributions.

## License

MIT
