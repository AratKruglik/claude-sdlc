---
name: flutter-testing
description: |
  Testing Flutter apps: unit tests for notifiers/blocs/repositories, widget tests with testWidgets/pumpWidget/finders, a shared pumpApp helper with theme/localization/router, Riverpod overrides and ProviderContainer, bloc_test, mocktail for dependencies, accessibility guideline checks, golden tests, integration_test, coverage. Builds on dart-foundation:dart-testing for package:test basics.

  Use this skill to:
  - Test widgets in the same scaffolding they run in (theme, l10n, providers).
  - Test Riverpod providers and Blocs without widgets.
  - Find widgets robustly and pump frames deterministically.
  - Decide when goldens and integration tests are worth it.

  Do NOT use this skill for:
  - Pure Dart unit-test basics (see dart-foundation:dart-testing).
  - Widget implementation (see flutter-conventions).
user-invocable: false
paths: ["test/**", "integration_test/**", "**/*_test.dart"]
---

# Flutter Testing

## Layers

| Layer | Tool | Location | Runs in pipeline |
|---|---|---|---|
| Unit — repositories, mappers, notifiers, blocs | `flutter_test` / `test`, `mocktail`, `bloc_test` | `test/` | yes |
| Widget — one screen or component | `testWidgets` | `test/` | yes |
| Golden — pixel snapshot | `matchesGoldenFile` (or `alchemist` if installed) | `test/` | yes, only if the project already has goldens |
| Integration — whole app on a device | `integration_test` (or `patrol` if installed) | `integration_test/` | no — needs a device/emulator |

Mirror `lib/` paths: `lib/features/orders/presentation/orders_screen.dart` → `test/features/orders/presentation/orders_screen_test.dart`.

## pumpApp helper

Widgets need the real app scaffolding (theme, localization delegates, providers, sometimes a router). Reuse the project's helper (`test/helpers/pump_app.dart`) if it exists; otherwise add one:

```dart
extension PumpApp on WidgetTester {
  Future<void> pumpApp(Widget widget, {List<Override> overrides = const []}) {
    return pumpWidget(
      ProviderScope(                                   // or MultiRepositoryProvider / MultiBlocProvider
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: widget,
        ),
      ),
    );
  }
}
```

## Widget tests

```dart
class _MockOrderRepository extends Mock implements OrderRepository {}

void main() {
  late _MockOrderRepository repository;

  setUp(() => repository = _MockOrderRepository());

  testWidgets('shows orders after loading', (tester) async {
    when(() => repository.fetchOrders()).thenAnswer((_) async => [Order(id: '1', total: 10)]);

    await tester.pumpApp(
      const OrdersScreen(),
      overrides: [orderRepositoryProvider.overrideWithValue(repository)],
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump();                               // let the future complete
    expect(find.byType(OrderTile), findsOneWidget);
  });

  testWidgets('shows retry on failure', (tester) async {
    when(() => repository.fetchOrders()).thenThrow(NetworkException());

    await tester.pumpApp(const OrdersScreen(), overrides: [orderRepositoryProvider.overrideWithValue(repository)]);
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pump();
    verify(() => repository.fetchOrders()).called(2);
  });
}
```

- **Finders**, in order of preference: `find.byType`, `find.text` / `find.widgetWithText`, `find.bySemanticsLabel`, `find.byKey`. Use keys when text is localized or ambiguous.
- **Pumping**: `pump()` advances one frame (resolves completed futures); `pump(duration)` advances time; `pumpAndSettle()` waits for animations to finish — it times out on infinite animations (spinners), so do not use it while a `CircularProgressIndicator` is visible.
- **Interaction**: `tap`, `enterText`, `drag`, `scrollUntilVisible`; always `pump` after.
- Cover loading, empty, error and data states for every new screen, plus the main interaction.
- Do not rely on real `Future.delayed`/timers — inject durations or use `tester.pump(duration)`.
- Network images in widget tests: mock the image provider or use `mocktail_image_network` (if installed); real HTTP fails in tests.

## Riverpod

```dart
test('cart adds items', () {
  final container = ProviderContainer(overrides: [/* fakes */]);
  addTearDown(container.dispose);

  container.read(cartProvider.notifier).add(item);

  expect(container.read(cartProvider), [item]);
});
```

- Riverpod 3 ships `ProviderContainer.test()`, which disposes automatically — use it when available.
- Riverpod 3 retries failing providers by default, so an error-state test can hang or see `AsyncLoading` instead of `AsyncError`. Disable it in tests: `ProviderContainer.test(retry: (_, __) => null)` / `ProviderScope(retry: (_, __) => null, …)` in the `pumpApp` helper.
- For async providers: `await container.read(ordersProvider.future)`.
- Listen to transitions with `container.listen(provider, listener.call, fireImmediately: true)` and a mocktail `Listener` to assert loading → data.

## Bloc / Cubit

```dart
blocTest<OrdersBloc, OrdersState>(
  'emits [loading, loaded] when orders are requested',
  build: () {
    when(() => repository.fetchOrders()).thenAnswer((_) async => orders);
    return OrdersBloc(repository);
  },
  act: (bloc) => bloc.add(const OrdersRequested()),
  expect: () => [const OrdersLoading(), OrdersLoaded(orders)],
);
```

Widget tests for bloc-driven screens: provide a `MockBloc` (`class _MockOrdersBloc extends MockBloc<OrdersEvent, OrdersState> implements OrdersBloc {}`) and `whenListen` / `when(() => bloc.state)` to set state directly.

## Navigation in tests

- go_router: pump `MaterialApp.router(routerConfig: GoRouter(initialLocation: '/orders/1', routes: appRoutes))` to test a deep route; assert on `find.byType(OrderDetailsScreen)`.
- To verify navigation calls, inject a mock `GoRouter` via `InheritedGoRouter` or test the resulting screen — follow the project's existing pattern.
- Test the auth redirect function directly as a pure function where possible.

## Accessibility checks

For new screens:

```dart
final handle = tester.ensureSemantics();
await tester.pumpApp(const CheckoutScreen());
await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
await expectLater(tester, meetsGuideline(textContrastGuideline));
handle.dispose();
```

## Goldens

Only when the project already has golden tests:

- `await expectLater(find.byType(OrderCard), matchesGoldenFile('goldens/order_card.png'));`
- Load real fonts (the project's `flutter_test_config.dart` or `loadAppFonts()` from its helper) or goldens render with the test font.
- Regenerate with `flutter test --update-goldens <file>` and state in the report that goldens were updated — rendering differs across OSes, so CI may need to regenerate them on its platform.

## Integration tests

Only if `integration_test/` exists. Write the flow (`IntegrationTestWidgetsFlutterBinding.ensureInitialized()`, then `testWidgets` driving the real app) but do not run it — it needs a device. List it in the report as "written, not executed".

## Running

```bash
flutter test                                  # all unit + widget tests
flutter test test/features/orders             # one feature
flutter test --coverage                       # coverage/lcov.info
```

Prefix with `fvm` when the project pins its SDK with FVM.
