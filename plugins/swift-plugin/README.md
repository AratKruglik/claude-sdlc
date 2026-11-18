# swift-plugin

Plain Swift backend stack provider for the [SDLC Marketplace](../../README.md).

## What it does

Registers any SwiftPM project with the SDLC pipeline. Provides a `swift-architect` agent (Sonnet/medium) as the development-phase backend implementer for Swift packages, command-line tools (`swift-argument-parser`) and HTTP servers (Vapor + Fluent, Hummingbird).

**Priority: 100.** On a project with an Xcode project, workspace, or Tuist / XcodeGen manifest in the root, `apple-plugin` (priority 300) claims both the `backend` and `frontend` aspects and `swift-plugin` stays inactive for that project.

## Detection

Matches any project with `Package.swift` in the root.

A package that only builds for iOS / watchOS (it imports UIKit or WatchKit) cannot be compiled with `swift build` on the host — run the pipeline on it with `--stack=apple`.

## Agents

| Agent | Model | Role |
|---|---|---|
| `swift-architect` | Sonnet/medium (plan pass: Opus) | Development-phase backend implementer |

## Skills (via swift-foundation)

| Skill | Description |
|---|---|
| `swift-foundation:swift-conventions` | Swift 6 idioms: value types, optionals, errors, generics, strict concurrency |
| `swift-foundation:swift-tooling` | `Package.swift`, dependencies, swift build/test, formatters and linters |
| `swift-foundation:swift-testing` | Swift Testing and XCTest, async tests, test doubles, coverage |

## Hooks

- **PostToolUse** — formats every edited `.swift` file with the tool the project configured: `swift format --in-place` when `.swift-format` exists, `swiftformat` when `.swiftformat` exists, nothing otherwise. Generated `*.generated.swift` / `*.pb.swift` files are skipped.
- **PreToolUse** — blocks edits to `.swiftlint.yml`, `.swift-format` and `.swiftformat` while a pipeline run is active.
- **SubagentStop** — `swift build --build-tests` once after `swift-architect` finishes; compile errors go back to the orchestrator as a retry hint. The timeout is 300 seconds to leave room for a cold build.

All three resolve the toolchain locally first, then inside a running Docker Compose service (the official `swift` images work), and stay silent when neither has it.

## Dependencies

- [`sdlc`](../sdlc) — core pipeline
- [`swift-foundation`](../swift-foundation) — shared Swift skills

## Installation

```
/plugin install swift-plugin@sdlc-marketplace
```

`sdlc` and `swift-foundation` are pulled automatically as dependencies.

## Usage

```
/sdlc:start "Add a /health endpoint with build info"
```

On a `Package.swift` project without an Xcode app project, the orchestrator activates `swift-plugin` (priority 100) and routes the development phase to `swift-architect`.
