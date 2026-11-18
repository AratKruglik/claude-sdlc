---
name: swift-tooling
description: |
  Swift project tooling: Package.swift manifests (tools version, platforms, products, targets, dependencies, resources, plugins), dependency constraints and the Package.resolved policy, swift build / test / run, xcodebuild for Xcode projects (schemes, destinations, test plans), Xcode project styles (buildable folders, Tuist, XcodeGen, legacy groups), formatters and linters (swift-format, SwiftFormat, SwiftLint), xcconfig files. Stack-agnostic — referenced by swift-plugin and apple-plugin.

  Use this skill to:
  - Add a dependency or a target the way the project already manages them.
  - Make sure a new file is actually compiled.
  - Run the project's own formatter, linter, build and tests the way CI does.

  Do NOT use this skill for:
  - Language idioms — see swift-foundation:swift-conventions.
  - Testing patterns — see swift-foundation:swift-testing.
user-invocable: false
paths: ["**/Package.swift", "**/Package.resolved", "**/*.xcconfig", "**/Project.swift", "**/Tuist.swift", "**/project.yml", "**/.swiftlint.yml", "**/.swift-format", "**/.swiftformat"]
---

# Swift Tooling

## Which build system

| Marker in the project root | Build system | Build / test |
|---|---|---|
| `Package.swift` only | SwiftPM | `swift build`, `swift test` |
| `*.xcodeproj` / `*.xcworkspace` | Xcode | `xcodebuild` with a scheme and destination |
| `Project.swift` / `Tuist.swift` | Tuist (generates the Xcode project) | `tuist generate`, then `tuist build` / `tuist test` or `xcodebuild` |
| `project.yml` with `targets:` | XcodeGen (generates the Xcode project) | `xcodegen generate`, then `xcodebuild` |

An Xcode app often also has local Swift packages (`Packages/*/Package.swift`) — features or shared modules live there and build with `swift build` on their own only if they do not import UIKit / WatchKit.

When a generator is present, the `.xcodeproj` is a build artefact: edit the manifest (`Project.swift`, `project.yml`), regenerate, never hand-edit the generated project. Check `.gitignore` to see whether the generated project is committed.

## SwiftPM manifests

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Billing",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "Billing", targets: ["Billing"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        .target(name: "Billing", dependencies: [.product(name: "Logging", package: "swift-log")]),
        .testTarget(name: "BillingTests", dependencies: ["Billing"]),
    ]
)
```

- Never lower `swift-tools-version` or `platforms` to make something compile, and never raise them without the BA spec asking — both change who can use the package.
- Version requirements: `from:` (up to next major) by default; `.upToNextMinor(from:)` for pre-1.0 packages; exact versions or `branch:` / `revision:` only with a comment saying why.
- Resources: `resources: [.process("Resources")]`, read with `Bundle.module`.
- Per-target settings: `swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("…"), .defaultIsolation(MainActor.self)]` — copy what sibling targets use.
- New source files under `Sources/<Target>/` are picked up automatically; a new target needs an entry in the manifest.
- Do not add a dependency for a few lines of code. Prefer Apple / swiftlang / swift-server packages and widely used ones.

### Package.resolved policy

- Apps, servers and CLIs: **commit** `Package.resolved` (in `.xcworkspace/xcshareddata/swiftpm/` for Xcode projects).
- Reusable libraries: usually not committed — follow the repo's existing choice.
- Update deliberately: `swift package update <name>`; never in the same change as feature work unless the feature needs it.

## Xcode projects: will my new file compile?

1. **Buildable folders** (Xcode 16+): `project.pbxproj` contains `PBXFileSystemSynchronizedRootGroup`. Files created inside that folder belong to its target automatically — just create them.
2. **Tuist / XcodeGen**: sources are globbed by the manifest (`sources: ["Sources/**"]`). Create the file under the globbed path, then regenerate.
3. **Legacy groups**: every file is listed explicitly. A new file needs a `PBXFileReference`, a `PBXBuildFile`, an entry in its group's `children`, and an entry in the target's `PBXSourcesBuildPhase`. Use unique 24-hex-character IDs, mirror an existing entry exactly, and say in the report that `project.pbxproj` was edited by hand. If the structure is unclear, stop and report it as a BLOCKER rather than guessing — a corrupt `pbxproj` breaks the whole project.

Never reformat or reorder `project.pbxproj`; edit only the lines you add.

## xcodebuild

```bash
xcodebuild -list                                  # schemes, targets, configurations
xcodebuild -scheme App -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme App -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -scheme App -destination 'platform=macOS' build
xcodebuild -scheme App -destination 'generic/platform=watchOS Simulator' build
```

- Use `-workspace App.xcworkspace` when a workspace exists (CocoaPods, multi-project), else `-project`.
- `generic/platform=… Simulator` builds without booting a device — the fastest compile check. Tests need a concrete simulator: list them with `xcrun simctl list devices available` and pick one that exists; never hard-code a device name you have not seen.
- Test plans (`*.xctestplan`): run with `-testPlan Name` when the scheme uses them.
- `-quiet` keeps the output readable; pipe through `xcbeautify` only if the project already does.
- Never pass `CODE_SIGNING_ALLOWED=NO` into committed scripts; it is fine on the command line for a simulator compile check.

## Formatting and linting

Use the tool the project configured — never introduce one:

| Config file | Tool | Format a file | Check |
|---|---|---|---|
| `.swift-format` | swift-format (bundled with the Swift 6 toolchain) | `swift format --in-place File.swift` | `swift format lint --strict -r Sources` |
| `.swiftformat` | SwiftFormat | `swiftformat File.swift` | `swiftformat --lint .` |
| `.swiftlint.yml` | SwiftLint | `swiftlint --fix` (only the rules marked correctable) | `swiftlint lint` |

- The plugin's PostToolUse hook formats each edited file when one of the formatter configs exists — never run a formatter repo-wide.
- Never edit `.swiftlint.yml`, `.swift-format` or `.swiftformat` to make a change pass — the sdlc config-protection hook blocks it during a run. `// swiftlint:disable:next rule_name` only for a genuine false positive, with a reason.
- Build-tool plugins (SwiftLint as an SPM/Xcode plugin) run during the build — a lint error is a build error there.

## Configuration and secrets

- `.xcconfig` files for build settings per configuration; read values through `Info.plist` (`$(API_BASE_URL)`) and `Bundle.main.object(forInfoDictionaryKey:)`.
- Anything in an `.xcconfig`, `Info.plist`, asset or the binary ships with the app and is extractable — never real secrets.
- Servers read configuration from the environment (`Environment.get("DATABASE_URL")` in Vapor, `ProcessInfo.processInfo.environment` elsewhere) and fail fast when a required value is missing.
- `.env` files are never committed; commit `.env.example`.

## Version managers and CI parity

- `.swift-version` (swiftly / swiftenv) or a `swift:6.x` Docker image pins the toolchain for servers — use it.
- `.xcode-version` or the CI workflow's `xcode-select` step names the Xcode version for apps. Do not use APIs from a newer SDK than that Xcode ships, unless guarded with `if #available`.
