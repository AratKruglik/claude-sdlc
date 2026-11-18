---
stack: apple
priority: 300
aspects: [backend, frontend]
detect:
  any:
    - file_exists: "*.xcodeproj"
    - file_exists: "*.xcworkspace"
    - file_exists: Project.swift
    - file_exists: Tuist.swift
    - file_contains:
        path: project.yml
        pattern: '^targets:'
---

# Apple Platforms Stack Profile

Native Apple app stack provider: iOS, iPadOS, macOS and watchOS apps written in Swift with SwiftUI (and UIKit / AppKit where the project already uses them). Triggers when the project root holds an `.xcodeproj`, an `.xcworkspace`, a Tuist manifest (`Project.swift` / `Tuist.swift`) or an XcodeGen `project.yml`. Priority 300 — the same tier as `flutter-plugin` and `react-native-plugin`.

Claims BOTH `backend` AND `frontend` aspects. An Apple app is one Swift codebase — UI, state, persistence and API clients live in the same targets and local packages — so one agent owns all of it. Claiming `backend` is also what keeps `swift-plugin` (priority 100, `backend`, detects any `Package.swift`) from activating alongside it when the app also has a root `Package.swift`.

Detection is anchored to the project root: the `ios/Runner.xcodeproj` of a Flutter app or the `ios/` folder of a React Native app does not match, so those stacks keep their own architect.

**Monorepo caveat.** When the Xcode project lives in a subdirectory (`ios/`, `apps/ios/`), run the pipeline inside that directory or pass `--stack=apple`. A SwiftPM package that only builds for Apple platforms (imports UIKit, WatchKit or iOS-only SwiftUI APIs) resolves to `swift` by default — pass `--stack=apple` for it too.

## Agents per phase

- business_analysis: business-analyst        # core agent
- development: apple-architect               # ⚡ Apple-specific
- qa: qa-engineer                            # core agent
- security: security-analyst                 # core agent
- documentation: document-writer             # core agent

## Convention skills to apply

- apple-plugin:swiftui-conventions
- apple-plugin:swiftui-state
- apple-plugin:swiftui-navigation
- apple-plugin:ios-ipados
- apple-plugin:macos-app
- apple-plugin:watchos-app
- apple-plugin:apple-testing
- swift-foundation:swift-conventions
- swift-foundation:swift-tooling
- swift-foundation:swift-testing

## Extra phases

(none)

## Phase prompts injection

For development phase, inject:
  "Apple platforms project. Detect before writing anything:
   - Project system: Tuist (`Project.swift` / `Tuist.swift`) or XcodeGen (`project.yml`) → edit the manifest and regenerate, never the generated `.xcodeproj`. Otherwise `project.pbxproj` with `PBXFileSystemSynchronizedRootGroup` → buildable folders, new files compile automatically; without it → legacy groups, a new file needs explicit pbxproj entries (see swift-foundation:swift-tooling) — report every hand edit of `project.pbxproj`.
   - Targets and platforms: `SDKROOT`, `SUPPORTED_PLATFORMS`, `TARGETED_DEVICE_FAMILY` (1 = iPhone, 2 = iPad, 1,2 = universal), `IPHONEOS_DEPLOYMENT_TARGET` / `MACOSX_DEPLOYMENT_TARGET` / `WATCHOS_DEPLOYMENT_TARGET`, Mac Catalyst (`SUPPORTS_MACCATALYST`), extensions (widgets, watch app, share, intents). Only touch the targets the BA spec names. Load the matching platform skill: apple-plugin:ios-ipados, apple-plugin:macos-app, apple-plugin:watchos-app.
   - Swift settings: `SWIFT_VERSION`, `SWIFT_STRICT_CONCURRENCY`, `SWIFT_DEFAULT_ACTOR_ISOLATION`, `SWIFT_APPROACHABLE_CONCURRENCY`. Never change them to make code compile.
   - UI framework: SwiftUI (`@main struct …: App`), UIKit (`UIApplicationDelegate` / `UIScene`), AppKit — or a mix. Follow the framework of the screen you extend; new screens in SwiftUI unless the project is UIKit/AppKit-only.
   - State: Observation (`@Observable` + `@State` / `@Bindable` / `@Environment`), legacy `ObservableObject` (`@StateObject` / `@ObservedObject` / `@Published`), The Composable Architecture (`ComposableArchitecture` import), or another established pattern — never introduce a second one.
   - Persistence: SwiftData (`@Model`, `ModelContainer`), Core Data (`.xcdatamodeld`), GRDB, files, CloudKit. Keychain wrapper for secrets.
   - Navigation: `NavigationStack` with value-based `navigationDestination`, `NavigationSplitView` on iPad / Mac, a router / coordinator object, or UIKit navigation controllers — mirror it.
   - Networking: `URLSession` async APIs behind a client protocol, OpenAPI-generated client (`swift-openapi-generator`), or an installed library — reuse it; never call the network from a `View`.
   - Dependencies: SPM packages in the Xcode project or a Tuist `Package.swift`, local packages under `Packages/`, CocoaPods (`Podfile`) — add new ones the way existing ones are added and only if the BA spec needs it.
   - Localization: `Localizable.xcstrings` (String Catalogs) or `.strings` files → every new user-facing string goes through it (`Text(\"key\")` / `String(localized:)`).
   - Feature layout: mirror the existing structure (feature folders, local packages per feature, MVVM, TCA features) — do not reorganize.
   Build UI from small views; take colors, fonts and spacing from the asset catalog / design system the project uses; support Dynamic Type, Dark Mode and VoiceOver labels on every control; respect safe areas.
   Formatting is applied per edited file by the plugin's PostToolUse hook (only when the project has a formatter config) — never run a formatter repo-wide. Verify your change compiles with `xcodebuild -scheme <scheme> -destination 'generic/platform=<platform> Simulator' build` (or `tuist build`) for every platform target you touched — the pipeline has no compile hook for Xcode projects. SwiftLint runs after you return via the SubagentStop hook when the project uses it.
   Apply skills: apple-plugin:swiftui-conventions, apple-plugin:swiftui-state, apple-plugin:swiftui-navigation, the platform skills for the targets you touch, swift-foundation:swift-conventions, swift-foundation:swift-tooling.
   If superpowers is available, invoke superpowers:verification-before-completion before returning."

