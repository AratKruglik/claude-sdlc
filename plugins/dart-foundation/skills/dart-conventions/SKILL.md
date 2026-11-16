---
name: dart-conventions
description: |
  Modern Dart idioms for any Dart project (Dart 3+): sound null safety, records, patterns and switch expressions, sealed/final/base/interface class modifiers, extension types, Future/Stream discipline, immutability, Effective Dart naming, library layout. Apply when the project is a Dart 3 project (pure Dart or Flutter). Stack-agnostic — referenced by every Dart plugin in the marketplace.

  Use this skill to:
  - Write null-safe code without `!` sprinkled over every access.
  - Model closed type hierarchies with sealed classes and exhaustive switch expressions.
  - Return multiple values with records instead of ad-hoc wrapper classes.
  - Write correct async code (no unawaited futures, no leaked stream subscriptions).
  - Lay out a package the way the Dart tooling expects (lib/, lib/src/, bin/, test/).

  Do NOT use this skill for:
  - Flutter widgets, state management or navigation — see flutter-plugin skills.
  - pubspec, lints and code generation — see dart-foundation:dart-tooling.
  - Testing patterns — see dart-foundation:dart-testing.
user-invocable: false
paths: ["**/*.dart"]
---

# Dart Conventions (stack-agnostic, Dart 3+)

Check the SDK constraint in `pubspec.yaml` (`environment: sdk: ^3.x.y`) before using a feature: records, patterns and class modifiers need `>=3.0`, extension types `>=3.3`, null-aware elements `>=3.8`. Never raise the lower bound just to use a feature — flag it in the report instead.

## Null safety

- Types are non-nullable by default. Make a type nullable (`String?`) only when "absent" is a real state of the domain.
- Prefer flow analysis over the `!` operator. Promote with a local variable or a pattern:

```dart
// ❌ two lookups, and a crash if the map changes in between
if (cache[key] != null) return cache[key]!;

// ✅ one lookup, promoted
final cached = cache[key];
if (cached != null) return cached;

// ✅ pattern
if (json case {'id': final int id, 'name': final String name}) {
  return User(id: id, name: name);
}
```

- Fields cannot be promoted unless they are private and final (Dart 3.2+). Copy them into a local first.
- `late` only when initialization is guaranteed before first read (e.g. `initState`, test `setUp`). A `late` field read too early throws `LateInitializationError` at runtime — the compiler cannot help.
- Use `??`, `??=` and `?.` for defaults; never `== null ? x : y` chains.

## Records

Use a record for a small, local, anonymous grouping of values — typically a multi-value return:

```dart
(int count, Duration elapsed) measure(Iterable<Job> jobs) { ... }

final (count, elapsed) = measure(jobs);
```

Name the fields (`({int count, Duration elapsed})`) once there are more than two or the types repeat. When the grouping has behaviour, invariants or crosses a package boundary, make it a class.

## Sealed hierarchies and exhaustive switching

Model "one of N shapes" with a `sealed` class; the compiler then checks every `switch` is exhaustive:

```dart
sealed class PaymentResult {}
final class PaymentSucceeded extends PaymentResult { PaymentSucceeded(this.receiptId); final String receiptId; }
final class PaymentDeclined extends PaymentResult { PaymentDeclined(this.reason); final String reason; }
final class PaymentFailed extends PaymentResult { PaymentFailed(this.error); final Object error; }

String describe(PaymentResult r) => switch (r) {
  PaymentSucceeded(:final receiptId) => 'Paid ($receiptId)',
  PaymentDeclined(:final reason) => 'Declined: $reason',
  PaymentFailed() => 'Something went wrong',
};
```

Never add a `default`/`_` arm to a switch over a sealed type — it silences the exhaustiveness check that catches the next added subtype.

## Class modifiers

| Modifier | Use for |
|---|---|
| `final class` | Value/implementation classes nobody outside the library should extend or implement |
| `sealed class` | Closed hierarchies switched on exhaustively |
| `interface class` | Contracts others implement but must not extend |
| `base class` | Classes that may be extended but whose implementation must be inherited |
| `abstract interface class` | Pure interfaces (ports/repositories) |
| `mixin class` | Only when a type must be usable both as a class and a mixin |

