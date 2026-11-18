---
name: swift-testing
description: |
  Testing Swift code: Swift Testing (@Suite, @Test, #expect, #require, parameterized arguments, traits, tags, confirmation for events), XCTest for existing suites (XCTAssert*, setUp/tearDown, expectations), async and actor-isolated tests, protocol-based test doubles, deterministic time and randomness, swift test / xcodebuild test, coverage. Stack-agnostic — referenced by swift-plugin and apple-plugin.

  Use this skill to:
  - Pick the framework the project already uses for the target you test.
  - Write focused, deterministic tests for logic, async code and actors.
  - Replace network, disk and clock dependencies with test doubles.

  Do NOT use this skill for:
  - SwiftUI previews, UI tests and snapshot tests — see apple-plugin:apple-testing.
  - Server HTTP-level tests — the swift-plugin stack prompt covers Vapor / Hummingbird testing helpers.
user-invocable: false
paths: ["**/Tests/**", "**/*Tests.swift", "**/*Test.swift"]
---

# Swift Testing

## Which framework

- A test target whose files `import Testing` → **Swift Testing**. New test files in that target use it too.
- Files that `import XCTest` → **XCTest**. Add new tests in the same style as the target; do not convert existing suites.
- A brand-new test target on a Swift 6 toolchain → Swift Testing.
- UI tests (`XCUIApplication`) and performance tests (`measure`) still require XCTest.
- Both frameworks can live in one target; never mix them inside one type.

## Swift Testing

```swift
import Testing
@testable import Billing

@Suite("Invoice totals")
struct InvoiceTotalTests {
    let calculator = InvoiceCalculator(taxRate: 0.2)

    @Test("adds tax to the subtotal")
    func addsTax() {
        let total = calculator.total(for: [LineItem(price: 100, quantity: 2)])
        #expect(total == 240)
    }

    @Test(arguments: [0, -1])
    func rejectsNonPositiveQuantity(_ quantity: Int) {
        #expect(throws: InvoiceError.invalidQuantity) {
            try calculator.validate(LineItem(price: 10, quantity: quantity))
        }
    }

    @Test func parsesStoredInvoice() throws {
        let invoice = try #require(Invoice(json: Fixtures.invoiceJSON))
        #expect(invoice.lines.count == 3)
    }
}
```

- A `struct` suite gets a fresh instance per test — put setup in `init()` (it may be `async throws`), teardown in `deinit` only when the suite is a `class` / `actor`.
- `#expect` for checks that should continue; `#require` when the rest of the test cannot run without the value (it unwraps optionals and stops on failure).
- `#expect(throws: SomeError.self)` or a specific error value; `#expect(throws: Never.self)` to assert no error.
- Parameterized tests with `arguments:` instead of loops — each argument is reported separately. Two collections → all combinations; `zip(a, b)` for pairs.
- Traits: `.tags(.network)`, `.disabled("reason")`, `.enabled(if:)`, `.timeLimit(.minutes(1))`, `.serialized` for suites that share external state, `.bug("URL")` to link an issue.
- Events and callbacks: `await confirmation("delegate called", expectedCount: 1) { confirm in … }`.
- Known failures: `withKnownIssue { … }`, not a disabled test with no reason.

## XCTest (existing suites)

```swift
final class InvoiceTotalTests: XCTestCase {
    private var calculator: InvoiceCalculator!

    override func setUp() {
        super.setUp()
        calculator = InvoiceCalculator(taxRate: 0.2)
    }

    func test_total_addsTaxToSubtotal() {
        XCTAssertEqual(calculator.total(for: [LineItem(price: 100, quantity: 2)]), 240)
    }

    func test_load_returnsUser() async throws {
        let user = try await sut.load(id: "42")
        XCTAssertEqual(user.name, "Ada")
    }
}
```

- `async throws` test methods instead of `XCTestExpectation` for async code; expectations only for delegate/notification callbacks (`await fulfillment(of: [exp], timeout: 1)`).
- Implicitly unwrapped properties are the XCTest idiom for state built in `setUp`; reset them in `tearDown` if they hold resources.
- `XCTUnwrap` instead of force-unwrapping in tests.

## Async, actors and MainActor

- Mark the test (or the whole suite) `@MainActor` when the subject is main-actor isolated — do not hop with `MainActor.run` inside each test.
- Test actor state through its async API: `#expect(await counter.value == 3)`.
- Never `sleep` / `Task.sleep` to wait for a result. Inject a clock (`any Clock<Duration>`; `ContinuousClock` in production, a test clock or `ImmediateClock` in tests) or await the operation directly.
- Inject randomness, UUID generation and `Date.now` the same way when results depend on them.

## Test doubles

- Depend on a protocol at the seam (`protocol PaymentGateway: Sendable`), then hand-write a stub or spy in the test target:

```swift
final class PaymentGatewaySpy: PaymentGateway, @unchecked Sendable {
    // Test-only spy: mutated from one test at a time.
    private(set) var charges: [Decimal] = []
    var result: Result<Receipt, PaymentError> = .success(.fixture)

    func charge(_ amount: Decimal) async throws -> Receipt {
        charges.append(amount)
        return try result.get()
    }
}
```

- Prefer an `actor` spy when the subject calls it concurrently.
- Network: a `URLProtocol` subclass registered on a `URLSessionConfiguration.ephemeral` session, or a protocol around the HTTP client — never real network calls in unit tests.
- Persistence: in-memory stores (`ModelConfiguration(isStoredInMemoryOnly: true)` for SwiftData, an in-memory GRDB `DatabaseQueue()`, a temporary directory for files).
- Mocking libraries only if the project already uses one.

## Naming and structure

- One behaviour per test; name it as a sentence (Swift Testing display name, or `test_<unit>_<behaviour>` in XCTest).
- Arrange / act / assert, separated by a blank line.
- Fixtures as `static let fixture` / `static func fixture(…)` extensions in the test target, never in production code.

## Running

```bash
swift test                                   # SwiftPM, all tests
swift test --filter InvoiceTotalTests        # one suite
swift test --enable-code-coverage            # coverage (swift test --show-codecov-path)
xcodebuild test -scheme App -destination 'platform=iOS Simulator,name=<an available simulator>'
xcodebuild test -scheme App -only-testing:AppTests/InvoiceTotalTests
```

`swift test --no-parallel` only when a suite cannot be fixed to run in parallel — prefer `.serialized` on that suite.
