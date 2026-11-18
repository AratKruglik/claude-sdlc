---
name: apple-testing
description: |
  Testing Apple apps: what to unit-test in a SwiftUI app (observable models, services, mappers, reducers), MainActor-isolated tests, SwiftData and Core Data in memory, protocol doubles for system services, TCA TestStore, XCUITest UI tests (launch arguments, accessibility identifiers, page objects), snapshot tests with swift-snapshot-testing, previews as smoke tests, running tests per platform with xcodebuild and test plans, coverage. Builds on swift-foundation:swift-testing for framework basics.

  Use this skill to:
  - Test app logic without launching the UI.
  - Write UI tests that survive layout changes.
  - Run the right scheme and destination for each platform target.

  Do NOT use this skill for:
  - Swift Testing / XCTest basics — see swift-foundation:swift-testing.
  - Server-side Swift tests — see swift-plugin.
user-invocable: false
paths: ["**/*Tests/**", "**/*UITests/**", "**/*.xctestplan", "**/*Tests.swift"]
---

# Testing Apple Apps

## What to test where

| Layer | Test type | Target |
|---|---|---|
| Observable models / view models / TCA reducers | Unit | app unit-test target or feature package tests |
| Services, API clients, mappers, persistence | Unit (with doubles / in-memory stores) | same |
| Critical user journeys (sign-in, checkout) | XCUITest | UI-test target, only if one exists |
| Visual regressions | Snapshot | only if the project already uses snapshots |

Most coverage comes from model tests — they are fast and run on every platform. Views themselves are not unit-tested; their logic belongs in the model.

## Model tests

```swift
import Testing
@testable import Orders

@MainActor
@Suite struct OrdersModelTests {
    @Test func loadShowsOrders() async throws {
        let client = OrdersClientStub(result: .success([.fixture(id: "1")]))
        let model = OrdersModel(client: client)

        await model.load()

        let orders = try #require(model.state.loadedValue)
        #expect(orders.map(\.id) == ["1"])
    }

    @Test func loadFailureShowsError() async {
        let model = OrdersModel(client: OrdersClientStub(result: .failure(URLError(.notConnectedToInternet))))

        await model.load()

        guard case .failed = model.state else {
            Issue.record("expected failed state, got \(model.state)")
            return
        }
    }
}
```

- `loadedValue` is a small test-target extension on the state enum (`if case .loaded(let value) = self { value } else { nil }`) — state holding `any Error` is not `Equatable`, so match the case instead of comparing whole states.
- `@MainActor` on the suite when the model is main-actor isolated (or the target defaults to `MainActor` isolation).
- Await the model's async method directly; for work the model starts internally, expose the task or an async completion hook rather than sleeping.
- Doubles for every system boundary: network client, Keychain wrapper, location / notification / HealthKit services, clock, UUID — behind the protocols the app already uses.

## Persistence in tests

- SwiftData: `let container = try ModelContainer(for: Draft.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))`, then `container.mainContext` (or a model actor) — a fresh container per test.
- Core Data: an `NSPersistentContainer` with an in-memory store description (`url = URL(fileURLWithPath: "/dev/null")`).
- Never touch the real app container or the user's defaults; use `UserDefaults(suiteName: UUID().uuidString)` and remove it after.

## TCA (only if used)

- `let store = TestStore(initialState: Feature.State()) { Feature() } withDependencies: { $0.ordersClient = .mock }`; `await store.send(.onAppear)`, `await store.receive(\.ordersLoaded) { $0.orders = … }`; exhaustivity on unless the project turns it off.

## UI tests (XCUITest)

- Launch with stubbed dependencies: `app.launchArguments = ["-uitesting"]` / `launchEnvironment["API_BASE_URL"] = …`, handled once at app start to swap in fixtures — never hit production from UI tests.
- Query by accessibility identifier (`app.buttons["orders.add"]`), not by visible text that changes with localization.
- Wait with `element.waitForExistence(timeout:)`, never `sleep`.
- One user journey per test; a page-object struct per screen if the suite already uses them.
- Interrupting system alerts (permissions): `addUIInterruptionMonitor` or pre-grant through the simulator; keep the test deterministic.
- UI tests require XCTest; they run on a concrete simulator and are slow — add them only for journeys the BA spec marks critical.

## Snapshot tests (only if present)

- `assertSnapshot(of: view, as: .image(layout: .device(config: .iPhone13)))` with the configurations the suite already uses; cover light / dark and a large Dynamic Type size for new components.
- Recording new references is deliberate: run once in record mode, review the images, commit them, and say so in the report. Snapshots depend on the simulator and OS version the suite pins.

## Previews

- Every new screen's `#Preview` must compile and render its states with stub data — a broken preview is a broken build. Previews are not a substitute for model tests.

## Running

```bash
xcrun simctl list devices available                       # pick a real simulator name / ID
xcodebuild test -scheme App -destination 'platform=iOS Simulator,name=<available iPhone>'
xcodebuild test -scheme App -destination 'platform=iOS Simulator,name=<available iPad>'      # universal apps
xcodebuild test -scheme App -destination 'platform=macOS'
xcodebuild test -scheme WatchApp -destination 'platform=watchOS Simulator,name=<available watch>'
xcodebuild test -scheme App -testPlan UnitTests -only-testing:AppTests/OrdersModelTests
swift test --package-path Packages/Orders                 # host-buildable feature packages
```

- Use `-workspace` when the project has one; Tuist projects can use `tuist test <scheme>`.
- Coverage: enabled in the scheme / test plan (`-enableCodeCoverage YES`); read it with `xcrun xccov view --report <result>.xcresult`.
- Report which scheme, test plan and destination ran, and any target you could not run (no simulator runtime installed).