Match what the package already does — do not retrofit modifiers onto public API in an unrelated change (adding `final` to a public class is a breaking change).

## Immutability and value types

- `final` for every field and every local that is not reassigned. `const` constructors whenever all fields are final and the values can be compile-time constants.
- Collections exposed from a class are unmodifiable: `List.unmodifiable(items)` or return `Iterable`.
- Value equality: if the project uses `freezed`, `equatable` or `built_value`, use the same one. Otherwise override `==` and `hashCode` (`Object.hash(a, b)`), never one without the other.
- `copyWith` returns a new instance; it never mutates.

## Async discipline

- Every `Future` is either awaited, returned, or explicitly handed to `unawaited(...)` (from `dart:async`) with a reason. A dropped future swallows its error — `unawaited_futures` / `discarded_futures` lints catch this; keep them on.
- `async` functions return `Future<T>`, never `void` (except top-level event handlers that must match a `void Function()` signature).
- Cancel every `StreamSubscription` you create; close every `StreamController` you own (`await controller.close()` in `dispose`/`close`).
- Prefer `async*`/`yield` and stream transformers over manual controllers for derived streams.
- Use `Future.wait` for independent work, not sequential `await`s in a loop.
- Use `Isolate.run` for CPU-heavy synchronous work (parsing large JSON, image processing) — never block the event loop.
- Catch specific types: `on FormatException catch (e)`. Bare `catch (e)` only at a boundary that logs and rethrows or converts to a domain error. Never `catch (_) {}`.

## Errors

- `Exception` subclasses for recoverable, expected conditions the caller should handle; `Error` subclasses (`ArgumentError`, `StateError`) for programmer mistakes. Do not catch `Error`s.
- Validate public API inputs with `ArgumentError.checkNotNull` / `RangeError.checkValueInInterval` or an explicit `throw ArgumentError.value(...)`.
- Keep the original stack trace when converting: `Error.throwWithStackTrace(DomainError(e), st)`.

## Naming and layout (Effective Dart)

| Kind | Style |
|---|---|
| Types, extensions, typedefs, enums | `UpperCamelCase` |
| Members, variables, parameters, constants | `lowerCamelCase` (no `kPrefix` unless the codebase uses it) |
| Libraries, packages, directories, files | `lowercase_with_underscores` |
| Private | leading `_` — library-private, not class-private |

Package layout:

```
lib/
  my_package.dart        # public API: export only what callers need
  src/                   # implementation, never imported by other packages directly
bin/                     # CLI entry points (dart run my_package:tool)
test/                    # mirrors lib/ — lib/src/foo.dart → test/src/foo_test.dart
```

- Import own-package files with `package:` imports in `lib/`; relative imports only inside `lib/` for files in the same package. Never reach into another package's `src/`.
- One public type per file is the norm; small private helpers may live alongside.
- Order imports: `dart:` → `package:` → relative, each block sorted (`directives_ordering` lint).

## Enums

Enhanced enums (fields, constructors, methods) beat `switch` tables scattered across the codebase:

```dart
enum Plan {
  free(maxProjects: 3),
  pro(maxProjects: 50);

  const Plan({required this.maxProjects});
  final int maxProjects;
}
```

Parse external strings with `Plan.values.byName(raw)` inside a `try` (throws `ArgumentError`) or `Plan.values.asNameMap()[raw]` for a nullable lookup.

## Extension methods and extension types

- Extension methods for small, discoverable helpers on types you do not own. Name the extension; keep it in the feature that needs it.
- Extension types (Dart 3.3+) for zero-cost typed IDs and wrappers: `extension type UserId(String value) {}` — prevents passing an `OrderId` where a `UserId` is expected.

## Things to avoid

- `dynamic` outside JSON decoding boundaries — decode into typed models immediately.
- `as` casts on untrusted data; use patterns (`case {'id': final int id}`) or `is` checks.
- `print` in library code — use `package:logging` or the project's logger (`avoid_print` lint).
- Global mutable state and singletons with hidden dependencies — pass collaborators through constructors.
- `new` keyword and redundant type annotations on initialized locals (`final list = <int>[]`).
