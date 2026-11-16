---
name: flutter-conventions
description: |
  Flutter project structure and widget conventions: app vs package detection, feature-first vs layer-first layout, widget composition and const discipline, StatelessWidget vs StatefulWidget lifecycle, BuildContext rules, keys, theming with ThemeData/ColorScheme/ThemeExtension, responsive and adaptive layout, accessibility (Semantics, text scaling, tap targets), localization with gen-l10n, assets and fonts, flavors, platform channels, secure storage, performance.

  Use this skill to:
  - Build screens from small, const, testable widgets.
  - Manage widget lifecycle (controllers, subscriptions, animations) without leaks.
  - Read styling from the theme and keep screens responsive and accessible.
  - Add strings, assets, permissions and platform code the way the project already does.

  Do NOT use this skill for:
  - State management choice and patterns (see flutter-state-management).
  - Routing and deep links (see flutter-navigation).
  - Testing (see flutter-testing).
  - Plain Dart idioms (see dart-foundation:dart-conventions).
user-invocable: false
paths: ["lib/**/*.dart", "**/pubspec.yaml", "**/l10n.yaml", "**/*.arb"]
---

# Flutter Conventions

## Project layout

Mirror what exists. The two common shapes:

```
lib/                                 lib/
  app/ (App widget, router, theme)     models/
  features/                            repositories/
    orders/                            services/
      data/  (dto, api, repository)    screens/
      domain/ (entities, interfaces)   widgets/
      presentation/ (screens, widgets, providers|bloc)
  l10n/                                main.dart
  main.dart
```

- `lib/main.dart` only bootstraps: `WidgetsFlutterBinding.ensureInitialized()`, DI/setup, `runApp(const App())`. Flavors use `main_<flavor>.dart` files calling a shared `bootstrap()`.
- One public widget per file; file name = snake_case of the widget (`order_list_tile.dart`).
- Private helper widgets (`_Header`) may live in the screen file when they are not reused.

## Widget composition

- Split by **reason to rebuild**, not by line count. A part that rebuilds on its own state becomes its own widget — extracting widgets (not helper methods returning widgets) lets Flutter skip rebuilds and lets tests target them.
- `const` constructors everywhere they are possible, and `const` at call sites (`prefer_const_constructors` lint). A `const` subtree is never rebuilt.
- Take the narrowest inputs: pass `Order order` or `String title`, not the whole state object.
- Use `super.key` in constructors: `const OrderTile({super.key, required this.order});`.
- Keep `build` pure and cheap: no I/O, no allocation of controllers, no heavy computation. Precompute in state/notifiers.

## StatelessWidget vs StatefulWidget

- Stateless by default. Stateful only for ephemeral UI state the state layer should not know about: `TextEditingController`, `AnimationController`, `ScrollController`, `FocusNode`, a local toggle.
- Create controllers in `initState`, release them in `dispose` (every `controller.dispose()`, `subscription.cancel()`). Use `SingleTickerProviderStateMixin` / `TickerProviderStateMixin` for animations.
- React to new widget inputs in `didUpdateWidget`, not by recreating state.
- If the project uses `flutter_hooks`, `useTextEditingController()` etc. replace the boilerplate — follow the neighbours.

## BuildContext rules

- After any `await`, check `if (!context.mounted) return;` (in a `State`: `if (!mounted) return;`) before using `context` — navigation, `ScaffoldMessenger`, `Theme.of`.
- Do not store a `BuildContext` in fields or pass it to repositories/services.
- `Theme.of`, `MediaQuery.sizeOf(context)`, `AppLocalizations.of(context)` are cheap lookups — call them in `build`, not in `initState` (use `didChangeDependencies` if needed outside build).
- Prefer the narrow `MediaQuery.sizeOf` / `paddingOf` / `textScalerOf` over `MediaQuery.of(context)` — they rebuild only when that aspect changes.

## Keys

- `ValueKey(item.id)` on items of lists that can reorder, insert or delete — otherwise state attaches to the wrong row.
- `Key('checkout_submit_button')` (or a `Keys` constants class if the project has one) on widgets tests must find unambiguously.
- `GlobalKey` only for `Form` validation or truly cross-tree access; never as a substitute for state management.

## Lists and scrolling

- `ListView.builder` / `ListView.separated` / `SliverList.builder` for dynamic or long lists — never `ListView(children: items.map(...).toList())` for unbounded data.
- `CustomScrollView` + slivers when a screen mixes headers, grids and lists.
- Pagination: trigger the next page from the state layer when the builder reaches the last items; show a loading row, not a full-screen spinner.

## Theming

