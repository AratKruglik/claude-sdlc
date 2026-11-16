---
name: flutter-state-management
description: |
  State management in Flutter apps: detecting the installed approach and following it — Riverpod 2/3 (Notifier/AsyncNotifier, code-gen @riverpod, ref.watch/read/listen, overrides), Bloc/Cubit (events, sealed states, BlocBuilder/BlocListener/BlocSelector, hydrated_bloc), Provider (ChangeNotifier), and plain ValueNotifier/ChangeNotifier. Modelling loading/empty/error/data states, repository boundaries, side effects, dependency injection.

  Use this skill to:
  - Pick the right primitive inside the library the project already uses.
  - Model async screen state so loading, error and empty are never forgotten.
  - Keep business logic out of widgets and testable without Flutter.
  - Trigger one-off effects (snackbars, navigation) without rebuild bugs.

  Do NOT use this skill for:
  - Ephemeral widget state like text controllers (see flutter-conventions — StatefulWidget).
  - Navigation (see flutter-navigation).
  - Testing notifiers and blocs (see flutter-testing).
user-invocable: false
paths: ["lib/**/*.dart"]
---

# Flutter State Management

## Rule zero: use what is installed

| Signal in pubspec.yaml | Approach |
|---|---|
| `flutter_riverpod` / `hooks_riverpod` | Riverpod; `riverpod_annotation` + `riverpod_generator` → code-gen `@riverpod` style |
| `flutter_bloc` / `bloc` | Bloc or Cubit — mirror which one neighbouring features use |
| `provider` (without Riverpod/Bloc) | `ChangeNotifier` + `ChangeNotifierProvider` |
| `get` | GetX controllers — follow existing patterns, do not expand GetX's service-locator use |
| `mobx` + `flutter_mobx` | Stores with `@observable`/`@action` + code-gen |
| none | `ValueNotifier` / `ChangeNotifier` + `ListenableBuilder`, constructor-injected repositories |

Never add a second library. If the BA spec seems to need one, list it in BLOCKERS.

## Layering (all approaches)

```
Widget  ──watches──▶  Notifier / Bloc / Controller  ──calls──▶  Repository (interface)  ──▶  API client / DB / platform
```

- Widgets render state and forward user intents. No `await api.…` in widgets.
- Notifiers/blocs hold presentation logic and call repositories. They do not import `package:flutter/material.dart` (except `foundation.dart` for `ChangeNotifier`), never take a `BuildContext`.
- Repositories map DTOs to domain models and translate transport errors into domain failures.

## Modelling async state

Every async screen has four states: loading, empty, error, data. Make the type force you to handle them.

Riverpod gives you `AsyncValue<T>`:

```dart
final orders = ref.watch(ordersProvider);
return switch (orders) {
  AsyncData(:final value) when value.isEmpty => const OrdersEmpty(),
  AsyncData(:final value) => OrdersList(orders: value),
  AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(ordersProvider)),
  _ => const Center(child: CircularProgressIndicator.adaptive()),
};
```

Elsewhere, a sealed state:

```dart
sealed class OrdersState { const OrdersState(); }
final class OrdersLoading extends OrdersState { const OrdersLoading(); }
final class OrdersLoaded extends OrdersState { const OrdersLoaded(this.orders); final List<Order> orders; }
final class OrdersFailure extends OrdersState { const OrdersFailure(this.message); final String message; }
```

If the project uses a single state class with a `status` enum (common in Bloc codebases with `copyWith`), follow that instead.

## Riverpod

- Code-gen style when `riverpod_annotation` is present:

```dart
@riverpod
Future<List<Order>> orders(Ref ref) async {
  final repo = ref.watch(orderRepositoryProvider);
  return repo.fetchOrders();
}

@riverpod
class Cart extends _$Cart {
  @override
  List<CartItem> build() => const [];

  void add(CartItem item) => state = [...state, item];
}
```

- Without code-gen: `NotifierProvider` / `AsyncNotifierProvider` (Riverpod 2+). Do not write new `StateNotifierProvider`/`ChangeNotifierProvider` code in a Riverpod 2+ project — they are legacy.
- `ref.watch` in `build` (widgets and providers) to depend; `ref.read` inside callbacks (`onPressed`) to act; `ref.listen` for side effects.
- Narrow rebuilds with `ref.watch(provider.select((s) => s.total))`.
- `autoDispose` (the code-gen default) for screen-scoped state; `keepAlive: true` only for genuinely app-wide state.
- Family/parameterized providers for per-id data: `ref.watch(orderProvider(orderId))`.
- Mutations in an `AsyncNotifier`: set `state = const AsyncLoading()` then `state = await AsyncValue.guard(() => repo.save(...))`.
- Dependencies are providers too — override them in tests and flavors (`ProviderScope(overrides: [...])`).

## Bloc / Cubit

- **Cubit** for simple state with method calls; **Bloc** when events need transformation (debounce, droppable, restartable via `bloc_concurrency`) or an audit trail. Match neighbours.
- Events and states are immutable; states use `equatable`/`freezed` or sealed classes so `BlocBuilder` skips identical emits.
- Never emit after `close()` — guard long operations with `if (isClosed) return;`.
- Provide blocs with `BlocProvider(create: (_) => OrdersBloc(context.read<OrderRepository>())..add(const OrdersRequested()))` at the route/screen level, not app-wide unless truly global.
- UI:
  - `BlocBuilder` / `BlocSelector` to rebuild; `buildWhen` to narrow.
  - `BlocListener` for one-off effects (snackbar, navigation); `listenWhen` to narrow.
  - `BlocConsumer` when both are needed.
  - `context.read<B>().add(...)` in callbacks; never `context.watch` inside callbacks.
- Persist only when the project already uses `hydrated_bloc`.

## Provider / ChangeNotifier

- Call `notifyListeners()` once per logical change, after state is consistent.
- `context.watch<T>()` in build, `context.read<T>()` in callbacks, `context.select<T, R>(...)` to narrow.
- Dispose owned resources in `dispose()`; `ChangeNotifierProvider(create: ...)` disposes for you, `.value` does not.

## Side effects (snackbars, dialogs, navigation)

Never trigger them from `build`. Use the listener primitive of the approach:

- Riverpod: `ref.listen(checkoutProvider, (prev, next) { if (next case AsyncError(:final error)) showError(context, error); });` inside `build` of a `ConsumerWidget` (listen is allowed there; it does not run the effect during build).
- Bloc: `BlocListener`.
- ChangeNotifier: `addListener` in `initState`, removed in `dispose`.

## Dependency injection

- Riverpod: repositories and clients are providers.
- Bloc/Provider: `RepositoryProvider` / `Provider` at the app root, or `get_it` (+ `injectable`) if the project already registers services there.
- Never instantiate a repository or `Dio` inside a widget.

## Forms

- Field values live in `TextEditingController`s (widget state) or in the notifier when validation depends on several fields — follow the project.
- Validate on submit and on field change after first submit; show errors via `InputDecoration.errorText` or `TextFormField.validator`.
- Disable the submit button while a submission is in flight; show progress inside it.
