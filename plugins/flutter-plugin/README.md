# flutter-plugin

Flutter stack provider for the [SDLC Marketplace](../../README.md).

## What it does

Registers Flutter apps and packages with the SDLC pipeline. Provides a `flutter-architect` agent (Sonnet/medium) that implements a feature end-to-end — repository and API client, state, screens, navigation, localization — on mobile, web and desktop targets.

**Priority: 300, aspects: `backend` + `frontend`.** A Flutter project is one Dart codebase, so one agent owns all of it. Claiming `backend` as well is what keeps `dart-plugin` (priority 100) from activating alongside it: on any `pubspec.yaml` with `sdk: flutter`, `flutter-plugin` wins both aspects.

## Detection

Matches when `pubspec.yaml` exists and contains `sdk: flutter`.

## Agents

| Agent | Model | Role |
|---|---|---|
| `flutter-architect` | Sonnet/medium (plan pass: Opus) | Development-phase implementer for both aspects |

## Skills

| Skill | Description |
|---|---|
| `flutter-plugin:flutter-conventions` | Layout, widget composition, lifecycle, BuildContext rules, theming, responsive/adaptive UI, accessibility, gen-l10n, assets, platform channels, storage, performance |
| `flutter-plugin:flutter-state-management` | Riverpod / Bloc / Provider / plain notifiers — detect and follow the installed one; async state modelling; side effects; DI |
| `flutter-plugin:flutter-navigation` | go_router (shell routes, typed routes, redirects), auto_route, Navigator; deep links, App Links, Universal Links |
| `flutter-plugin:flutter-testing` | Widget tests with a pumpApp helper, Riverpod overrides, bloc_test, accessibility guidelines, goldens, integration_test |
| `dart-foundation:dart-conventions` | Dart 3 idioms (shared) |
| `dart-foundation:dart-tooling` | pub, lints, format/analyze/fix, build_runner (shared) |
| `dart-foundation:dart-testing` | package:test + mocktail basics (shared) |

## Hooks

- **PostToolUse** — `dart format` on every edited `.dart` file (generated `*.g.dart` / `*.freezed.dart` / `*.mocks.dart` skipped).
- **PreToolUse** — blocks edits to `analysis_options.yaml` and `.editorconfig` while a pipeline run is active.
- **SubagentStop** — `flutter analyze` once after `flutter-architect` finishes; failures go back to the orchestrator as a retry hint.

The pipeline never runs `flutter build` or `flutter run`: they need Xcode / Android SDK toolchains, devices and signing.
**Formatter width.** The hook runs plain `dart format`, which reads `formatter: page_width:` from `analysis_options.yaml` only when the package's language version is 3.7 or newer. A project on an older language version that formats with a custom `--line-length` will see edited files rewrapped to 80 columns — move to 3.7+ with `page_width`, or disable this plugin's PostToolUse hook for that project.

**FVM.** The hooks call `dart` / `flutter` from `PATH`. With an FVM-pinned SDK and no global install they skip silently; the architect still runs `fvm flutter analyze` itself.

## Dependencies

- [`sdlc`](../sdlc) — core pipeline
- [`dart-foundation`](../dart-foundation) — shared Dart skills

## Installation

```
/plugin install flutter-plugin@sdlc-marketplace
```

`sdlc` and `dart-foundation` are pulled automatically as dependencies. `dart-plugin` is not needed for Flutter projects; install it as well only if the repo also contains pure Dart packages or servers.

## Usage

```
/sdlc:start "Add an order history screen with pull-to-refresh"
```

On a `pubspec.yaml` with `sdk: flutter`, the orchestrator activates `flutter-plugin` (priority 300) and routes the development phase to `flutter-architect`.
