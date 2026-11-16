---
stack: flutter
priority: 300
aspects: [backend, frontend]
detect:
  all:
    - file_exists: pubspec.yaml
    - file_contains:
        path: pubspec.yaml
        pattern: 'sdk:\s*flutter'
---

# Flutter Stack Profile

Flutter app and package stack provider. Triggers when `pubspec.yaml` declares a dependency on `sdk: flutter`. Priority 300 — the same tier as `react-native-plugin`.

Claims BOTH `backend` AND `frontend` aspects. A Flutter project is one Dart codebase — UI, state, repositories and API clients all live in `lib/` — so one agent owns all of it. Claiming `backend` is also what keeps `dart-plugin` (priority 100, `backend`, detects any `pubspec.yaml`) from activating alongside it on the same project.

Targets: iOS, Android, web, macOS, Windows, Linux — detected from the platform folders present. A pure Dart package in a Flutter monorepo (no `sdk: flutter`) is handled by `dart-plugin` when the pipeline runs in that package's directory.

## Agents per phase

- business_analysis: business-analyst        # core agent
- development: flutter-architect             # ⚡ Flutter-specific
- qa: qa-engineer                            # core agent
- security: security-analyst                 # core agent
- documentation: document-writer             # core agent

## Convention skills to apply

- flutter-plugin:flutter-conventions
- flutter-plugin:flutter-state-management
- flutter-plugin:flutter-navigation
- flutter-plugin:flutter-testing
- dart-foundation:dart-conventions
- dart-foundation:dart-tooling
- dart-foundation:dart-testing
- frontend-design:frontend-design  # optional external; skipped automatically when absent

## Extra phases

(none)

## Phase prompts injection

For development phase, inject:
  "Flutter project. Detect before writing anything:
   - SDK: `environment: sdk:` and `flutter:` constraints in pubspec.yaml; `.fvmrc` / `.fvm/` → run every command through `fvm` (`fvm flutter ...`).
   - Targets: which of `android/`, `ios/`, `web/`, `macos/`, `windows/`, `linux/` exist. Do not add a platform folder unless the BA spec asks for that platform.
   - App vs package: `lib/main.dart` (or `lib/main_*.dart` flavors) → app; no entry point + `flutter:` plugin section → plugin/package.
   - State management — match what is installed, never introduce a second one: `flutter_riverpod`/`hooks_riverpod` (+ `riverpod_annotation` → code-gen providers), `flutter_bloc` (Bloc vs Cubit — mirror neighbours), `provider`, `get`/`getx`, `mobx`, or plain `ValueNotifier`/`ChangeNotifier`.
   - Navigation: `go_router` (typed routes if `go_router_builder`), `auto_route`, or plain `Navigator`/`MaterialApp.routes`.
   - Models: `freezed` + `json_serializable` (regenerate with build_runner), `equatable`, or hand-written.
   - Networking: `dio` (interceptors for auth/refresh) or `http`; API layer lives behind repository classes, never called from widgets.
   - Storage: `flutter_secure_storage` (secrets), `shared_preferences` (non-sensitive prefs), `hive`/`isar`/`drift`/`sqflite` (local DB).
   - Localization: `l10n.yaml` + `lib/l10n/*.arb` → every new user-facing string goes into the ARB files and is read via `AppLocalizations.of(context)`.
   - Feature layout: mirror the existing structure (feature-first `lib/features/<x>/{data,domain,presentation}` or layer-first) — do not reorganize.
   Build UI from small `const`-constructible widgets; use `Theme.of(context)` tokens instead of hard-coded colors and text styles; respect `MediaQuery`/`SafeArea` and text scaling; every tappable control has a semantic label.
   Formatting is applied per edited file by the plugin's PostToolUse hook — never run `dart format` repo-wide. `flutter analyze` runs after you return via the SubagentStop hook and must be clean.
   Apply skills: flutter-plugin:flutter-conventions, flutter-plugin:flutter-state-management, flutter-plugin:flutter-navigation, dart-foundation:dart-conventions, dart-foundation:dart-tooling.
   If superpowers is available, invoke superpowers:verification-before-completion before returning."

For qa phase, inject:
  "Flutter testing strategy:
   - Unit tests (`test/`) for repositories, notifiers/blocs, mappers: `flutter_test` + `mocktail` (stay on `mockito` only if already used).
   - Bloc/Cubit: `bloc_test` `blocTest(build:, act:, expect:)`. Riverpod: `ProviderContainer` with `overrides` (`ProviderScope(overrides: ...)` in widget tests); dispose containers via `addTearDown`.
   - Widget tests: `testWidgets` + `pumpWidget` wrapped in the app's real theme/localization/router scaffolding (reuse an existing `pumpApp` helper if present). Find by `find.byType`, `find.text`, `find.bySemanticsLabel`, `find.byKey` — in that order of preference. `pumpAndSettle` only when animations must finish; prefer explicit `pump(duration)`.
   - Accessibility: `expect(tester, meetsGuideline(androidTapTargetGuideline))`, `textContrastGuideline`, `labeledTapTargetGuideline` for new screens.
   - Goldens (only if the project already has golden tests): `matchesGoldenFile`, update with `flutter test --update-goldens` and say so in the report — fonts and platform differ between machines.
   - Integration tests (`integration_test/`) only if the directory exists; they need a device/emulator and are not run in the pipeline.
   Run: `flutter test` (add `--coverage` when CI collects coverage).
   Apply skills: flutter-plugin:flutter-testing, dart-foundation:dart-testing."

For security phase, inject:
  "Flutter-specific security checks in addition to OWASP Mobile Top 10:
   - Secrets/tokens: `flutter_secure_storage` only — never `shared_preferences`, Hive without encryption, or plain files.
   - Nothing secret in the binary: `--dart-define` / `--dart-define-from-file` values, `assets/` JSON and `.env` files bundled via `flutter_dotenv` are all extractable from the APK/IPA.
   - Transport: HTTPS only; no `badCertificateCallback` returning true; `android:usesCleartextTraffic` and iOS `NSAllowsArbitraryLoads` must not be enabled for release; certificate pinning for sensitive apps (banking, health).
   - Deep links / App Links / Universal Links: validate scheme, host and every parameter before navigating; `assetlinks.json` / `apple-app-site-association` must match the declared domains; go_router `redirect` must enforce auth on protected routes.
   - WebViews (`webview_flutter`): restrict navigation with a `NavigationDelegate`, keep `JavaScriptMode.disabled` unless required, never pass tokens through `JavaScriptChannel`.
   - Platform channels: validate arguments on the native side; never expose a generic 'run command' or file-path method.
   - Logging: no tokens/PII in `print`/`debugPrint`/logger output; release builds strip debug logging.
   - Release hardening: `--obfuscate --split-debug-info` for release builds, `android:allowBackup=\"false\"` when the app stores sensitive data, exported Android components reviewed.
   - Permissions: only the permissions the feature needs in `AndroidManifest.xml` / `Info.plist`, each with a usage description on iOS.
   - Dependencies: `flutter pub outdated`; flag packages with known advisories (pub prints them on `pub get`)."

## Pre-phase commands

(none)

## Post-pipeline checks

No `flutter build` — release builds need Xcode / Android SDK toolchains and signing, and are not run in the pipeline. `flutter analyze` is the compile-equivalent safety net.

- flutter analyze
- flutter test
