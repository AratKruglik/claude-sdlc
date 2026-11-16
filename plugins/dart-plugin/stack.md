---
stack: dart
aspects: [backend]
priority: 100
detect:
  any:
    - file_exists: pubspec.yaml
---

# Dart Stack Profile (backend)

Registers any Dart project (`pubspec.yaml` in the project root) with the SDLC pipeline. Covers:
- Pure Dart packages and libraries (pub.dev or internal)
- CLI tools (`bin/`, `package:args`)
- HTTP servers and APIs: `shelf` + `shelf_router`, `dart_frog`, plain `dart:io` `HttpServer`
- Shared Dart packages inside a Flutter monorepo (a package without `sdk: flutter`)

**Flutter projects are not handled here.** `flutter-plugin` (priority 300) claims both the `backend` and `frontend` aspects on any `pubspec.yaml` that depends on `sdk: flutter`, so it wins and `dart-plugin` stays inactive for that project.

## Agents per phase

```yaml
business_analysis: business-analyst         # core agent (aspect-agnostic)
development:
  backend: dart-architect                   # owned by this plugin
qa: qa-engineer                             # core agent
security: security-analyst                  # core agent
documentation: document-writer             # core agent
```

## Convention skills to apply

- dart-foundation:dart-conventions
- dart-foundation:dart-tooling
- dart-foundation:dart-testing

## Phase prompts injection

For development phase (backend aspect), inject:
> You are working on a **pure Dart** project (no Flutter SDK dependency).
> Detect the project shape from `pubspec.yaml` and the tree:
> - `dart_frog` in dependencies + `routes/` → Dart Frog server (file-based routes, `onRequest` handlers, middleware via `_middleware.dart`, providers for DI).
> - `shelf` / `shelf_router` → Shelf server (`Pipeline` + `Middleware`, `Router` handlers returning `Response`).
> - `args` + `bin/` → CLI (`CommandRunner` + `Command` subclasses, exit codes via `exitCode`).
> - Otherwise → library package: public API exported from `lib/<package>.dart`, implementation in `lib/src/`.
> - `workspace:` in the root `pubspec.yaml` or a `melos.yaml` → monorepo: work inside the target package, then analyze and test every dependent package.
>
> Apply `dart-foundation:dart-conventions`: sound null safety without `!` sprinkling, sealed classes + exhaustive `switch` for closed hierarchies, records for multi-value returns, `final`/`const` by default, no dropped futures. Respect the SDK lower bound in `environment: sdk:` — do not use language features newer than it.
>
> Apply `dart-foundation:dart-tooling`: add dependencies with `dart pub add`, never edit `analysis_options.yaml` to silence findings, regenerate with `dart run build_runner build --delete-conflicting-outputs` when `build_runner` is present (never hand-edit `*.g.dart` / `*.freezed.dart`).
>
> Formatting is applied per edited file by the plugin's PostToolUse hook — never run `dart format` repo-wide. `dart analyze` runs after you return via the SubagentStop hook; it must report zero errors and warnings (and zero infos when CI uses `--fatal-infos`).
>
> If superpowers is available, invoke superpowers:verification-before-completion before returning.

For qa phase, inject:
> Apply `dart-foundation:dart-testing`:
> - `package:test` with `group(Type, ...)`, behaviour-sentence names, AAA structure, fresh state in `setUp`.
> - `mocktail` for boundary mocks (repositories, HTTP clients, clocks); stay on `mockito` only if the project already uses it.
> - `await expectLater(...)` for futures, stream matchers (`emitsInOrder`, `emitsError`, `emitsDone`) for streams, `fakeAsync` for timers.
> - Servers: test handlers directly by building a `Request` (shelf) or a `RequestContext` mock (dart_frog) — no real sockets in unit tests.
> - Tag integration tests that need real infrastructure with `@Tags(['integration'])`.
>
> Run: `dart test` (with `--coverage=coverage` when CI collects coverage).

For security phase, inject:
> Check Dart-specific issues in addition to OWASP Top 10:
> - **Command injection**: `Process.run` / `Process.start` with `runInShell: true` or with user input in the executable or arguments.
> - **SQL injection**: string interpolation inside SQL passed to `postgres` / `mysql1` / `sqlite3` — must use parameter binding.
> - **Path traversal**: file paths derived from request URLs or params — must be normalized with `package:path` and confined to a base directory.
> - **TLS**: any `badCertificateCallback` returning `true`, or `HttpClient` / `SecurityContext` with verification disabled.
> - **Secrets**: credentials in source or `--define` values; servers must read them from `Platform.environment` or a secrets manager.
> - **Server hardening**: wildcard CORS with credentials, missing auth middleware on new routes, stack traces or exception messages returned in HTTP responses, unbounded request bodies (no size limit).
> - **Dependencies**: `dart pub outdated` and pub.dev security advisories (`dart pub get` prints them) — flag Critical/High.

## Post-pipeline checks

- dart analyze
- dart test

These are advisory — failures are reported but do not retry.
