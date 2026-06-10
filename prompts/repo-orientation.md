# Repo Orientation Prompt

## Repo

- Name: ScribeFlowPro
- Path: `/Volumes/omarchyuser/projekti/scribeflowpro`
- Root contract: `AGENTS.md`

## Purpose

Use this prompt before editing a repo. The goal is to understand the project through live files, not memory.

## Mode

Read-only. Do not modify files.

## Use When

- Starting work in this repo.
- Handing the repo to Codex/Hermes for the first time in a session.
- Checking whether the repo is safe to edit.
- Reconstructing stack, entry points, commands, and dirty state.

## Instructions

IMPORTANT: This task is single-session only. Do not use multi_agent_v2, spawn_agent, send_input, resume_agent, wait_agent, close_agent, subagents, delegation, or child agents.

Read the repository and produce a concise orientation report.

## Read Order

1. `AGENTS.md`
2. nearest child `AGENTS.md` files relevant to the inspected area
3. `README.md` if present
4. `codemap.md`, `PRD.md`, `ARD.md`, `TRD.md`, `TASKS.md`, `TODO.md`, and `CHANGELOG.md` when present
5. `package.json`, `Package.swift`, `Cargo.toml`, `pyproject.toml`, workflows, scripts, or equivalent metadata if present
6. `git status --short`

## Output Format

- Project purpose:
- Stack:
- Entry points:
- Important directories:
- Verification Ladder:
- Dirty git state:
- Release/package notes:
- Risks:
- Best first command to run:

## Hard Stops

- Do not edit files.
- Do not clean the worktree.
- Do not install dependencies.
- Do not package, publish, merge, or release.
- Do not publish anything.
- If a fact is unknown, write `UNKNOWN`.

## Verification

Report the files read and the exact command output used for git state and command discovery.

Work sequentially through the read order. Do not spawn child agents.
