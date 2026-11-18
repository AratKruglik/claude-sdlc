---
name: watchos-app
description: |
  watchOS app specifics: single-target SwiftUI watch apps (companion or independent), glanceable design for small screens, navigation on the watch, the Digital Crown, complications and Smart Stack widgets with WidgetKit, background refresh and extended runtime sessions, workouts and HealthKit, WatchConnectivity with the iPhone app, networking and data sync constraints, notifications, power and performance limits.

  Use this skill to:
  - Build a watch screen that is useful in a two-second glance.
  - Add or update a complication / Smart Stack widget.
  - Share data between the iPhone and the watch correctly.
  - Run workout or health features within watchOS limits.

  Do NOT use this skill for:
  - iPhone / iPad targets — see apple-plugin:ios-ipados.
  - Shared SwiftUI view rules — see apple-plugin:swiftui-conventions.
user-invocable: false
paths: ["**/*Watch*/**", "**/*watch*/**"]
---

# watchOS Apps

## Know the target

- Modern watch apps are a single SwiftUI target (`SDKROOT = watchos`, `@main struct …: App`). Old projects may still have a WatchKit extension (`WKExtensionDelegate`, storyboard) — follow it, do not migrate as part of a feature.
- Companion (installed with the iPhone app, `WKCompanionAppBundleIdentifier`) vs independent (`WKRunsIndependentlyOfCompanionApp = YES`): an independent app must work without the phone — its own networking and sign-in.
- `WATCHOS_DEPLOYMENT_TARGET` gates APIs; check before using newer SwiftUI or WidgetKit features.
- Shared models and services live in a local package or shared files compiled into both targets; nothing UIKit-specific in shared code.

## Glanceable design

- One primary piece of information and at most a couple of actions per screen. Large type from text styles, high contrast, SF Symbols.
- Lists: `List` with concise rows; `.listStyle(.carousel)` only where the app already uses it.
- Navigation: a shallow `NavigationStack`, or a vertically paged `TabView` (`.tabViewStyle(.verticalPage)`) for parallel views; `NavigationSplitView` gives the list-detail pattern on the watch. Keep flows to two or three levels.
- Use `.containerBackground(…, for: .navigation)` / `.tabView` for the system-style gradient backgrounds.
- Toolbars: `ToolbarItem(placement: .topBarTrailing / .bottomBar)` for secondary actions instead of extra buttons in content.
- Digital Crown: `.digitalCrownRotation($value, …)` for value adjustment; scrolling content gets it for free.
- Text input is expensive on the watch — prefer pickers, presets and dictation-friendly `TextField`s; never require typing for a primary flow.
- Always-On: hide sensitive data and reduce update frequency when `@Environment(\.isLuminanceReduced)` is true.

## Complications and Smart Stack

- Complications are WidgetKit widgets in a widget extension: `.accessoryCircular`, `.accessoryRectangular`, `.accessoryInline`, `.accessoryCorner`. Render with `AccessoryWidgetBackground`, `Gauge`, `ProgressView` and support the tinted / vibrant rendering modes (`@Environment(\.widgetRenderingMode)`).
- Timelines: provide entries ahead of time; reload with `WidgetCenter.shared.reloadTimelines(ofKind:)` when the app's data changes. Reload budgets are limited — never reload on a timer from the app.
- Relevance (`TimelineEntryRelevance`, `RelevantContext`) helps the Smart Stack surface the widget at the right moment.
- Share data with the widget through an App Group container.

## Data and connectivity

- `WatchConnectivity` (`WCSession`) for phone ↔ watch: `updateApplicationContext` for latest-state sync, `transferUserInfo` for queued delivery, `sendMessage` only while both apps are reachable and the user is waiting. Activate the session early, handle `isReachable` / `activationState`, and treat every received dictionary as untrusted input.
- Networking: `URLSession` works directly on the watch (Wi-Fi, cellular or through the phone); keep payloads small and requests few. Background transfers use a background `URLSession`.
- Persistence: SwiftData or files in the watch's own container; sync through the backend or CloudKit when the data must match the phone.
- Secrets: Keychain on the watch; Keychain items are not shared with the phone automatically — sign in on the watch through the app's own flow (or receive a short-lived token over WatchConnectivity and store it in the watch Keychain).

## Background work and runtime

- Watch apps are suspended quickly. Schedule refresh with `WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate:userInfo:)` and handle it with `.backgroundTask(.appRefresh)`; complete every task promptly.
- Longer foreground-adjacent work (mindfulness, physical therapy, alarms) needs a `WKExtendedRuntimeSession` with the matching session type in the target's background modes.
- Workouts: `HKWorkoutSession` + `HKLiveWorkoutBuilder`; request HealthKit authorization only for the types the feature needs (`NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription`); end the session and save the workout on every exit path.
- Battery: no polling loops, no high-frequency timers; batch updates.

## Notifications

- Local and remote notifications appear on the watch; custom long-look interfaces through a `WKNotificationScene` / notification controller only if the app already has one.
- Actionable notifications route through the same handler as on the phone.

## Testing on the watch

- Unit tests for watch-specific models in a watch test target or the shared package; build with `xcodebuild -scheme <WatchScheme> -destination 'generic/platform=watchOS Simulator' build`.
- Preview complications with `#Preview(as: .accessoryRectangular) { Widget() } timeline: { … }`.
