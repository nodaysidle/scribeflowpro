# DOX Audit Prompt

## Repo

- Name: ScribeFlowPro
- Path: `/Volumes/omarchyuser/projekti/scribeflowpro`
- Root contract: `AGENTS.md`

## Purpose

Use this prompt to verify that the DOX / `AGENTS.md` hierarchy is navigable, truthful, and safe for future coding agents.

## Mode

Read-only. Do not modify files.

## Use When

- After adding or changing any `AGENTS.md` file.
- Before asking Codex/Hermes to perform implementation work in this repo.
- When child folder ownership, verification commands, or constraints may have drifted.

## Instructions

IMPORTANT: This task is single-session only. Do not use multi_agent_v2, spawn_agent, send_input, resume_agent, wait_agent, close_agent, subagents, delegation, or child agents.

Audit the DOX hierarchy and report exact gaps. Do not repair anything.

## Read Order

1. root `AGENTS.md`
2. every child `AGENTS.md` listed under root `Child DOX Index`
3. each nested child `AGENTS.md` referenced by those child indexes
4. `README.md` and command metadata only if needed to verify claimed commands
5. `git status --short`

## Output Format

- Score: `<number>/10`
- Verdict:
- Critical issues:
- Missing child docs:
- Dead child-index targets:
- Parent/child rule conflicts:
- Verification Ladder gaps:
- Stale or invented commands:
- Exact files involved:
- Recommended minimal fixes:

## Hard Stops

- Do not edit files.
- Do not create missing `AGENTS.md` files.
- Do not clean the worktree.
- Do not run package/install/release commands.
- Do not publish, merge, push, notarize, or deploy.
- If a fact is unknown, write `UNKNOWN`.

## Verification

List every `AGENTS.md` file inspected and explicitly state whether all `Child DOX Index` targets exist.

Work sequentially through the read order. Do not spawn child agents.
