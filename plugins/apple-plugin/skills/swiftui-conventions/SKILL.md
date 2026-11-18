---
name: swiftui-conventions
description: |
  SwiftUI conventions for Apple apps: app and scene structure, view composition and identity, modifiers and custom ViewModifiers, layout (stacks, Grid, ViewThatFits, Layout), lists and lazy containers, async work with .task, environment values (@Entry), design-system tokens from the asset catalog, Dynamic Type, Dark Mode, accessibility, String Catalog localization, #Preview, UIKit / AppKit interop, performance. Platform specifics live in ios-ipados, macos-app and watchos-app.

  Use this skill to:
  - Build screens out of small, previewable views that match the rest of the app.
  - Keep side effects out of view bodies.
  - Make every new screen accessible, localized and theme-aware.
  - Bridge to UIKit / AppKit only where SwiftUI cannot do the job.

  Do NOT use this skill for:
  - Where state lives and how it flows — see apple-plugin:swiftui-state.
  - Navigation, deep links, sheets — see apple-plugin:swiftui-navigation.
  - Tests and previews as tests — see apple-plugin:apple-testing.
user-invocable: false
paths: ["**/*.swift"]
---

# SwiftUI Conventions

## App and scene structure

```swift
@main
struct OrdersApp: App {
    @State private var session = SessionModel()
    let container: ModelContainer = .shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
        .modelContainer(container)
    }
}
```

- Long-lived services and app-wide models are created once at the app (or scene) level and injected through the environment — never created inside a view's `body`.
- A UIKit-lifecycle app (`AppDelegate` / `SceneDelegate`) hosts SwiftUI screens through `UIHostingController`; keep the lifecycle it has.

## Views

- One screen = one file; extract subviews as soon as a `body` stops fitting on a screen or a piece repeats. Prefer small `struct` views over computed `some View` properties or `@ViewBuilder` functions for anything with its own state or reuse.
- Views are cheap descriptions — `body` must be pure and fast: no I/O, no formatting of large collections, no object creation that should outlive the render.
- Pass views only the data they need (a value or a `@Bindable` model), not the whole app state.
- Stable identity: `ForEach` over `Identifiable` models or with `id:` on a real identifier — never `\.self` on mutable values or array indices for data that can be reordered. Avoid `AnyView`; branch with `if` / `switch` inside a `@ViewBuilder` instead.
- Custom styling that repeats becomes a `ViewModifier` + `View` extension, or a `ButtonStyle` / `LabelStyle` — follow what the design system already defines.

## Async work

- Start work tied to a view's lifetime in `.task { await model.load() }` (cancelled automatically when the view disappears) or `.task(id: query) { … }` to restart when an input changes. Not `onAppear { Task { … } }`.
- User actions call into the model: `Button("Save") { Task { await model.save() } }` — or a synchronous model method that manages its own task when the project does that.
- Pull to refresh: `.refreshable { await model.reload() }`.
- Every screen renders loading, content, empty (`ContentUnavailableView`) and error states.

## Layout

- `VStack` / `HStack` / `ZStack` with explicit `spacing` from the design tokens; `Grid` for aligned rows; `LazyVStack` / `LazyVGrid` inside `ScrollView` for long content; `List` for system-styled lists with swipe actions and selection.
- `ViewThatFits` and size classes for adaptive layouts — avoid `GeometryReader` unless you need the actual size, and never put it at the root of a scrolling container.
- Respect safe areas; use `.safeAreaInset` / `.safeAreaPadding` for bars instead of manual offsets.
- No fixed frames for text containers — text must grow with Dynamic Type.

## Visual design

- Colors from the asset catalog (`Color("Brand")` or generated symbols `Color.brand`) or semantic system colors (`.primary`, `.secondary`, `Color(.systemBackground)`), fonts from text styles (`.font(.headline)`) or the design system's scaled custom fonts. No hex literals in feature code.
- SF Symbols via `Image(systemName:)` / `Label`; check symbol availability against the deployment target.
- Follow the system look of the SDK the project builds with (Liquid Glass materials from the 26-series SDKs on): standard controls, toolbars and tab bars adopt it automatically — do not paint opaque custom backgrounds behind system bars, and use `.glassEffect` / `GlassEffectContainer` for custom floating controls only when the deployment target allows it (`if #available`).
- Dark Mode and increased contrast must work: check new screens in both appearances via previews.

## Accessibility

- Every interactive element has a meaningful label: `Label`, `Button("Title")`, or `.accessibilityLabel(...)` for icon-only buttons. Decorative images: `Image(decorative:)` or `.accessibilityHidden(true)`.
- Group related content with `.accessibilityElement(children: .combine)`; expose custom actions with `.accessibilityAction`.
- `.accessibilityIdentifier("orders.list.row")` on elements UI tests need — follow the existing naming scheme.
- Support Dynamic Type up to accessibility sizes: switch `HStack` to `VStack` with `@Environment(\.dynamicTypeSize)` when content no longer fits.
- Respect Reduce Motion (`@Environment(\.accessibilityReduceMotion)`) for non-essential animation.

## Localization

- String Catalog (`Localizable.xcstrings`): `Text("orders.empty.title")` / `String(localized: "orders.empty.title")` with a key or the English source string — match the project's convention. Add a comment for translators where the meaning is ambiguous.
- Pluralization through the catalog's plural variants, not string concatenation. Format numbers, dates, currency and measurements with `.formatted()` / `FormatStyle`, never by hand.

## Environment

- Custom environment values with the `@Entry` macro:

```swift
extension EnvironmentValues {
    @Entry var analytics: any AnalyticsClient = NoopAnalyticsClient()
}
```

- Read with `@Environment(\.analytics)`; observable models with `@Environment(SessionModel.self)`.

## Previews

- Every new screen and reusable component has a `#Preview` with representative states (content, empty, error, long text). Use `@Previewable @State` for interactive previews and in-memory data (`ModelContainer` in memory, stub services).
- Previews must compile — they are part of the build.

## UIKit / AppKit interop

- `UIViewRepresentable` / `UIViewControllerRepresentable` (`NSViewRepresentable` on Mac) only for what SwiftUI lacks; keep the coordinator small and forward events to the model.
- In a UIKit app, new SwiftUI screens live in `UIHostingController` subclasses or factory functions — follow the existing pattern.

## Performance

- Keep observable state granular so a change re-renders only the views that read it (see swiftui-state).
- Images: `AsyncImage` for simple cases, or the project's image loader; downsample large images before display.
- Heavy work (parsing, image processing) off the main actor — a `@concurrent` / `nonisolated` async function or an actor — then assign results on the main actor.
- Use `Self._printChanges()` / Instruments' SwiftUI template to diagnose redundant updates; never leave `_printChanges` in committed code.