- Colors from `Theme.of(context).colorScheme` (`primary`, `onSurface`, `error`, `surfaceContainer…`), text from `Theme.of(context).textTheme` (`titleMedium`, `bodySmall`). No `Color(0xFF…)` literals and no `TextStyle(fontSize: …)` in feature code.
- Project-specific tokens (spacing, brand colors) belong in a `ThemeExtension<T>` read via `Theme.of(context).extension<AppSpacing>()!`, or the project's existing tokens file.
- Material 3 is the default (`useMaterial3: true`); match the project if it still uses Material 2. Support dark mode whenever the app defines `darkTheme`.
- Cupertino/adaptive widgets (`Switch.adaptive`, `CircularProgressIndicator.adaptive`) when the app targets iOS and already uses them.

## Responsive and adaptive layout

- Use `LayoutBuilder` / `MediaQuery.sizeOf(context).width` breakpoints the project defines; no fixed pixel widths for containers.
- `SafeArea` on screen bodies that are not inside a `Scaffold` handling insets; keyboard: `Scaffold.resizeToAvoidBottomInset` stays default unless there is a reason.
- Text must survive 200% text scaling: no fixed-height boxes around text, use `Flexible`/`Expanded` and `overflow: TextOverflow.ellipsis` where truncation is acceptable.
- Desktop/web targets: hover and focus states, keyboard shortcuts (`Shortcuts`/`Actions`) for primary actions, no mobile-only gestures as the only path.

## Accessibility

- Every icon-only control has a label: `IconButton(tooltip: l10n.deleteOrder, …)` or `Semantics(label: …)`.
- Tap targets ≥ 48×48 dp (`kMinInteractiveDimension`).
- Do not convey state by color alone; pair with an icon or text.
- Decorative images: `excludeFromSemantics: true`; meaningful ones: `semanticLabel`.
- Group related content with `MergeSemantics`; announce async results with `SemanticsService.announce` only when nothing visible changes focus.

## Localization (gen-l10n)

When `l10n.yaml` exists:

1. Add the key to the template ARB (`lib/l10n/app_en.arb`) with an `@key` description, and to every other ARB file (translate if obvious, else copy the English text and list it in the report as needing translation).
2. Placeholders and plurals use ICU syntax: `"itemsInCart": "{count, plural, =0{Cart is empty} =1{1 item} other{{count} items}}"`.
3. Regenerate (`flutter gen-l10n`, or `flutter pub get` when `generate: true`) and read with `AppLocalizations.of(context)!.itemsInCart(count)` (or the project's `context.l10n` extension).

Never concatenate translated fragments; never format dates/numbers by hand — use `intl` `DateFormat` / `NumberFormat` with the current locale.

## Assets and fonts

- Declare assets in `pubspec.yaml` under `flutter: assets:` (directory entries end with `/`). Provide `2.0x/` and `3.0x/` variants for raster images, or prefer SVG via `flutter_svg` if the project uses it.
- If the project uses `flutter_gen`, reference assets via the generated `Assets.images.logo` instead of string paths.
- Custom fonts under `flutter: fonts:`; reference through the theme's `fontFamily`, not per widget.

## Platform integration

- Prefer an existing plugin from pub.dev (verified publisher, supports the project's targets) over writing a platform channel.
- Platform channels: one `MethodChannel('com.company.app/feature')` per feature, wrapped in a Dart class behind an interface so it can be faked in tests; validate arguments on the native side; handle `MissingPluginException` on targets that lack the implementation.
- Guard platform-specific code with `defaultTargetPlatform` / `kIsWeb` (never `Platform.isIOS` on web — `dart:io` is unavailable there).
- Permissions: add only what the feature needs to `AndroidManifest.xml` and `Info.plist` (with a user-facing `NS…UsageDescription`); request at the moment of use with `permission_handler` (if installed) and handle "permanently denied".

## Storage

| Data | Store |
|---|---|
| Tokens, refresh tokens, credentials | `flutter_secure_storage` (Keychain / EncryptedSharedPreferences) |
| Small non-sensitive preferences | `shared_preferences` (`SharedPreferencesAsync` / `SharedPreferencesWithCache` on recent versions) |
| Structured local data / offline cache | the installed DB: `drift`, `isar`, `hive`, `sqflite` |
| Files | `path_provider` directories — `getApplicationSupportDirectory` for app data, never the documents dir for caches |

## Performance

- Avoid `Opacity`/`ClipRRect` animations over large subtrees — use `FadeTransition`, `AnimatedOpacity`, or pre-clipped images.
- `RepaintBoundary` around independently animating regions only when profiling shows a need.
- Cache network images (`cached_network_image` if installed) and size them (`cacheWidth`/`cacheHeight`) to the displayed size.
- Heavy work (JSON parsing of large payloads, image processing) via `compute`/`Isolate.run`.
- Never rebuild an entire screen for a single field change — scope listeners (`select`, `BlocSelector`, `context.select`).
