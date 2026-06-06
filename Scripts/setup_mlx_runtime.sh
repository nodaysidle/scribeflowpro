#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/ScribeFlowPro"
VENV="$APP_SUPPORT/venv"
MODELS="$HOME/Models"

mkdir -p "$APP_SUPPORT" "$MODELS"

if [[ ! -x "$VENV/bin/python" ]]; then
    python3 -m venv "$VENV"
fi

"$VENV/bin/python" -m pip install --upgrade pip
"$VENV/bin/python" -m pip install --upgrade mlx-whisper mlx-lm huggingface-hub

hf download mlx-community/whisper-tiny-mlx-q4 \
    --local-dir "$MODELS/mlx-community_whisper-tiny-mlx-q4"

hf download mlx-community/Qwen2.5-0.5B-Instruct-4bit \
    --local-dir "$MODELS/mlx-community_Qwen2.5-0.5B-Instruct-4bit"

printf 'ScribeFlowPro MLX runtime ready:\n'
printf '  Python: %s\n' "$VENV/bin/python"
printf '  Whisper: %s\n' "$MODELS/mlx-community_whisper-tiny-mlx-q4"
printf '  LLM: %s\n' "$MODELS/mlx-community_Qwen2.5-0.5B-Instruct-4bit"
