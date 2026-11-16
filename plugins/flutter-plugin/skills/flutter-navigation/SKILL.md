---
name: flutter-navigation
description: |
  Navigation in Flutter apps: detecting go_router / auto_route / Navigator, adding routes and nested navigation (ShellRoute / StatefulShellRoute for tab bars), typed routes with go_router_builder, path and query parameters, auth redirects and guards, deep links / Android App Links / iOS Universal Links, passing data between screens, returning results, web URL strategy.

  Use this skill to:
  - Register a new screen in the router the project already uses.
  - Pass parameters safely and validate deep-link input.
  - Protect routes behind authentication with redirects.
  - Keep tab state with stateful shell routes.

  Do NOT use this skill for:
  - Widget structure (see flutter-conventions).
  - State that drives navigation decisions (see flutter-state-management).
  - Testing routes (see flutter-testing).
user-invocable: false
paths: ["lib/**/*.dart", "**/AndroidManifest.xml", "**/Info.plist", "**/*.entitlements"]
---

# Flutter Navigation

## Detect the router

| Signal | Router |
|---|---|
| `go_router` (+ `go_router_builder` → typed `@TypedGoRoute`) | go_router — the Flutter team's package, most common |
| `auto_route` (+ `auto_route_generator`) | auto_route — `@RoutePage()` + generated `AppRouter` |
| neither, `MaterialApp(routes:` / `onGenerateRoute:` | Navigator 1.0 named or anonymous routes |
| `MaterialApp.router` with a custom `RouterDelegate` | hand-rolled Router API — follow it carefully |

Find the router definition (`GoRouter(` / `class AppRouter` / `routes:`) and add new routes next to related ones. Never introduce a second router.

## go_router

```dart
final router = GoRouter(
  initialLocation: '/orders',
  refreshListenable: authNotifier,              // re-run redirect when auth changes
  redirect: (context, state) {
    final loggedIn = authNotifier.isLoggedIn;
    final loggingIn = state.matchedLocation == '/login';
    if (!loggedIn) return loggingIn ? null : '/login?from=${Uri.encodeComponent(state.uri.toString())}';
    if (loggingIn) return '/orders';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => HomeShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/orders',
            builder: (_, __) => const OrdersScreen(),
            routes: [
              GoRoute(
                path: ':orderId',                 // → /orders/42
                builder: (_, state) => OrderDetailsScreen(orderId: state.pathParameters['orderId']!),
              ),
            ],
          ),
        ]),
        StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen())]),
      ],
    ),
  ],
);
```

- `context.go('/orders/42')` replaces the stack to match the URL (use for tab switches, deep links, post-login). `context.push('/orders/42')` pushes on top (use for drill-down where back should return). Follow how neighbours navigate.
- Use `name:` + `context.goNamed('order', pathParameters: {'orderId': id})` if the project names routes.
- **Typed routes** (`go_router_builder`): define `@TypedGoRoute<OrderRoute>(path: '/orders/:orderId') class OrderRoute extends GoRouteData { … }`, regenerate, navigate with `OrderRoute(orderId: id).go(context)`. Never mix string paths into a typed-route codebase.
- Pass IDs in the path/query, not objects via `extra` — `extra` is lost on web refresh and deep links. Load the object from the state layer by ID.
- Return a result: `final picked = await context.push<Address>('/addresses/pick');` and `context.pop(address)` in the picked screen.
- `StatefulShellRoute.indexedStack` keeps each tab's stack alive; switch tabs with `shell.goBranch(index, initialLocation: index == shell.currentIndex)`.
- 404: provide `errorBuilder` (or `onException`) showing a not-found screen with a way home.

## auto_route

- Annotate the screen with `@RoutePage()`, add `AutoRoute(page: OrderDetailsRoute.page, path: '/orders/:orderId')` to the router's `routes`, regenerate with build_runner.
- Navigate with generated route objects: `context.router.push(OrderDetailsRoute(orderId: id))`.
- Guards: implement `AutoRouteGuard.onNavigation` and attach via `guards: [...]`.

## Navigator 1.0

- Named routes: add to `routes:` / `onGenerateRoute` and navigate with `Navigator.of(context).pushNamed('/orders/details', arguments: OrderDetailsArgs(id))`; parse `settings.arguments` with a type check.
- Anonymous: `Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderDetailsScreen(orderId: id)))`.
- Do not migrate an existing app to go_router as part of a feature.

## Auth and guards

- Authorization is decided in **one** place — the router `redirect` / guard — not by each screen hiding itself.
- The redirect reads auth state synchronously from a `Listenable` (Riverpod: a provider exposed as a `Listenable`, Bloc: a stream wrapped in a `ChangeNotifier`) and the router has `refreshListenable` so logout immediately leaves protected routes.
- After login, return to the originally requested location (`from` query param) only if it is a relative path inside the app — never redirect to an arbitrary URL from a query parameter.

## Deep links

Inbound links are untrusted input.

- go_router handles deep links automatically once the platform is configured; `state.pathParameters` / `state.uri.queryParameters` must be validated (format, length, allowed values) before use.
- Android App Links: `intent-filter` with `android:autoVerify="true"`, `https` scheme and the host in `AndroidManifest.xml`; `/.well-known/assetlinks.json` on the domain with the release signing certificate fingerprint.
- iOS Universal Links: `applinks:your.domain` in `Runner.entitlements` (Associated Domains); `/.well-known/apple-app-site-association` on the domain.
- Custom schemes (`myapp://`) are claimable by any app — never carry auth codes or tokens on them; prefer verified https links.
- Flutter's built-in deep-link handling can be toggled with `flutter_deeplinking_enabled` in the manifest/Info.plist; if the project uses `app_links`/`uni_links` manually instead, follow that path.
- List every native file you change (manifest, entitlements, plist) in the report.

## Web

- `usePathUrlStrategy()` (from `flutter_web_plugins`) before `runApp` if the project wants clean URLs instead of `#/`; the hosting must then rewrite all paths to `index.html`.
- Every screen reachable by URL must be reconstructible from the URL alone — another reason to pass IDs, not objects.

## Back behaviour

- `PopScope(canPop: false, onPopInvokedWithResult: (didPop, _) { … })` to confirm discarding unsaved changes (replaces deprecated `WillPopScope`).
- Do not block the system back gesture without a visible reason.
