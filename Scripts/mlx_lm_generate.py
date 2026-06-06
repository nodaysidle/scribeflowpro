#!/usr/bin/env python3
"""ScribeFlowPro MLX-LM bridge.

Generates text from a local mlx-community LLM directory and emits JSON:
{"text":"..."}
"""
from __future__ import annotations

import argparse
import contextlib
import io
import json
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--max-tokens", type=int, default=512)
    parser.add_argument("--temperature", type=float, default=0.3)
    args = parser.parse_args()

    try:
        from mlx_lm import generate, load

        noisy_stdout = io.StringIO()
        noisy_stderr = io.StringIO()
        with contextlib.redirect_stdout(noisy_stdout), contextlib.redirect_stderr(noisy_stderr):
            model, tokenizer = load(args.model)
            text = generate(
                model,
                tokenizer,
                prompt=args.prompt,
                max_tokens=args.max_tokens,
                verbose=False,
                temp=args.temperature,
            )

        print(json.dumps({"text": text}, ensure_ascii=False))
        return 0
    except TypeError:
        try:
            from mlx_lm import generate, load
            model, tokenizer = load(args.model)
            text = generate(model, tokenizer, prompt=args.prompt, max_tokens=args.max_tokens, verbose=False)
            print(json.dumps({"text": text}, ensure_ascii=False))
            return 0
        except Exception as exc:  # noqa: BLE001
            print(json.dumps({"error": str(exc)}), file=sys.stderr)
            return 2
    except Exception as exc:  # noqa: BLE001
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
