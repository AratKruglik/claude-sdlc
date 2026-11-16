---
name: kotlin-conventions
description: |
  Idiomatic Kotlin for JVM projects: null safety without !!, val and read-only collections, data/sealed/value classes, exhaustive when, scope functions (let/apply/also/run/with) used sparingly, extension functions, default and named arguments, Result vs exceptions, collections vs sequences, Java interop annotations, package and file layout, Kotlin coding conventions. Stack-agnostic within Kotlin/JVM.

  Use this skill to:
  - Model domain types with data, sealed and value classes.
  - Handle absence and errors explicitly and exhaustively.
  - Keep code readable — no scope-function chains or clever one-liners.
  - Interoperate with Java libraries without platform-type surprises.

  Do NOT use this skill for:
  - Coroutines and Flow (see kotlin-coroutines).
  - Testing (see kotlin-testing).
  - Gradle/Maven dependency management (see java-foundation:build-tooling).
user-invocable: false
paths: ["**/*.kt"]
---

# Kotlin Conventions

Follow the official Kotlin coding conventions and whatever ktlint/detekt config the project has. Check the Kotlin version in the build before using newer features (`data object` ≥ 1.9, `entries` ≥ 1.9, guard conditions in `when` ≥ 2.1 stable in 2.2, context parameters are experimental).

## Null safety

- Non-null by default; nullable only when absence is a real domain state.
- Handle nulls with `?.`, `?:`, early return, or `let`:

```kotlin
val user = repository.findById(id) ?: throw UserNotFound(id)
val city = user.address?.city ?: "unknown"
```

- `!!` is a crash waiting to happen. Allowed only where a preceding line proves non-null and the compiler cannot see it — and then prefer `checkNotNull(x) { "why" }` / `requireNotNull` for a useful message.
- Java APIs return **platform types** (`String!`). Declare the Kotlin type explicitly at the boundary (`val name: String? = javaObj.getName()`) so a null fails where it enters, not three calls later.
- `lateinit var` only for framework/test injection; never for values that can legitimately be missing.

## Immutability

- `val` over `var`; `var` only in tight local scopes.
- Public APIs expose `List`/`Set`/`Map` (read-only interfaces), never `MutableList`. Build with `buildList { }` / `buildMap { }` or `toList()`.
- `data class` properties are `val`; produce changes with `copy(...)`.

## Modelling types

```kotlin
@JvmInline value class OrderId(val value: UUID)

data class Order(val id: OrderId, val lines: List<OrderLine>, val status: OrderStatus)

sealed interface PaymentResult {
    data class Succeeded(val receiptId: String) : PaymentResult
    data class Declined(val reason: String) : PaymentResult
    data object Timeout : PaymentResult
}

fun describe(r: PaymentResult): String = when (r) {
    is PaymentResult.Succeeded -> "Paid (${r.receiptId})"
    is PaymentResult.Declined -> "Declined: ${r.reason}"
    PaymentResult.Timeout -> "Timed out"
}
```

- `when` over a sealed type or enum is an expression with **no `else` branch**, so adding a subtype breaks the build where it must be handled.
- `value class` for typed IDs and units — zero runtime cost, prevents mixing `UserId` and `OrderId`.
- `enum class` with properties for fixed sets; iterate with `entries` (not `values()`) on 1.9+.
- `object` for stateless singletons only; anything with dependencies is a class injected by constructor.
- Prefer `interface` + constructor injection over `open` classes and inheritance; classes are final by default — keep them that way.

## Functions

- Default and named arguments instead of overloads and builders: `fun search(query: String, limit: Int = 20, includeArchived: Boolean = false)`. Call boolean/same-typed args by name.
- Single-expression functions (`= …`) when the body is one expression and stays readable.
- Extension functions for helpers on types you do not own, placed near their use (`OrderMappers.kt`), not in a global `Utils.kt`.
- Top-level functions are fine; no `XxxUtils` objects.
- Mark visibility deliberately: `internal` for module-private API, `private` for file-private helpers.

## Scope functions

| Function | Use for |
|---|---|
| `let` | null-checked transform: `x?.let { use(it) }` |
| `apply` | configure an object you just created |
| `also` | side effect in a chain (logging) |
| `run` / `with` | rarely — a block that computes a value from one receiver |

Never nest scope functions or chain more than two; name the lambda parameter when `it` is ambiguous. A plain `val` + `if` is often clearer.

## Errors

- Exceptions for unexpected failures and broken invariants: `require(x > 0) { "..." }` for arguments, `check(state)` for state, custom exceptions for domain errors the caller handles.
- Expected business outcomes (declined, not found, conflict) are often clearer as a sealed result type — follow the project. If the project uses Arrow `Either`, use it consistently.
- `runCatching` catches `CancellationException` and `Error`s too — only use it at boundaries, never around suspend calls without rethrowing cancellation (see kotlin-coroutines).
- Use `use { }` for every `Closeable`/`AutoCloseable`.

## Collections

- Standard operators (`map`, `filter`, `associateBy`, `groupBy`, `partition`, `sumOf`) for clarity.
- `asSequence()` only for large collections with several chained steps, or for lazy/infinite sources — not by default.
- `firstOrNull { }` instead of `filter { }.firstOrNull()`; `any { }` instead of `filter { }.isNotEmpty()`.
- `associateBy`/`groupBy` instead of manual map building.

## Strings and formatting

- String templates (`"Order $id has ${lines.size} lines"`), raw strings (`"""…""".trimIndent()`) for multi-line text.
- Never build SQL, shell commands or HTML with templates from user input.

## Layout

- Source in `src/main/kotlin`, tests in `src/test/kotlin`, package path mirrors directories.
- One public class per file named after it; a file of related top-level functions/extensions named for its topic (`OrderMappers.kt`).
- Member order: properties, init blocks, secondary constructors, methods, companion object last.

## Java interop

- Called from Java: `@JvmStatic` on companion functions, `@JvmOverloads` on functions with defaults, `@Throws` for checked exceptions Java callers must catch, `@JvmField` only for constants.
- Calling Java: wrap nullable returns at the boundary; prefer Kotlin stdlib over Guava/Apache Commons equivalents.
