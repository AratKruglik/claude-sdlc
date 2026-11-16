---
name: dart-testing
description: |
  Testing pure Dart code with package:test: file layout, group/test/setUp structure, matchers, async and stream expectations, mocktail mocks and fakes (mockito when the project already uses it), test tags and platforms, coverage. Stack-agnostic — referenced by every Dart plugin in the marketplace. Flutter widget, golden and integration tests live in flutter-plugin:flutter-testing.

  Use this skill to:
  - Write fast, isolated unit tests for Dart classes and functions.
  - Mock collaborators at boundaries without over-mocking.
  - Test Futures, Streams, timers and errors correctly.
  - Run the suite and collect coverage the way CI does.

  Do NOT use this skill for:
  - Widget tests, goldens, integration_test — see flutter-plugin:flutter-testing.
  - Language idioms — see dart-foundation:dart-conventions.
user-invocable: false
paths: ["test/**", "**/*_test.dart"]
---

# Dart Testing (package:test)

## Layout

- Tests live in `test/`, mirroring `lib/`: `lib/src/cart/cart.dart` → `test/src/cart/cart_test.dart`.
- Every test file ends in `_test.dart` and has a `main()`.
- Shared fakes/builders go in `test/helpers/` (or the repo's existing location) — not in `lib/`.
- Pure Dart: `dart test`. Flutter projects run the same tests with `flutter test` (which uses `flutter_test`; its `test`/`expect` API is the same).

## Structure

```dart
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockOrderRepository extends Mock implements OrderRepository {}

void main() {
  group(CheckoutService, () {
    late _MockOrderRepository repository;
    late CheckoutService service;

    setUp(() {
      repository = _MockOrderRepository();
      service = CheckoutService(repository);
    });

    test('places an order when the cart is not empty', () async {
      // Arrange
      when(() => repository.save(any())).thenAnswer((_) async {});
      final cart = Cart(items: [CartItem(sku: 'A1', quantity: 2)]);

      // Act
      final order = await service.checkout(cart);

      // Assert
      expect(order.items, hasLength(1));
      verify(() => repository.save(order)).called(1);
    });

    test('throws EmptyCartException for an empty cart', () {
      expect(() => service.checkout(Cart.empty()), throwsA(isA<EmptyCartException>()));
      verifyNever(() => repository.save(any()));
    });
  });
}
```

- `group` by unit (pass the type itself: `group(CheckoutService, ...)`), test names as behaviour sentences.
- Arrange / Act / Assert, one behaviour per test.
- `setUp` creates fresh state for every test; `tearDown` / `addTearDown` releases resources (close controllers, delete temp dirs). Never share mutable state across tests via top-level variables.

## Mocks and fakes

The default is **mocktail** (no code generation). If the project already uses **mockito** with `@GenerateNiceMocks` + `build_runner`, stay with it — do not mix both.

- Mock only boundaries: repositories, HTTP clients, platform services, clocks. Use real value objects and pure functions.
- `registerFallbackValue(FakeOrder())` in `setUpAll` before using `any()` with a non-primitive type.
- Prefer a hand-written fake (an in-memory repository) when several tests need realistic behaviour; it is clearer than a stack of `when(...)` calls.
- Stub async methods with `thenAnswer((_) async => value)`, never `thenReturn(Future.value(...))`.
- HTTP: `package:http/testing.dart` `MockClient((request) async => Response('{"id":1}', 200))` beats mocking `http.Client` methods by hand.

## Matchers

```dart
expect(total, equals(Money.cents(1999)));
expect(items, containsAll([a, b]));
expect(user, isA<AdminUser>().having((u) => u.permissions, 'permissions', contains(Permission.billing)));
expect(() => parse('x'), throwsA(isA<FormatException>()));
expect(price, closeTo(9.99, 0.001));
```

`isA<T>().having(...)` beats several separate `expect`s on casted fields.

## Async, streams and time

```dart
test('emits loading then data', () {
  expect(
    repository.watchOrders(),
    emitsInOrder([isEmpty, hasLength(1), emitsDone]),
  );
});

test('surfaces errors', () async {
  await expectLater(service.load(), throwsA(isA<NetworkException>()));
});
```

- Always `await` (or return) async expectations — `expectLater` for futures, the stream matcher form for streams. An un-awaited expectation passes vacuously.
- Time-dependent code takes a `Clock` (`package:clock`) or a `DateTime Function()` — never call `DateTime.now()` deep inside logic.
- Timers, debounce, retries: `fakeAsync((async) { ...; async.elapse(const Duration(seconds: 5)); })` from `package:fake_async` — no real `Future.delayed` in tests.

## Tags, platforms, slow tests

- Integration tests that hit a real database or network get a tag: `@Tags(['integration'])` at the top of the file, declared in `dart_test.yaml`; CI may run `dart test -x integration`.
- `@TestOn('vm')` / `@TestOn('browser')` when a test depends on `dart:io` or `dart:html`.
- Real infrastructure (Postgres, Redis) in integration tests: use the repo's docker-compose services; never point tests at shared or production resources.

## Coverage

```bash
dart test --coverage=coverage
dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib
# Flutter: flutter test --coverage  → coverage/lcov.info
```

Exclude generated files (`*.g.dart`, `*.freezed.dart`) from coverage targets. Cover branches and error paths of new code, not trivial getters.

## Anti-patterns

- Testing private members — test through the public API.
- `sleep`/`Future.delayed` to "wait for" async work.
- Asserting on `toString()` output instead of structured fields.
- Mocking the class under test or value types.
- One giant test with many acts and asserts.
