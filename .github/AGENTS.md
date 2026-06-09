# .github — GitHub automation

## Purpose

Owns GitHub Actions workflows and repository automation.

## Ownership

- `workflows`

## Local Contracts

- CI/release automation changes require verification and must not expose secrets.
- Do not alter publishing behavior unless explicitly requested.

## Work Guidance

- Read this file after the root `AGENTS.md` before editing this subtree.
- Prefer extending existing modules/files over creating parallel duplicate systems.
- Update this `AGENTS.md` only when durable ownership, contracts, or verification guidance changes.

## Verification

- Read changed files back.
- Inspect `git diff --name-only` / `git status --short`.

## Child DOX Index

None.
