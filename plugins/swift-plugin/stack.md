---
stack: swift
aspects: [backend]
priority: 100
detect:
  any:
    - file_exists: Package.swift
---

# Swift Stack Profile (backend)

Registers any SwiftPM project (`Package.swift` in the project root) with the SDLC pipeline. Covers:
- Swift packages and libraries (Swift Package Index or internal)
- Command-line tools (`swift-argument-parser`, `executableTarget`)
- HTTP servers and APIs: Vapor (+ Fluent), Hummingbird
- Swift on Linux / server-side Swift in Docker

**Apple apps are not handled here.** `apple-plugin` (priority 300) claims both the `backend` and `frontend` aspects whenever the root holds an Xcode project, a workspace, or a Tuist / XcodeGen manifest, so it wins and `swift-plugin` stays inactive for that project.

**SwiftPM-only Apple code.** A package whose code imports UIKit, WatchKit or iOS-only SwiftUI APIs cannot be built with `swift build` on the host. When such a package is the project root, run the pipeline with `--stack=apple`.

## Agents per phase

```yaml
business_analysis: business-analyst         # core agent (aspect-agnostic)
development:
  backend: swift-architect                  # owned by this plugin
qa: qa-engineer                             # core agent
security: security-analyst                  # core agent
documentation: document-writer             # core agent
```

## Convention skills to apply

- swift-foundation:swift-conventions
- swift-foundation:swift-tooling
- swift-foundation:swift-testing

## Phase prompts injection

For development phase (backend aspect), inject:
> You are working on a **SwiftPM** project (no Xcode app project in the root).
> Detect the project shape from `Package.swift` and the tree:
> - `vapor/vapor` dependency → Vapor server: `configure.swift` registers middleware, migrations and routes; controllers conform to `RouteCollection`; request/response types conform to `Content`; persistence through Fluent models + `AsyncMigration` if `fluent` is present.
> - `hummingbird-project/hummingbird` → Hummingbird 2 server: `Application` + `Router`, `RouterController`s, `ResponseCodable` types, middleware groups.
> - `apple/swift-argument-parser` + an `executableTarget` → CLI: one `AsyncParsableCommand` per subcommand, validation in `validate()`, `ExitCode` for failures.
> - Otherwise → library: public API in `Sources/<Target>/`, everything else `internal`.
> - Several `Package.swift` files or a `Packages/` directory → multi-package repo: work inside the target package, then build and test every package that depends on it.
>
> Apply `swift-foundation:swift-conventions`: value types first, no force unwraps / `try!` on input-derived values, `async throws` APIs, `Sendable` types across isolation boundaries, actors for shared mutable state, no `@unchecked Sendable` / `nonisolated(unsafe)` in code you own. Respect `swift-tools-version`, the language mode and `platforms:` — never change them to make code compile.
>
> Apply `swift-foundation:swift-tooling`: add dependencies in `Package.swift` with `from:` requirements, keep `Package.resolved` committed for executables, never edit `.swiftlint.yml` / `.swift-format` / `.swiftformat` to silence findings.
>
> Formatting is applied per edited file by the plugin's PostToolUse hook (only when the project has a formatter config) — never run a formatter repo-wide. `swift build --build-tests` runs after you return via the SubagentStop hook and must succeed with no new warnings.
>
> If superpowers is available, invoke superpowers:verification-before-completion before returning.

For qa phase, inject:
> Apply `swift-foundation:swift-testing`:
> - Swift Testing (`@Test`, `#expect`, `#require`, `arguments:`) for new tests unless the target is an XCTest suite — then follow it.
> - Protocol-based test doubles (stub / spy structs or actors) at the boundaries: repositories, HTTP clients, clocks. No real network in unit tests.
> - Vapor: `try await app.test(.GET, "path") { res async in … }` (`XCTVapor`) or `app.testing().test(…)` (`VaporTesting`, for Swift Testing suites) — whichever the test target already imports — with an in-memory or SQLite test database (`app.databases.use(.sqlite(.memory), as: .sqlite)`) and migrations run in setup.
> - Hummingbird: `app.test(.router) { client in try await client.execute(uri:, method:) }` from `HummingbirdTesting`.
> - CLI: call the command's `run()` with parsed arguments (`try Command.parse([...])`) and assert on injected output, not on process exit.
> - Async code: await directly or inject a clock — never `Task.sleep` to wait.
>
> Run: `swift test` (`--enable-code-coverage` when CI collects coverage).

For security phase, inject:
> Check Swift-specific issues in addition to OWASP Top 10:
> - **SQL injection**: `\(value)` interpolation inside SQLKit `.raw("…")` / `SQLQueryString` without `bind:`, string-built queries for `sqlite3` / PostgresNIO — must use bindings.
> - **Command injection**: `Process` launched through `/bin/sh -c`, or with user input in the executable path or arguments.
> - **Path traversal**: file paths derived from route parameters or query strings — standardize, confine to a base directory, prefer `FileMiddleware` for static files.
> - **AuthN/AuthZ**: new routes inside the same `grouped(…Authenticator(), User.guardMiddleware())` group as their protected neighbours; ownership checks on every resource fetched by ID.
> - **Passwords and tokens**: `Bcrypt` (Vapor) or swift-crypto for hashing, never a plain hash; JWT keys from the environment; tokens compared in constant time.
> - **Server hardening**: wildcard CORS with credentials, error middleware returning internal error details in production, missing request body size limits (`app.routes.defaultMaxBodySize`), TLS verification disabled on outbound `HTTPClient`s.
> - **Secrets**: credentials in source, `Package.swift` or committed `.env` files; configuration read from the environment at startup.
> - **Dependencies**: review `Package.resolved` changes; flag packages with known advisories.

## Post-pipeline checks

- swift build --build-tests
- swift test

These are advisory — failures are reported but do not retry.
