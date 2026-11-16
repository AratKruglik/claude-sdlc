---
name: dart-tooling
description: |
  Dart and Flutter project tooling: pubspec.yaml dependency constraints, dart pub / flutter pub workflow, pubspec.lock policy, pub workspaces and melos monorepos, analysis_options.yaml with lint packages (lints, flutter_lints, very_good_analysis), dart format / dart analyze / dart fix, build_runner code generation (freezed, json_serializable, riverpod_generator, mockito). Stack-agnostic — referenced by every Dart plugin in the marketplace.

  Use this skill to:
  - Add a dependency with the right constraint in the right section.
  - Run the project's own formatter, analyzer and generator the way CI does.
  - Decide whether to commit pubspec.lock and generated files.
  - Work inside a pub workspace or melos monorepo without breaking sibling packages.

  Do NOT use this skill for:
  - Language idioms — see dart-foundation:dart-conventions.
  - Testing patterns — see dart-foundation:dart-testing.
user-invocable: false
paths: ["**/pubspec.yaml", "**/analysis_options.yaml", "**/build.yaml", "**/melos.yaml"]
---

# Dart Tooling

## Which CLI

- `pubspec.yaml` has `flutter:` under `dependencies` (`sdk: flutter`) → Flutter project: use `flutter pub ...`, `flutter analyze`, `flutter test`. `dart format` and `dart fix` still work.
- Otherwise → pure Dart: `dart pub ...`, `dart analyze`, `dart test`.
- If the repo pins an SDK with FVM (`.fvmrc` or `.fvm/`), prefix commands with `fvm` (`fvm flutter test`). Never switch the pinned version.

## Dependencies

Add with the CLI so the constraint and lockfile stay consistent:

```bash
dart pub add http                 # runtime dependency, caret constraint
dart pub add dev:mocktail         # dev_dependencies
dart pub add 'dev:build_runner'   # generators are dev-only
flutter pub add flutter_secure_storage
```

- Caret constraints (`^1.4.0`) for normal deps. Never `any`. Pin exactly only to work around a known regression, with a comment saying which.
- `dependency_overrides` is a temporary debugging tool — never ship it in a library; in an app, leave a comment with the upstream issue.
- `git:` and `path:` dependencies only for packages inside the same repo or ones not on pub.dev; a git dep must pin `ref:`.
- Check what a new package pulls in (`dart pub deps --style=compact`) and prefer packages with the "Dart 3 compatible" and verified-publisher signals on pub.dev. Do not add a dependency for a few lines of code.
- Run `dart pub outdated` before bumping; bump in a separate change from feature work unless the feature needs it.

### pubspec.lock policy

- Applications (Flutter apps, server binaries, CLIs): **commit** `pubspec.lock`.
- Reusable packages (published to pub.dev or consumed by other packages): do not commit it (the Dart team's guidance); respect the repo's existing choice if it differs.

## Monorepos

- **Pub workspaces** (Dart 3.6+): root `pubspec.yaml` has `workspace:` listing packages; each member has `resolution: workspace`. Run `dart pub get` from the root — one shared lockfile.
- **melos**: `melos.yaml` (or `melos:` in the root pubspec for melos 7). Use the repo's scripts: `melos bootstrap`, `melos run analyze`, `melos run test`. Do not run `pub get` per package by hand if melos manages linking.
- Change a shared package → run analyze and tests for every dependent package, not only the one you edited.

## Static analysis

`analysis_options.yaml` is the source of truth. Typical shapes:

```yaml
include: package:flutter_lints/flutter.yaml   # or package:lints/recommended.yaml / package:very_good_analysis/analysis_options.yaml

analyzer:
  language:
    strict-casts: true
    strict-raw-types: true
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"

linter:
  rules:
    - unawaited_futures
    - prefer_final_locals
```

- **Never** weaken `analysis_options.yaml` (removing rules, adding `ignore:` to `analyzer.errors`) to make a change pass. Fix the code. The sdlc config-protection hook blocks edits to this file during a run.
- `// ignore: rule_name` only for a genuine false positive, on the single line, with a reason in the same comment. Never `// ignore_for_file:` in hand-written code.
- Zero analyzer issues (errors, warnings *and* infos when the project's CI uses `--fatal-infos`) before reporting done.

## Formatting and fixes

```bash
dart format .                      # formats in place; CI usually runs: dart format --output=none --set-exit-if-changed .
dart fix --dry-run                 # preview automated fixes for lint and deprecations
dart fix --apply                   # apply them
```

- Dart 3.7+ uses the "tall" style and reads `formatter: page_width:` from `analysis_options.yaml` — do not pass `--line-length` by hand when the file sets it.
- Trailing commas drive layout in older formatter versions; follow the surrounding code.
- Never hand-format generated files.

## Code generation (build_runner)

Detect: `build_runner` in `dev_dependencies` plus annotations like `@freezed`, `@JsonSerializable`, `@riverpod`, `@GenerateMocks`, or `part 'x.g.dart';` directives.

```bash
dart run build_runner build --delete-conflicting-outputs
# Flutter projects: same command (or flutter pub run build_runner build ...)
```

- Edit the source (`user.dart`), regenerate, never edit `user.g.dart` / `user.freezed.dart` by hand.
- Whether generated files are committed is a repo decision — check `git ls-files '*.g.dart'` and `.gitignore`, then follow it.
- A generator error is a compile error: fix it before running tests.
- `build.yaml` configures generators (e.g. `json_serializable` `field_rename: snake`). Read it before writing models so field names match the wire format.

## Running things

```bash
dart run                       # bin/<package>.dart
dart run my_package:tool       # bin/tool.dart
dart compile exe bin/server.dart -o build/server   # AOT binary for deployment
```

For servers, `dart compile exe` (or the project's Dockerfile) is the release artefact; `dart run` is for development only (JIT, slower startup).

## Environment and secrets

- Server/CLI: read configuration from `Platform.environment`; fail fast with a clear message when a required variable is missing.
- Compile-time constants: `--define=KEY=value` (Dart) / `--dart-define` or `--dart-define-from-file` (Flutter), read with `const String.fromEnvironment('KEY')`. These are baked into the binary — never put real secrets there.
- `.env` files are never committed; commit `.env.example`.