For qa phase, inject:
  "Apple platforms testing strategy:
   - Unit tests for view models / observable models, services, reducers and mappers in the app's unit-test target or the feature package's test target: Swift Testing for new tests unless the target is an XCTest suite.
   - Main-actor isolated models: mark the test or suite `@MainActor`. Inject protocol-based doubles for network, persistence, clock and system services (location, notifications, HealthKit).
   - SwiftData: an in-memory `ModelContainer(for:configurations: ModelConfiguration(isStoredInMemoryOnly: true))` per test. Core Data: an in-memory `NSPersistentContainer` (`/dev/null` store URL).
   - TCA (only if used): `TestStore` with exhaustive assertions and overridden dependencies.
   - UI tests (XCUITest) only if a UI-test target exists: launch arguments to stub the backend, query by accessibility identifier, one user journey per test.
   - Snapshot tests only if the project already has them (`swift-snapshot-testing`); record new references deliberately and say so in the report.
   Run: `xcodebuild test -scheme <scheme> -destination 'platform=iOS Simulator,name=<an available simulator>'` (pick one from `xcrun simctl list devices available`), `-destination 'platform=macOS'` for Mac targets, or `swift test` inside a local package that builds on the host.
   Apply skills: apple-plugin:apple-testing, swift-foundation:swift-testing."

For security phase, inject:
  "Apple-specific security checks in addition to OWASP Mobile Top 10:
   - Secrets and tokens: Keychain only, with an appropriate `kSecAttrAccessible` class — never `UserDefaults`, `@AppStorage`, plist files or SwiftData / Core Data in plaintext.
   - Nothing secret in the bundle: `Info.plist`, `.xcconfig` values, asset catalogs and string constants are all extractable from the IPA / app bundle.
   - Transport: App Transport Security stays on — no `NSAllowsArbitraryLoads`; server-trust challenge handlers must evaluate the trust (and pin for sensitive apps), never accept blindly.
   - URL schemes, Universal Links (`apple-app-site-association`), widgets and App Intents parameters, Handoff / NSUserActivity: validate before navigating or acting; sensitive actions require an authenticated session.
   - WKWebView: restrict navigation in `WKNavigationDelegate`, validate `WKScriptMessage` bodies, never inject tokens into JavaScript.
   - Data protection: files with sensitive data written with `.completeFileProtection`; caches excluded from backup where appropriate; `isExcludedFromBackup` for regenerable data.
   - Privacy: every accessed protected resource has its `NS…UsageDescription`; `PrivacyInfo.xcprivacy` declares required-reason APIs and collected data; App Tracking Transparency before any tracking.
   - Entitlements: only what the feature needs; macOS App Sandbox stays enabled for Mac App Store targets, hardened runtime for notarized apps; no `com.apple.security.cs.disable-library-validation` without reason.
   - Logging: no tokens or personal data in `print` / `os.Logger`; no `privacy: .public` on sensitive values.
   - Biometrics: `LAContext` results gate access to Keychain items with `SecAccessControl` (`.biometryCurrentSet`), not a boolean flag in memory.
   - Dependencies: review `Package.resolved` / `Podfile.lock` changes and flag packages with known advisories."

## Pre-phase commands

(none)

## Post-pipeline checks

No `xcodebuild archive`, signing or `tuist generate` here — archives need signing identities and provisioning, and the scheme and destination are project-specific. The architect compiles every touched platform target itself during development.

- [ ! -f .swiftlint.yml ] || swiftlint lint
