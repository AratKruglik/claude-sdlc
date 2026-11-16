---
name: kotlin-testing
description: |
  Testing Kotlin/JVM code: choosing between JUnit 5 (+ kotlin.test / AssertJ) and Kotest by what the project uses, MockK (mockk, every/coEvery, verify/coVerify, slot, relaxed mocks), coroutine tests with runTest and test dispatchers, Flow tests with Turbine, Ktor testApplication, Testcontainers integration tests, test fixtures and builders, coverage with Kover or JaCoCo.

  Use this skill to:
  - Write tests in the project's framework and style.
  - Mock collaborators (including suspend functions) with MockK.
  - Test coroutines and flows deterministically without real delays.
  - Test Ktor routes in-process.

  Do NOT use this skill for:
  - Java-only test code (see java-foundation:jvm-testing).
  - Production Kotlin idioms (see kotlin-conventions).
user-invocable: false
paths: ["src/test/**", "**/*Test.kt", "**/*Spec.kt"]
---

# Kotlin Testing

## Pick the framework the project uses

| Signal in the build | Framework |
|---|---|
| `io.kotest:kotest-runner-junit5` | Kotest — mirror the spec style in neighbouring tests (`FunSpec`, `StringSpec`, `BehaviorSpec`, `DescribeSpec`) |
| `junit-jupiter` (+ `kotlin("test")`) | JUnit 5 with `kotlin.test` assertions or AssertJ |
| `io.mockk:mockk` | MockK for mocks (default for Kotlin) |
| `mockito-kotlin` only | stay with Mockito — do not introduce MockK alongside it |

Tests live in `src/test/kotlin`, mirroring the main package; file names end in `Test.kt` (JUnit) or `Spec.kt`/`Test.kt` (Kotest, follow neighbours).

## JUnit 5

```kotlin
class CheckoutServiceTest {
    private val repository = mockk<OrderRepository>()
    private val service = CheckoutService(repository)

    @Test
    fun `places an order when the cart is not empty`() = runTest {
        coEvery { repository.save(any()) } just Runs

        val order = service.checkout(cartWith(sku = "A1", quantity = 2))

        assertEquals(1, order.lines.size)
        coVerify(exactly = 1) { repository.save(order) }
    }

    @Test
    fun `rejects an empty cart`() = runTest {
        assertFailsWith<EmptyCartException> { service.checkout(Cart.EMPTY) }
        coVerify(exactly = 0) { repository.save(any()) }
    }
}
```

- Backtick test names as behaviour sentences.
- Fresh instances per test (JUnit creates a new class instance per test by default — keep it that way; avoid `@TestInstance(PER_CLASS)` with mutable state).
- Parameterized: `@ParameterizedTest` + `@CsvSource` / `@MethodSource`.

## Kotest

```kotlin
class CheckoutServiceSpec : FunSpec({
    val repository = mockk<OrderRepository>()
    val service = CheckoutService(repository)

    beforeTest { clearMocks(repository) }

    test("places an order when the cart is not empty") {
        coEvery { repository.save(any()) } just Runs
        service.checkout(cartWith(sku = "A1", quantity = 2)).lines shouldHaveSize 1
    }

    test("rejects an empty cart") {
        shouldThrow<EmptyCartException> { service.checkout(Cart.EMPTY) }
    }
})
```

- Kotest test bodies are already coroutines — call suspend functions directly; use `runTest` only for virtual-time control (or Kotest's `coroutineTestScope = true`).
- Data-driven: `withData(...)`. Property tests (`checkAll`) only if the project already uses them.
- Shared state across tests in a spec body: reset in `beforeTest`, or use `isolationMode = InstancePerTest` if neighbours do.

## MockK

- `every { }` / `coEvery { }` to stub, `verify { }` / `coVerify { }` to check; `returns`, `throws`, `just Runs`, `answers { }`.
- Capture arguments with `slot<Order>()` + `capture(slot)`.
- `relaxed = true` only for collaborators whose calls the test does not care about — never on the thing whose interaction you assert.
- Mock boundaries (repositories, clients, clocks); use real data classes and pure functions.
- `mockkObject`/`mockkStatic` are a smell — inject the dependency instead; if unavoidable, `unmockkAll()` in teardown.

## Coroutines and time

- `runTest { }` (kotlinx-coroutines-test) skips `delay` with virtual time; advance with `advanceTimeBy`, `advanceUntilIdle`.
- Pass the test's dispatcher into the class under test: `CheckoutService(repository, io = StandardTestDispatcher(testScheduler))` — production code takes a `CoroutineDispatcher` parameter for this reason.
- Time-dependent logic takes a `java.time.Clock` (or `kotlinx.datetime.Clock`) — use a fixed clock in tests.
- Flows: Turbine if installed —

```kotlin
service.orderUpdates().test {
    assertEquals(OrderStatus.PENDING, awaitItem().status)
    assertEquals(OrderStatus.PAID, awaitItem().status)
    cancelAndIgnoreRemainingEvents()
}
```

  otherwise `flow.take(n).toList()`.

## Ktor

```kotlin
@Test
fun `GET orders returns 401 without a token`() = testApplication {
    application { module(testDependencies()) }
    val response = client.get("/orders")
    assertEquals(HttpStatusCode.Unauthorized, response.status)
}
```

- In-process, no ports. Override dependencies through the module's parameters or a test Koin module.
- JSON: install `ContentNegotiation` on the test client (`createClient { install(ContentNegotiation) { json() } }`) and assert on decoded DTOs, not raw strings.
- Cover: happy path, validation failure (400), auth failure (401/403), not found (404).

## Integration tests

- Testcontainers (`PostgreSQLContainer`, Kotest `extension(...)` or JUnit `@Testcontainers`) for real databases; run migrations before tests.
- Tag or separate them (`@Tag("integration")`, a dedicated source set or Gradle task) if the project does.

## Builders and fixtures

- Test data via functions with defaults: `fun order(id: OrderId = OrderId(UUID.randomUUID()), lines: List<OrderLine> = listOf(line())) = Order(id, lines, OrderStatus.PENDING)`.
- Shared fixtures in `src/test/kotlin/.../fixtures` or the `testFixtures` source set if configured.

## Running and coverage

```bash
./gradlew test                       # all tests
./gradlew test --tests '*Checkout*'  # filter
./gradlew koverHtmlReport            # Kover, if applied
./gradlew jacocoTestReport           # JaCoCo, if applied
```
