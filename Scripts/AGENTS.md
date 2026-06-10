# Scripts — Automation scripts

## Purpose

Owns local build, package, smoke, install, QA, and release helper scripts.

## Ownership

- `mlx_lm_generate.py`
- `mlx_whisper_transcribe.py`
- `package_app.sh`
- `setup_mlx_runtime.sh`

## Local Contracts

- Scripts must be safe, deterministic, and scoped.
- Do not delete user data, releases, caches, or installed apps without explicit approval.

## Work Guidance

- Read this file after the root `AGENTS.md` before editing this subtree.
- Prefer extending existing modules/files over creating parallel duplicate systems.
- Update this `AGENTS.md` only when durable ownership, contracts, or verification guidance changes.

## Verification

- Read changed files back.
- Inspect `git diff --name-only` / `git status --short`.

## Child DOX Index

None.
