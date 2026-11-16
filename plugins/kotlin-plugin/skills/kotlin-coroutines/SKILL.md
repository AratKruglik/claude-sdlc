---
name: kotlin-coroutines
description: |
  Kotlin coroutines on the JVM: suspend functions, structured concurrency (coroutineScope, supervisorScope, application-owned scopes), dispatchers and blocking I/O, cancellation and CancellationException rules, timeouts, async/await parallelism, Flow (cold streams, operators, flowOn, StateFlow/SharedFlow), Ktor request coroutines, bridging callbacks and Java futures, dispatcher injection for tests.

  Use this skill to:
  - Write suspend APIs that are cancellable and do not block threads.
  - Run independent work in parallel without leaking coroutines.
  - Expose streams with Flow correctly.
  - Keep coroutine code testable with injected dispatchers.

  Do NOT use this skill for:
  - General Kotlin idioms (see kotlin-conventions).
  - Testing coroutines (see kotlin-testing — runTest, Turbine).
user-invocable: false
paths: ["**/*.kt"]
---

# Kotlin Coroutines

## Suspend functions

- A function that does I/O or waits is `suspend`. It must be **main-safe**: callers can invoke it from any dispatcher, so it switches context itself when it blocks.

```kotlin
class ReportRepository(private val io: CoroutineDispatcher = Dispatchers.IO) {
    suspend fun load(path: Path): Report = withContext(io) {
        Files.newBufferedReader(path).use { parse(it) }   // blocking JDBC/file/HTTP-client calls live here
    }
}
```

- Inject the dispatcher (constructor parameter with a default) so tests can pass a test dispatcher.
- Do not make a function `suspend` if it never suspends.
- Non-blocking clients (Ktor client, R2DBC, async drivers) need no `withContext(IO)`.

## Structured concurrency

- Every coroutine has an owner scope that outlives it and cancels it:
  - inside a suspend function → `coroutineScope { }` (one failure cancels siblings) or `supervisorScope { }` (children fail independently);
  - in a Ktor handler → the call's coroutine;
  - for app-lifetime background work → a scope the application creates and cancels on shutdown (`CoroutineScope(SupervisorJob() + Dispatchers.Default)` owned by a component with `close()`).
- **Never `GlobalScope`.** Never `runBlocking` except in `main` or tests — inside a server it blocks a request thread and can deadlock.
- Parallel independent calls:

```kotlin
suspend fun dashboard(userId: UserId): Dashboard = coroutineScope {
    val orders = async { orderClient.recent(userId) }
    val profile = async { profileClient.get(userId) }
    Dashboard(orders.await(), profile.await())
}
```

- Bound fan-out over large lists (`Semaphore`, `chunked`, or `flatMapMerge(concurrency = N)`) — never `map { async { } }` over thousands of items.

## Cancellation

- Cancellation is cooperative: long CPU loops call `ensureActive()` / `yield()`.
- **Never swallow `CancellationException`.** A broad catch around suspend calls must rethrow it:

```kotlin
try {
    client.send(event)
} catch (e: CancellationException) {
    throw e
} catch (e: IOException) {
    log.warn("send failed", e)
}
```

- `runCatching { suspendCall() }` swallows cancellation — avoid it around suspend calls, or rethrow `CancellationException` from the failure.
- Cleanup in `finally`; suspending cleanup needs `withContext(NonCancellable) { … }`.
- Timeouts: `withTimeout(5.seconds) { … }` (throws `TimeoutCancellationException`) or `withTimeoutOrNull`.

## Exceptions

- In `coroutineScope`/`async`, exceptions propagate to the caller of `await`/the scope — handle them there.
- `CoroutineExceptionHandler` only on root coroutines of an app-owned scope, for logging; it does not make failures recoverable.
- `launch` for fire-and-forget within a scope; its failures cancel the parent unless under a `SupervisorJob`.

## Flow

- `Flow` is cold: nothing runs until collected. Build with `flow { emit(…) }`, `channelFlow { }` for concurrent producers, `callbackFlow { … awaitClose { unregister() } }` for callback APIs.
- Change upstream context with `flowOn(io)`, never `withContext` inside `flow { }` around `emit`.
- Operators: `map`, `filter`, `onEach`, `catch` (upstream errors only), `retryWhen`, `debounce`, `distinctUntilChanged`, `flatMapLatest`.
- Hot state: `StateFlow` (current value, conflated) via `MutableStateFlow` kept private and exposed as `StateFlow`; events: `SharedFlow`. Convert a cold flow with `stateIn(scope, SharingStarted.WhileSubscribed(5_000), initial)`.
- Ktor server-sent events / WebSockets: collect flows inside the route's coroutine so they cancel with the connection.

## Bridging

- Java `CompletableFuture` → `future.await()` (`kotlinx-coroutines-jdk8`, built into core on recent versions).
- Callback API → `suspendCancellableCoroutine { cont -> … cont.invokeOnCancellation { cancel() } }`.
- Exposing to Java callers → a non-suspend facade returning `CompletableFuture` via `scope.future { }`.

## Ktor specifics

- Route handlers already run in a coroutine — call suspend functions directly; wrap only blocking calls in `withContext(Dispatchers.IO)`.
- Do not launch work that must outlive the request in `call`'s scope; hand it to an application-owned scope or a queue.
