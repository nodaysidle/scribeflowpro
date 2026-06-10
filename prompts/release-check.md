# Release Check Prompt

## Repo

- Name: ScribeFlowPro
- Path: `/Volumes/omarchyuser/projekti/scribeflowpro`
- Root contract: `AGENTS.md`

## Purpose

Use this prompt for release-readiness review before packaging, publishing, merging, deploying, notarizing, or announcing anything.

## Mode

Read-only. Do not modify files.

## Use When

- Before a release branch is merged.
- Before building or uploading release artifacts.
- Before publishing a GitHub Release.
- Before app install/package/notarization work.

## Instructions

IMPORTANT: This task is single-session only. Do not use multi_agent_v2, spawn_agent, send_input, resume_agent, wait_agent, close_agent, subagents, delegation, or child agents.

Inspect release readiness using live repo files and the root Verification Ladder. Do not perform the release.

## Read Order

1. `AGENTS.md`
2. nearest child `AGENTS.md` files for release/package/build areas
3. `README.md`, `CHANGELOG.md`, `TODO.md`, and release docs when present
4. version metadata: `package.json`, `Package.swift`, `Cargo.toml`, app manifests, or equivalent
5. scripts/workflows used by the Verification Ladder
6. `git status --short`
7. `git log --oneline -5`

## Output Format

- Release readiness: `GO`, `NO-GO`, or `UNKNOWN`
- Target version/artifact:
- Dirty git state:
- Required verification commands:
- Commands already safe to run:
- Commands requiring NDI approval:
- Blocking issues:
- Non-blocking risks:
- Exact next safe step:

## Hard Stops

- Do not edit files.
- Do not clean the worktree.
- Do not install dependencies unless explicitly approved.
- Do not package or install artifacts.
- Do not publish releases.
- Do not merge to `main`.
- Do not push branches or tags.
- Do not sign, notarize, deploy, or alter release assets.
- If a fact is unknown, write `UNKNOWN`.

## Verification

Quote the root Verification Ladder and cite exact files that define version/build/release behavior.

Work sequentially through the read order. Do not spawn child agents.
