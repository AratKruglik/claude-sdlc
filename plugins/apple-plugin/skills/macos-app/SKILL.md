---
name: macos-app
description: |
  macOS app specifics: SwiftUI scenes on the Mac (WindowGroup, Window, DocumentGroup, Settings, MenuBarExtra, UtilityWindow), opening and managing windows, menus and commands (CommandMenu, CommandGroup, keyboard shortcuts, focused values), Mac-idiomatic UI (Table, Inspector, toolbars, sidebar, context menus, hover), document-based apps and file access, App Sandbox and security-scoped bookmarks, hardened runtime and notarization constraints, AppKit interop, login items and menu-bar apps, Mac Catalyst vs native.

  Use this skill to:
  - Make a feature feel native on the Mac instead of a stretched iPad screen.
  - Add windows, menu commands, settings and keyboard shortcuts.
  - Read and write user files correctly under the App Sandbox.

  Do NOT use this skill for:
  - iPad apps running on Mac via Catalyst or "Designed for iPad" — see apple-plugin:ios-ipados.
  - Shared SwiftUI view rules — see apple-plugin:swiftui-conventions.
user-invocable: false
paths: ["**/*Mac*/**", "**/*mac*/**", "**/*.entitlements"]
---

# macOS Apps

## Know the target

- `SDKROOT = macosx` (native) vs `SUPPORTS_MACCATALYST = YES` (iPad app on Mac). Native macOS targets use SwiftUI for macOS and/or AppKit; Catalyst targets follow ios-ipados with Mac-specific guards.
- `MACOSX_DEPLOYMENT_TARGET` gates APIs (`if #available(macOS …, *)`).
- Distribution: Mac App Store (App Sandbox required) vs Developer ID (hardened runtime + notarization, sandbox optional). Check `ENABLE_APP_SANDBOX`, `ENABLE_HARDENED_RUNTIME` and the `.entitlements` file before touching file, network or process code.
- Multiplatform targets share code with iOS: guard Mac-only code with `#if os(macOS)` and keep shared views platform-neutral.

## Scenes and windows

```swift
@main
struct LedgerApp: App {
    var body: some Scene {
        WindowGroup("Ledger", id: "main") { ContentView() }
            .commands { LedgerCommands() }
        Window("Activity", id: "activity") { ActivityView() }
            .keyboardShortcut("0", modifiers: [.command, .option])
        Settings { SettingsView() }
        MenuBarExtra("Ledger", systemImage: "chart.bar") { MenuBarView() }
            .menuBarExtraStyle(.window)
    }
}
```

- `WindowGroup` for documents / multiple instances, `Window` for single auxiliary windows, `Settings` for the app's settings window (opened with ⌘,), `MenuBarExtra` for menu-bar items, `DocumentGroup` for document-based apps.
- Open windows with `@Environment(\.openWindow)` (`openWindow(id:)` / `openWindow(value:)`), close with `@Environment(\.dismissWindow)`.
- Set sensible window sizes: `.defaultSize`, `.windowResizability(.contentSize)`, and `.frame(minWidth:minHeight:)` on the root view.
- Each window has its own state; app-wide state lives in models injected at the app level.

## Menus, commands and keyboard

- Every primary action is reachable from the menu bar with a keyboard shortcut: `CommandMenu("Orders")` for new menus, `CommandGroup(replacing: .newItem)` / `(after: .sidebar)` to extend standard ones. Do not reuse system shortcuts (⌘Q, ⌘W, ⌘,).
- Commands act on the focused window through `@FocusedValue` / `.focusedSceneValue(\.selectedOrder, order)`; disable them with `.disabled(selection == nil)` when they do not apply.
- Context menus (`.contextMenu`) mirror menu actions on items; support Delete, ⌘A, arrow-key navigation and Return in lists and tables.
- Focus: `@FocusState`, `.focusable()`, `.onKeyPress` for custom keyboard handling.

## Mac-idiomatic UI

- `NavigationSplitView` with a `List(selection:)` sidebar; `Table` with sortable columns for tabular data (multi-selection via `Set<ID>`); `.inspector` for trailing detail panels; `.toolbar` items with `.principal` / `.primaryAction` placements and customization IDs.
- Smaller, denser controls than iOS: `.controlSize(.small)` where the design calls for it, `Form` with `.formStyle(.grouped)` in settings, standard `Toggle` / `Picker` styles.
- Hover feedback (`.onHover`, `.help("Tooltip")`), right-click menus, drag and drop with `Transferable` (including to Finder).
- No tab bars or bottom sheets ported from iOS — use sidebars, toolbars, sheets attached to windows.

## Files and the App Sandbox

- Let the user pick files: `.fileImporter` / `.fileExporter` / `NSOpenPanel` / `NSSavePanel`. The sandbox grants access only to what the user chose (plus the app container).
- Persist access across launches with security-scoped bookmarks: `url.bookmarkData(options: .withSecurityScope)`, resolve with `URL(resolvingBookmarkData:options: .withSecurityScope, …)`, wrap every use in `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` (with `defer`), and refresh stale bookmarks.
- Required entitlements must match the feature: `com.apple.security.files.user-selected.read-write`, `com.apple.security.network.client` for outbound network, `…network.server` only for servers. Add nothing broader.
- App data lives in the container (`URL.applicationSupportDirectory`); never write next to the app bundle or into the user's home directly.
- Document apps: `FileDocument` / `ReferenceFileDocument` with declared `UTType`s (exported in `Info.plist`); autosave and versions come from `DocumentGroup`.

## Processes, login items, helpers

- Launching helper tools (`Process`) is limited under the sandbox and needs embedded, signed executables — prefer frameworks and XPC services.
- Launch at login: `SMAppService.mainApp.register()`, reflected in a Settings toggle; never write LaunchAgents by hand.
- Menu-bar-only apps set `LSUIElement` and still provide a way to quit and to open settings.

## AppKit interop

- `NSViewRepresentable` / `NSViewControllerRepresentable` for AppKit-only controls (`NSTextView` with rich editing, custom `NSOutlineView`); `NSHostingView` / `NSHostingController` to embed SwiftUI in an AppKit app.
- In an AppKit app, follow its structure (window controllers, storyboards / XIBs, `NSDocument`) and add SwiftUI only where the project already does.
- `NSApplication.shared` and `NSWorkspace` calls are main-actor work.

## Release constraints

- Hardened runtime: no exceptions (`com.apple.security.cs.*`) unless the feature cannot work without one — list any you add.
- Do not archive, sign, notarize or staple in the pipeline; report anything that would change the signing or entitlement setup.
