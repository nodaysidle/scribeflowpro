# ScribeFlowPro — AGENTS.md

## NODAYSIDLE Law

NODAYSIDLE quality bar: 9.7/10. Ship installable, polished apps. Finished beats fancy. Verified beats assumed.

## Repository Map

If `codemap.md` exists in the project root, read it first for architecture, entry points, directory responsibilities, and data-flow context.

If no root `codemap.md` exists, fall back to:
- this `AGENTS.md`
- the closest child `AGENTS.md` files on the path to the target
- `README.md`
- `PRD.md`, `ARD.md`, `TRD.md`, `TASKS.md`, `TODO.md`, and `CHANGELOG.md` when present
- real entry-point files and config files

## DOX Self-Documentation Contract

This repo uses a DOX-style self-documenting `AGENTS.md` hierarchy for Codex and other coding agents.

Before editing:
1. Read this root `AGENTS.md`.
2. Identify the exact files/folders to touch.
3. Walk the nearest `AGENTS.md` chain from root to target folder.
4. Use the closest `AGENTS.md` for local contracts.
5. Parent rules still apply. Child docs may specialize; they may not weaken parent rules or NODAYSIDLE law.

After meaningful edits:
1. Update the closest relevant `AGENTS.md` only if a durable local contract, file responsibility, verification command, or gotcha changed.
2. Update parent `Child DOX Index` sections only when child docs are added, removed, or repointed.
3. Do not write progress logs, task history, diary notes, or one-off implementation receipts into `AGENTS.md`.
4. Keep docs concise, operational, and true to live files.

Create child `AGENTS.md` files only for durable boundaries with distinct ownership, rules, verification, or architecture. Do not document generated folders such as `dist/`, `node_modules/`, `target/`, `.build/`, `artifacts/`, `.git/`, or release outputs.

## Global Rules

- Make the smallest correct change.
- Do not refactor unrelated code.
- Do not add dependencies without explicit approval.
- Do not change release, signing, notarization, deployment, billing, or credential settings unless asked.
- Do not clean the worktree, delete files, rewrite history, force-push, or remove backups without explicit approval.
- Preserve current stack and architecture unless the task explicitly requires changing them.
- If current code conflicts with these rules, report the conflict before editing.

## Stack Lock

- Native macOS Swift/SwiftPM app.
- Offline-first transcription workflow. Do not add cloud transcription, accounts, telemetry, or proprietary storage unless explicitly requested.
- Preserve installable `.app` packaging path and current Swift Package Manager structure.

Swift package entrypoint: `Package.swift`. Verify targets/products from the live manifest before changing source.

## Safety and Approval Policy

Agents must stop and request explicit NDI approval before any action that can destroy, expose, publish, spend, deploy, or permanently alter project state.

Approval required for:
- deleting files, directories, branches, tags, releases, backups, databases, caches, or generated assets outside normal build output
- force-push, history rewrite, branch deletion, tag deletion, or main-branch merges
- publishing releases, packages, installers, app bundles, websites, docs, or public artifacts
- deployment changes, production config changes, DNS changes, Vercel/Supabase/cloud settings, or webhook changes
- credential, token, signing, notarization, keychain, permission, entitlement, or billing changes
- installing/moving artifacts outside the repo, including `/Applications`, unless the task explicitly includes install/package verification
- dependency upgrades, framework swaps, runtime changes, or generated migration scripts
- destructive cleanup commands such as `rm -rf`, `git clean`, `reset --hard`, database wipes, or cache wipes without named scope

Allowed without extra approval when already within the requested task:
- reading files
- running non-destructive checks
- editing approved instruction files
- running format/lint/test/build commands that do not publish or deploy
- creating repo-local Markdown documentation within the approved scope

If unsure, stop and ask. Do not guess.

## Verification Ladder

Run the lowest sufficient rung for the change. Do not claim completion without recording the command and result.

1. **Read-only audit**
   - `git status --short`
   - Read this root `AGENTS.md`, the nearest child `AGENTS.md`, and the target files.
   - Do not modify files.

2. **Unit / fast checks**
   - `swift test`

3. **Full build / static checks**
   - `swift build`
   - `swift build -c release`

4. **Runtime smoke**
   - `UNKNOWN` — no dedicated runtime smoke command was verified in repo metadata.

5. **Package / install**
   - `Scripts/package_app.sh release`
   - Installing outside the repo or replacing an app in `/Applications` requires explicit NDI approval.

6. **Release gate**
   - Pushing branches is allowed only when requested.
   - Merging to `main`, publishing GitHub Releases, notarization, signing changes, deployment changes, credential changes, and destructive cleanup require explicit NDI approval.

For docs-only `AGENTS.md` changes, verify with:
- `find . -name AGENTS.md -not -path './.git/*' -not -path './node_modules/*' -not -path './src-tauri/target/*' -not -path './target/*' -not -path './.build/*' | sort`
- `git status --short`
- confirm no product source/config files changed unless explicitly intended.

## Prompt Commands

Reusable repo-local agent prompts live in `prompts/`.

- `prompts/repo-orientation.md` — read-only repo onboarding and command discovery.
- `prompts/dox-audit.md` — read-only DOX/AGENTS hierarchy audit.
- `prompts/release-check.md` — read-only release-readiness audit.

Prompt files are instruction templates, not executable scripts. Keep them short, current, and verified against live repo commands.

## Child DOX Index

- `Scripts/AGENTS.md` — Automation scripts.
- `docs/AGENTS.md` — Project documentation.
- `.github/AGENTS.md` — GitHub automation.
- `Tests/AGENTS.md` — Tests.
- `ScribeFlowPro/AGENTS.md` — Swift app source.
