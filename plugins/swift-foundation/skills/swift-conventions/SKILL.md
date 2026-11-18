---
name: swift-conventions
description: |
  Swift language conventions for any Swift codebase: Swift 6 language mode, value types first, optionals without force-unwraps, error handling (throws, typed throws, Result), protocols and generics (some vs any), access control, strict concurrency (async/await, structured tasks, actors, Sendable, @MainActor, default actor isolation and approachable concurrency), memory (ARC, weak/unowned captures), and the Swift API Design Guidelines. Stack-agnostic — referenced by swift-plugin and apple-plugin.

  Use this skill to:
  - Write Swift that compiles cleanly under the project's language mode and concurrency checking.
  - Choose between struct, enum, class and actor.
  - Model failures and absence without crashes.
  - Name APIs the way the rest of the Swift ecosystem does.

  Do NOT use this skill for:
  - Package / build / formatter setup — see swift-foundation:swift-tooling.
  - Tests — see swift-foundation:swift-testing.
  - SwiftUI views and state — see apple-plugin:swiftui-conventions and apple-plugin:swiftui-state.
user-invocable: false
paths: ["**/*.swift"]
---

# Swift Conventions

## Know the language mode first

Read it before writing a line — it decides what compiles:

- SwiftPM: `// swift-tools-version:` on the first line of `Package.swift`, and `swiftLanguageModes:` / per-target `.swiftLanguageMode(.v5)` settings. Tools version 6.0+ defaults to the Swift 6 language mode.
- Xcode: `SWIFT_VERSION` in the target's build settings (`project.pbxproj`, `.xcconfig`, Tuist/XcodeGen manifests).
- Concurrency settings: `SWIFT_STRICT_CONCURRENCY` (minimal / targeted / complete) in Swift 5 mode; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` (Xcode 26+ app templates turn both on); `.defaultIsolation(MainActor.self)` in a SwiftPM 6.2+ target.

Never change the language mode, strict-concurrency level or default isolation to make your code compile. Fix the code. Never use a feature newer than the toolchain the project pins (`.swift-version`, `swift-tools-version`, CI image).

## Types

- **Value types by default.** `struct` for data, `enum` for closed sets of cases (with associated values), `class` only for identity, shared mutable state, or Objective-C / framework subclassing. `final class` unless designed for inheritance.
- `let` over `var`; mutate through methods on a `struct` (`mutating`) rather than exposing settable properties.
- Model states as an `enum` instead of a cluster of optionals and booleans:

```swift
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(any Error)
}
```

- `switch` over your own enums exhaustively — no `default:` that would silently swallow a new case. For framework enums marked non-frozen, use `@unknown default:`.
- Prefer `Codable` structs with `CodingKeys` (or a `JSONDecoder.keyDecodingStrategy` the project already uses) over hand-written dictionary parsing.

## Optionals

- No force unwrap (`!`), `try!` or `as!` in production code. Allowed: `IBOutlet`s in legacy UIKit, and a compile-time-known literal such as `URL(string: "https://example.com")!` — nothing derived from input.
- `guard let x else { return / throw }` for early exits; `if let x` for the happy branch; `??` for a real default, not to hide a bug.
- Never use `fatalError` / `precondition` for conditions caused by input, network or disk — throw instead.

## Errors

- `throws` for recoverable failures. Define domain errors as `enum MyError: Error` with associated values; conform to `LocalizedError` only where a message reaches the user.
- Typed throws (`throws(ParseError)`) only for small, closed, internal APIs where the caller must handle every case — public APIs and anything that calls into other throwing code stay untyped.
- `Result` is for storing or passing an outcome (callbacks, state), not for returning from `async` functions — use `async throws`.
- Never `try?` an operation whose failure matters; at least log it with context.

## Protocols and generics

- Small protocols describing a capability (`protocol UserRepository { func user(id: User.ID) async throws -> User }`) — the seam for tests and for swapping implementations.
- `some Protocol` for parameters and return types when one concrete type flows through; `any Protocol` only when you need heterogeneous storage. Write `any` explicitly — it is required in Swift 6 for existential use.
- Prefer protocol extensions and generic functions over class hierarchies.
- Do not add a protocol with a single implementation and no test double — that is indirection, not design.

## Concurrency

- `async`/`await` for every asynchronous API you write. No new completion-handler APIs; wrap legacy callbacks once with `withCheckedThrowingContinuation` and resume exactly once on every path.
- **Structured concurrency first:** `async let` for a fixed number of parallel calls, `withThrowingTaskGroup` for a dynamic number. Unstructured `Task { }` only at a boundary (a UI event, a lifecycle hook) — and keep the handle if the work must be cancellable. `Task.detached` almost never.
- Respect cancellation in long loops: `try Task.checkCancellation()`.
- **Isolation:**
  - UI state and anything touching UIKit / AppKit / SwiftUI is `@MainActor`.
  - Shared mutable state that is not UI goes in an `actor`. Remember actor reentrancy: re-check state after every `await` inside an actor method.
  - Types that cross isolation domains are `Sendable` — immutable structs/enums get it for free; classes need `final` + immutable stored properties, or must be an actor.
  - `nonisolated` for pure functions on isolated types. With approachable concurrency, `nonisolated async` functions run on the caller's actor; mark a function `@concurrent` when it must run off the caller's actor (CPU-heavy work).
- `@unchecked Sendable`, `nonisolated(unsafe)` and `@preconcurrency import` are escape hatches for code you cannot change (old SDKs, C libraries). Each one needs a comment stating why it is safe. Never use them to silence a warning in code you own.
- No `DispatchQueue` / `DispatchSemaphore` in new code unless you are bridging to an API that requires it. Never block a concurrency thread with a semaphore waiting on async work.

## Memory

- Closures stored by `self` (callbacks, `NotificationCenter` observers, Combine `sink`) capture `[weak self]` and `guard let self else { return }`. `unowned` only when the lifetime relationship is guaranteed and documented.
- `Task { }` started from an object captures `self` strongly until it finishes; cancel long-running tasks in `deinit` or the view's `.task` lifecycle.
- Delegates are `weak var delegate: (any SomeDelegate)?` with a class-constrained protocol (`AnyObject`).

## Access control and layout

- Default to `internal`; `private` for helpers; `public` / `package` only for API another module consumes. `open` only when subclassing from outside is intended.
- One primary type per file, file named after it. Group protocol conformances in `extension Type: Protocol { }` blocks.
- `// MARK: -` sections only where the file already uses them.

## API Design Guidelines (naming)

- Clarity at the point of use: `remove(at: index)`, `user(withID:)`, not `removeElement(index:)`.
- Types and protocols `UpperCamelCase`; everything else `lowerCamelCase`; acronyms uniform case (`userID`, `urlString`, `HTTPClient`).
- Boolean properties read as assertions: `isEmpty`, `hasChanges`, `canSubmit`.
- Mutating/non-mutating pairs: `sort()` / `sorted()`, `formUnion()` / `union()`.
- Factory methods start with `make`. Protocols describing a capability end in `-able` / `-ing`; protocols describing what something is are nouns.
- Document public API with `///` doc comments (summary line, `- Parameter`, `- Returns`, `- Throws`).

## Logging

- `Logger` from `os` (Apple platforms) or `swift-log` (`Logger(label:)`, servers / cross-platform) — whichever the project uses. No `print` in production paths.
- Never log tokens, passwords or personal data. With `os.Logger`, dynamic values are private by default in release logs — keep it that way; mark `privacy: .public` only for non-sensitive values.
