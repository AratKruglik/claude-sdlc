# dart-plugin

Plain Dart backend stack provider for the [SDLC Marketplace](../../README.md).

## What it does

Registers any Dart project with the SDLC pipeline. Provides a `dart-architect` agent (Sonnet/medium) as the development-phase backend implementer for pure Dart code: packages, CLI tools and HTTP servers (`shelf`, `dart_frog`, plain `dart:io`).

**Priority: 100.** On a Flutter project, `flutter-plugin` (priority 300) claims both the `backend` and `frontend` aspects and `dart-plugin` stays inactive for that project.

## Detection

Matches any project with `pubspec.yaml` in the root.

## Agents

| Agent | Model | Role |
|---|---|---|
| `dart-architect` | Sonnet/medium | Development-phase backend implementer |

## Skills (via dart-foundation)

| Skill | Description |
|---|---|
| `dart-foundation:dart-conventions` | Dart 3 idioms: null safety, records, patterns, sealed classes, async discipline |
| `dart-foundation:dart-tooling` | pubspec constraints, pub workspaces/melos, analysis_options, format/analyze/fix, build_runner |
| `dart-foundation:dart-testing` | package:test, mocktail, async/stream matchers, coverage |

## Hooks

- **PostToolUse** — `dart format` on every edited `.dart` file (generated `*.g.dart` / `*.freezed.dart` / `*.mocks.dart` skipped).
- **PreToolUse** — blocks edits to `analysis_options.yaml` and `.editorconfig` while a pipeline run is active.
- **SubagentStop** — `dart analyze` once after `dart-architect` finishes; failures go back to the orchestrator as a retry hint.

All three resolve the `dart` binary locally first, then inside a running Docker Compose service, and stay silent when neither has it.
**Formatter width.** The hook runs plain `dart format`, which reads `formatter: page_width:` from `analysis_options.yaml` only when the package's language version is 3.7 or newer. A project on an older language version that formats with a custom `--line-length` will see edited files rewrapped to 80 columns — move to 3.7+ with `page_width`, or disable this plugin's PostToolUse hook for that project.

**FVM.** The hooks call `dart` / `flutter` from `PATH`. With an FVM-pinned SDK and no global install they skip silently; the architect still runs `fvm flutter analyze` itself.

## Dependencies

- [`sdlc`](../sdlc) — core pipeline
- [`dart-foundation`](../dart-foundation) — shared Dart skills

## Installation

```
/plugin install dart-plugin@sdlc-marketplace
```

`sdlc` and `dart-foundation` are pulled automatically as dependencies.

## Usage

```
/sdlc:start "Add a /health endpoint with build info"
```

On a `pubspec.yaml` project without `sdk: flutter`, the orchestrator activates `dart-plugin` (priority 100) and routes the development phase to `dart-architect`.
