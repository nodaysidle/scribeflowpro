# ScribeFlowPro — Swift app source

## Purpose

Owns ScribeFlowPro Swift app source by feature area.

## Ownership

- `Audio`
- `ML`
- `Models`
- `ScribeFlowPro.entitlements`
- `ScribeFlowProApp.swift`
- `Services`
- `Utilities`
- `Views`

## Local Contracts

- Preserve SwiftPM structure and current app architecture.
- Keep UI behavior installable and testable, not demo-only.
- Do not introduce cloud/accounts/telemetry unless explicitly requested.

## Work Guidance

- Read this file after the root `AGENTS.md` before editing this subtree.
- Prefer extending existing modules/files over creating parallel duplicate systems.
- Update this `AGENTS.md` only when durable ownership, contracts, or verification guidance changes.

## Verification

- `swift test` when code/tests change.
- `swift build` when app source changes.

## Child DOX Index

None.
