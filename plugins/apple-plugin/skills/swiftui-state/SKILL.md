---
name: swiftui-state
description: |
  State and data flow in SwiftUI apps: Observation (@Observable, @State, @Bindable, @Environment), legacy ObservableObject (@StateObject, @ObservedObject, @EnvironmentObject, @Published) in existing code, ownership rules, MainActor-isolated models, dependency injection, SwiftData (@Model, ModelContainer, ModelContext, @Query, migrations) and Core Data in existing apps, The Composable Architecture when installed. Detect and follow the pattern in place.

  Use this skill to:
  - Decide who owns a piece of state and how it reaches a view.
  - Write observable models that update only the views that read them.
  - Persist data with SwiftData or the project's existing store.
  - Inject services so models are testable.

  Do NOT use this skill for:
  - View composition and layout — see apple-plugin:swiftui-conventions.
  - Navigation state — see apple-plugin:swiftui-navigation.
user-invocable: false
paths: ["**/*.swift", "**/*.xcdatamodeld/**"]
---

# SwiftUI State and Data Flow

## Detect the pattern first

| Signal | Pattern | Follow it |
|---|---|---|
| `@Observable` classes, `@State var model = …`, `@Bindable` | Observation (iOS 17 / macOS 14 / watchOS 10+) | default for new code |
| `ObservableObject`, `@Published`, `@StateObject` | Combine-era observation | keep it in that feature; do not mix both in one model |
| `import ComposableArchitecture`, `@Reducer`, `Store` | TCA | new features as reducers, dependencies via `@Dependency` |
| `*ViewModel` classes per screen | MVVM | one view model per screen, same naming |

Never introduce a second pattern. Migrating a feature from `ObservableObject` to `@Observable` is a separate change unless the BA spec asks for it.

## Ownership

- **Value state local to a view** (a toggle, text field contents, a sheet flag): `@State private var`.
- **A model the view creates and owns**: `@State private var model = OrdersModel()` with Observation (`@StateObject` in legacy code). Never `@ObservedObject` / plain `let` for something the view creates — it is recreated on every parent render.
- **A model passed in by a parent**: a plain `let` / `var` property (Observation tracks reads automatically); `@Bindable var model` when the view needs bindings (`$model.title`).
- **Shared across a subtree**: inject with `.environment(model)`, read with `@Environment(OrdersModel.self)`.
- **Bindings to parent-owned values**: `@Binding`.
- **User preferences** that are not secret: `@AppStorage` / `@SceneStorage` (scene restoration). Never tokens or personal data.

## Observable models

```swift
@MainActor
@Observable
final class OrdersModel {
    private(set) var state: LoadState<[Order]> = .idle
    var filter: OrderFilter = .open

    @ObservationIgnored private let client: any OrdersClient

    init(client: any OrdersClient) {
        self.client = client
    }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await client.orders(filter: filter))
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error)
        }
    }
}
```

- Models that drive UI are `@MainActor` (implicit when the target uses `MainActor` default isolation). Do networking and heavy work through `async` services; assign results on the main actor.
- One enum for screen state instead of `isLoading` + `error` + `items` combinations.
- `private(set)` for state the view only reads; expose intent methods (`load()`, `toggleFavorite(_:)`) instead of letting views mutate internals.
- `@ObservationIgnored` for dependencies and caches that must not trigger updates.
- Keep models free of SwiftUI types where possible — they are the unit under test.

## Dependency injection

- Services (API clients, stores, clocks, analytics) are protocols with a live implementation, passed through initializers or the environment (`@Entry`), so tests and previews can substitute them.
- TCA projects: `@Dependency(\.ordersClient)` with `liveValue` / `testValue` / `previewValue`.
- No global singletons for new services unless the project's established pattern is a shared container — then register in it.

## SwiftData

```swift
@Model
final class Draft {
    var title: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var attachments: [Attachment] = []

    init(title: String, createdAt: Date = .now) {
        self.title = title
        self.createdAt = createdAt
    }
}
```

- One `ModelContainer` for the app (`.modelContainer(...)` on the scene); views read with `@Query(sort: \Draft.createdAt, order: .reverse)` and filter with `#Predicate`; writes through `@Environment(\.modelContext)` or a model actor.
- Background imports in a `@ModelActor actor` with its own context — never pass `@Model` instances across actors; pass `PersistentIdentifier`s.
- Schema changes: add a new `VersionedSchema` and a `SchemaMigrationPlan` stage when the app has shipped with the old schema; never rename or retype a stored property without one.
- CloudKit-backed containers need optional or defaulted properties and no unique constraints — check before adding fields.

## Core Data (existing apps)

- Use the existing `NSPersistentContainer` / stack; UI reads on `viewContext`, writes in `performBackgroundTask` or a background context; `@FetchRequest` / `@SectionedFetchRequest` in SwiftUI.
- Model changes create a new model version (`.xcdatamodeld`) with lightweight migration where possible; never edit the shipped version in place.

## Async streams and system events

- Observe `AsyncSequence`s (`NotificationCenter.default.notifications(named:)`, Core Location updates, SwiftData changes) inside `.task` so they are cancelled with the view, or in the model with a stored `Task` cancelled in `deinit`.
- Combine pipelines only where the feature already uses Combine.
