---
name: ios-ipados
description: |
  iPhone and iPad specifics for Apple apps: device families and size classes, adaptive layouts across iPhone, iPad and foldable iPhone screens, iPad multitasking and resizable windows, multiple scenes, pointer, hardware keyboard shortcuts, drag and drop, Apple Pencil, app lifecycle and background work (BGTaskScheduler, background URLSession), push and local notifications, permissions and Info.plist usage descriptions, privacy manifests, WidgetKit / Live Activities / App Intents extensions, Mac Catalyst and "Designed for iPad" on Mac.

  Use this skill to:
  - Make a screen correct on every iPhone and iPad size the target supports.
  - Add a system capability (notifications, background refresh, location, camera) with the right plist keys and permission flow.
  - Add or extend a widget, Live Activity or App Intent.

  Do NOT use this skill for:
  - Mac-native (AppKit / SwiftUI macOS) targets — see apple-plugin:macos-app.
  - watchOS targets — see apple-plugin:watchos-app.
user-invocable: false
paths: ["**/*.swift", "**/Info.plist", "**/*.entitlements", "**/PrivacyInfo.xcprivacy"]
---

# iOS and iPadOS

## Know what the target supports

- `TARGETED_DEVICE_FAMILY`: `1` iPhone, `2` iPad, `1,2` universal. A universal app must work on both — check every new screen on a compact-width iPhone and a regular-width iPad.
- `IPHONEOS_DEPLOYMENT_TARGET` decides which APIs need `if #available(iOS …, *)`.
- `SUPPORTS_MACCATALYST` / "Designed for iPad" on Apple silicon Macs — the iPad UI also runs on Mac; avoid APIs marked unavailable on Catalyst or guard them with `#if targetEnvironment(macCatalyst)`.

## Adaptive layout

- Design for size classes, not devices: read `@Environment(\.horizontalSizeClass)` and switch between compact (stack, single column) and regular (split view, multi-column) layouts. Never branch on `UIDevice.current.userInterfaceIdiom` for layout.
- iPad windows are freely resizable (Stage Manager and iPadOS windowing), and the same app may run in a narrow slide-over-sized window — a regular-width layout must collapse cleanly. Do not opt out with `UIRequiresFullScreen`; newer SDKs deprecate it and devices letterbox apps that set it.
- Foldable and multi-screen iPhones change the window size at runtime: treat a size-class change like an iPad resize — keep state in models, not in layout, so nothing resets when the screen changes.
- Orientation: support what `UISupportedInterfaceOrientations` lists (iPad apps should support all four).
- Safe areas, the Dynamic Island and the home indicator are handled by safe-area-aware layout — never hard-code insets.

## iPad interaction

- `NavigationSplitView` / `.tabViewStyle(.sidebarAdaptable)` for top-level navigation on regular width.
- Pointer: system controls get hover effects for free; custom tappable views add `.hoverEffect()` and `.contentShape(...)`.
- Hardware keyboard: `.keyboardShortcut("n", modifiers: .command)` on primary actions; menu-bar commands with `.commands { CommandMenu("Orders") { … } }` (shown in the iPad menu bar and the shortcut overlay).
- Drag and drop: `.draggable(item)` / `.dropDestination(for: Item.self)` with `Transferable` types — between apps and within the app.
- Multiple windows: set `UIApplicationSupportsMultipleScenes` only if the feature needs it; open with `@Environment(\.openWindow)`; each scene has its own navigation state.
- Apple Pencil: PencilKit (`PKCanvasView` via representable) or `.onPencilSqueeze` / `.onPencilDoubleTap` only where the feature is about drawing or annotation.

## Lifecycle and background work

- React to `@Environment(\.scenePhase)` (`.active` / `.inactive` / `.background`) to save state or pause work; UIKit apps use `UIScene` delegate callbacks.
- Background refresh / processing: register `BGTaskScheduler` identifiers in `BGTaskSchedulerPermittedIdentifiers` and handle them with `.backgroundTask(.appRefresh("id"))`; keep tasks short and always set an expiration handler.
- Long downloads / uploads: a background `URLSessionConfiguration`.
- Never rely on running in the background without a declared background mode — and declare only the modes the feature needs.

## Notifications

- Ask permission in context (when the user enables a feature that needs it), not at launch: `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])`.
- Remote push needs the Push Notifications capability; register with `registerForRemoteNotifications` and send the token to the backend over an authenticated request.
- Handle taps through `UNUserNotificationCenterDelegate` and route through the same deep-link handler as URLs.

## Permissions and privacy

- Every protected resource needs its usage string (`NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSContactsUsageDescription`, …) in `Info.plist` or the target's Info build settings — the app crashes on access without it. Write the purpose in user terms and add it to the String Catalog if `InfoPlist.xcstrings` exists.
- Prefer permissionless pickers: `PhotosPicker`, the document picker, `LocationButton` (CoreLocationUI).
- Handle denied / restricted states with a clear explanation and a link to Settings (`UIApplication.openSettingsURLString`).
- `PrivacyInfo.xcprivacy`: declare required-reason APIs you add (`UserDefaults`, file timestamps, system boot time, disk space) and any newly collected data types.

## Extensions

- **Widgets** (WidgetKit): a `TimelineProvider` / `AppIntentTimelineProvider`, views per `WidgetFamily`, data shared with the app through an App Group container (`UserDefaults(suiteName:)` for non-secret values, a shared SwiftData store, or files). Reload with `WidgetCenter.shared.reloadTimelines(ofKind:)` after the app changes the data.
- **Live Activities** (ActivityKit): `ActivityAttributes` with a small `ContentState`, Lock Screen and Dynamic Island presentations, `NSSupportsLiveActivities` in `Info.plist`; end activities when the task completes.
- **App Intents**: `AppIntent` structs with `@Parameter`s and an `AppShortcutsProvider` for Siri / Shortcuts / Spotlight; perform work through the same services the app uses; validate parameters like any other input.
- Extensions have tight memory and time limits — no heavy work, no large frameworks.
- Shared code between app and extensions lives in a local package or a shared framework, with `APPLICATION_EXTENSION_API_ONLY` respected (no `UIApplication.shared`).
