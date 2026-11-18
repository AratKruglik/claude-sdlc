---
name: swiftui-navigation
description: |
  Navigation in SwiftUI apps: NavigationStack with value-based navigationDestination and a programmatic path, NavigationSplitView for iPad and Mac, TabView (including the sidebar-adaptable style), sheets, full-screen covers, popovers, inspectors, alerts and confirmation dialogs, router / coordinator objects, deep links (custom URL schemes, Universal Links), state restoration, UIKit navigation interop.

  Use this skill to:
  - Add a destination the same way existing ones are added.
  - Drive navigation from models (deep links, notifications, post-save redirects).
  - Handle incoming URLs safely.

  Do NOT use this skill for:
  - Platform-specific window and scene management — see apple-plugin:macos-app and apple-plugin:ios-ipados.
  - Screen state — see apple-plugin:swiftui-state.
user-invocable: false
paths: ["**/*.swift", "**/*.entitlements", "**/apple-app-site-association"]
---

# SwiftUI Navigation

## Detect the existing structure

- `NavigationStack(path: $router.path)` + a `Route` enum + `.navigationDestination(for: Route.self)` → value-based routing with a router. Add a case to the enum and its destination; never push with `NavigationLink(destination:)` alongside it.
- `NavigationSplitView` → sidebar / content / detail driven by selection state.
- `TabView` with one stack per tab → each tab owns its own path.
- UIKit `UINavigationController` / coordinators → push `UIHostingController`s through the coordinator.
- TCA → `StackState` / `@Presents` navigation in reducers.

Never use the deprecated `NavigationView` in new code.

## NavigationStack

```swift
enum OrdersRoute: Hashable {
    case detail(Order.ID)
    case edit(Order.ID)
}

@MainActor @Observable
final class OrdersRouter {
    var path: [OrdersRoute] = []
    func show(_ route: OrdersRoute) { path.append(route) }
    func popToRoot() { path.removeAll() }
}

NavigationStack(path: $router.path) {
    OrdersList()
        .navigationDestination(for: OrdersRoute.self) { route in
            switch route {
            case .detail(let id): OrderDetail(id: id)
            case .edit(let id): OrderEditor(id: id)
            }
        }
}
```

- Routes carry identifiers, not full models — the destination loads fresh data, and the path stays `Codable` for restoration.
- `NavigationLink(value: OrdersRoute.detail(order.id)) { OrderRow(order: order) }` for user taps; `router.show(...)` for programmatic navigation.
- Register `navigationDestination` once per value type, on a view inside the stack — not inside a lazy container.
- Titles: `.navigationTitle`, `.navigationBarTitleDisplayMode` (iOS); toolbar items with `ToolbarItem(placement:)` using semantic placements (`.primaryAction`, `.confirmationAction`, `.cancellationAction`).

## Split views (iPad, Mac)

- `NavigationSplitView { Sidebar(selection: $selection) } detail: { Detail(id: selection) }`; selection drives the detail, a `NavigationStack` inside the detail column handles deeper pushes.
- On compact width the split view collapses into a stack automatically — test both.

## Tabs

- `TabView(selection: $tab)` with the `Tab` API (`Tab("Orders", systemImage: "list.bullet", value: .orders) { … }`) when the deployment target allows it, else `.tabItem`. `.tabViewStyle(.sidebarAdaptable)` turns tabs into a sidebar on iPad and Mac.
- Each tab keeps its own navigation path; reselecting a tab pops to root if the app already does that.

## Modal presentation

- `.sheet(item: $editing)` with an `Identifiable` item rather than a boolean + optional pair; `.fullScreenCover` (iOS) only for immersive flows; `.popover` (anchored on iPad / Mac, a sheet on iPhone); `.inspector` for a trailing detail panel on iPad / Mac.
- Dismiss from inside with `@Environment(\.dismiss)`; return results through a callback or the shared model, not by reaching into the presenter.
- `.alert` / `.confirmationDialog` with `presenting:` data; destructive actions use `role: .destructive` and confirmation.
- Sheet sizing on iPhone: `.presentationDetents([.medium, .large])` only where the design calls for it.

## Deep links

- Custom schemes are declared in `CFBundleURLTypes`; Universal Links need the Associated Domains entitlement (`applinks:example.com`) and an `apple-app-site-association` file served by the backend.
- Handle in one place: `.onOpenURL { url in router.handle(url) }` at the root (plus `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` if needed).
- Parse into a `Route` with `URLComponents`; check scheme and host exactly, validate every parameter (type, range, ownership) and fall back to the root for anything unknown. Never navigate to a screen that performs an action (payment, delete, sign-in with a token) without the user confirming in-app.
- Deep links into authenticated areas wait for the session: store the pending route, navigate after sign-in.

## State restoration

- `@SceneStorage` for small per-scene state (selected tab, a `Codable` path encoded to `Data`). Restore defensively: drop routes whose data no longer exists.
