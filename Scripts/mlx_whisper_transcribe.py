#!/usr/bin/env python3
"""ScribeFlowPro MLX Whisper bridge.

Transcribes one audio file with a local mlx-community Whisper model and emits JSON:
{"segments":[{"text":"...","start":0.0,"end":1.0,"confidence":0.9}],"text":"..."}
"""
from __future__ import annotations

import argparse
import contextlib
import io
import json
import math
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--audio", required=True)
    parser.add_argument("--language", default="en")
    args = parser.parse_args()

    try:
        from mlx_whisper import transcribe

        noisy_stdout = io.StringIO()
        noisy_stderr = io.StringIO()
        with contextlib.redirect_stdout(noisy_stdout), contextlib.redirect_stderr(noisy_stderr):
            result = transcribe(
                args.audio,
                path_or_hf_repo=args.model,
                language=args.language,
                verbose=False,
            )

        segments = []
        for segment in result.get("segments", []):
            avg_logprob = float(segment.get("avg_logprob", 0.0) or 0.0)
            confidence = max(0.0, min(1.0, math.exp(avg_logprob)))
            segments.append(
                {
                    "text": str(segment.get("text", "")).strip(),
                    "start": float(segment.get("start", 0.0) or 0.0),
                    "end": float(segment.get("end", 0.0) or 0.0),
                    "confidence": confidence,
                }
            )

        print(json.dumps({"text": str(result.get("text", "")).strip(), "segments": segments}, ensure_ascii=False))
        return 0
    except Exception as exc:  # noqa: BLE001 - bridge must report clean JSON errors to Swift
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
