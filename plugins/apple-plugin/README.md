# apple-plugin

Apple platforms stack provider for the [SDLC Marketplace](../../README.md).

## What it does

Registers native Apple app projects with the SDLC pipeline. Provides an `apple-architect` agent (Sonnet/medium) that implements a feature end-to-end — API client, persistence, state, SwiftUI screens, navigation, localization, project wiring — on iOS, iPadOS, macOS and watchOS targets, including widgets and App Intents.

**Priority: 300, aspects: `backend` + `frontend`.** An Apple app is one Swift codebase, so one agent owns all of it. Claiming `backend` as well is what keeps `swift-plugin` (priority 100) from activating alongside it when the app also has a root `Package.swift`.

## Detection

Matches when the project root contains any of:

- an `*.xcodeproj` or `*.xcworkspace`
- a Tuist manifest: `Project.swift` or `Tuist.swift`
- an XcodeGen `project.yml` with a `targets:` section

Detection is anchored to the root, so the `ios/` Xcode project inside a Flutter or React Native app does not activate this plugin. When the Xcode project lives in a subdirectory, run the pipeline there or pass `--stack=apple`.

## Agents

| Agent | Model | Role |
|---|---|---|
| `apple-architect` | Sonnet/medium (plan pass: Opus) | Development-phase implementer for both aspects |

## Skills

| Skill | Description |
|---|---|
| `apple-plugin:swiftui-conventions` | App and scene structure, view composition, `.task`, layout, design tokens, Liquid Glass-era system look, accessibility, String Catalogs, previews, UIKit / AppKit interop, performance |
| `apple-plugin:swiftui-state` | Observation vs `ObservableObject` vs TCA — detect and follow; ownership rules; MainActor models; dependency injection; SwiftData and Core Data |
| `apple-plugin:swiftui-navigation` | `NavigationStack` routes, `NavigationSplitView`, tabs, sheets / inspectors / alerts, deep links and Universal Links, state restoration |
| `apple-plugin:ios-ipados` | Size classes, resizable iPad windows and foldable screens, multiple scenes, pointer / keyboard / drag and drop / Pencil, background work, notifications, permissions, privacy manifests, widgets, Live Activities, App Intents, Mac Catalyst |
| `apple-plugin:macos-app` | Mac scenes and windows, menus and commands, `Table` / inspector / toolbar idioms, App Sandbox and security-scoped bookmarks, document apps, login items, AppKit interop, hardened runtime |
| `apple-plugin:watchos-app` | Glanceable watch UI, navigation and Digital Crown, complications and Smart Stack, WatchConnectivity, background refresh, workouts and HealthKit |
| `apple-plugin:apple-testing` | Model tests, in-memory SwiftData / Core Data, TCA `TestStore`, XCUITest, snapshots, running tests per platform with `xcodebuild` |
| `swift-foundation:swift-conventions` | Swift 6 idioms and strict concurrency (shared) |
| `swift-foundation:swift-tooling` | SwiftPM, xcodebuild, project styles, formatters and linters (shared) |
| `swift-foundation:swift-testing` | Swift Testing / XCTest basics (shared) |

## Hooks

- **PostToolUse** — formats every edited `.swift` file with the tool the project configured: `swift format --in-place` when `.swift-format` exists, `swiftformat` when `.swiftformat` exists, nothing otherwise.
- **PreToolUse** — blocks edits to `.swiftlint.yml`, `.swift-format` and `.swiftformat` while a pipeline run is active.
- **SubagentStop** — `swiftlint lint` once after `apple-architect` finishes, only when the project has `.swiftlint.yml`; violations go back to the orchestrator as a retry hint.

There is no compile hook: `xcodebuild` needs a scheme and destination that only the architect can choose, so `apple-architect` compiles every platform target it touched itself. The pipeline never archives, signs, notarizes or uploads.

**Requirements.** Building and testing need macOS with Xcode and the simulator runtimes for the platforms you target. On other hosts the architect can still write code, but cannot verify it.

## Dependencies

- [`sdlc`](../sdlc) — core pipeline
- [`swift-foundation`](../swift-foundation) — shared Swift skills

## Installation

```
/plugin install apple-plugin@sdlc-marketplace
```

`sdlc` and `swift-foundation` are pulled automatically as dependencies. `swift-plugin` is not needed for app projects; install it as well only if the repo also contains server-side Swift or host-only packages you run the pipeline on separately.

## Usage

```
/sdlc:start "Add an order history screen with pull-to-refresh on iPhone and iPad"
```

On a project with an Xcode project or Tuist / XcodeGen manifest in the root, the orchestrator activates `apple-plugin` (priority 300) and routes the development phase to `apple-architect`.
