# swift-foundation

Shared Swift foundation skills for the [SDLC Marketplace](../../README.md).

This is a **pure skill library** — no agent, no stack profile. It ships stack-agnostic Swift conventions referenced by every Swift plugin in the marketplace (`swift-plugin`, `apple-plugin`).

## Skills

| Skill | Description |
|---|---|
| `swift-foundation:swift-conventions` | Swift 6 idioms: value types first, optionals without force-unwraps, typed and untyped `throws`, protocols and generics (`some` / `any`), strict concurrency (actors, `Sendable`, `@MainActor`, default isolation, structured tasks), API design guidelines |
| `swift-foundation:swift-tooling` | `Package.swift` manifests, dependency constraints and `Package.resolved`, `swift build` / `swift test` / `swift run`, `xcodebuild` basics, swift-format / SwiftFormat / SwiftLint, Tuist and XcodeGen projects |
| `swift-foundation:swift-testing` | Swift Testing (`@Test`, `#expect`, `#require`, parameterized tests, traits), XCTest for existing suites, async tests, protocol-based test doubles, coverage |

## Dependencies

- [`sdlc`](../sdlc) — core pipeline (auto-pulled on install)

## Installation

This plugin is pulled automatically as a dependency of `swift-plugin` and `apple-plugin`:

```
/plugin install swift-plugin@sdlc-marketplace
# or
/plugin install apple-plugin@sdlc-marketplace
```

To install standalone (if you want Swift skills without a stack provider):

```
/plugin install swift-foundation@sdlc-marketplace
```
