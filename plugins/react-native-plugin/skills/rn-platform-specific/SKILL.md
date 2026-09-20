---
name: rn-platform-specific
description: |
  iOS / Android platform-specific code in React Native: Platform.OS, Platform.select, .ios.tsx / .android.tsx file extensions, native modules, permissions, safe area handling, status bar.

  Use this skill to:
  - Branch code at runtime via Platform.OS / Platform.select.
  - Use file extensions for whole-component swaps.
  - Link and use native modules (Expo SDK or autolinked bare).
  - Handle permissions across platforms.
  - Configure status bar and safe area correctly.

  Do NOT use this skill for:
  - General project structure (see rn-conventions).
  - Navigation (see rn-navigation).
  - Storage (see rn-state-and-storage).
  - Testing (see rn-testing).
user-invocable: false
paths: ["**/*.ios.*", "**/*.android.*", "ios/**", "android/**"]
---

# Platform-Specific Patterns

iOS and Android have real differences. RN abstracts most, but sometimes you need to branch.

## `Platform.OS`

```ts
import { Platform } from 'react-native';

console.log(Platform.OS);                  // 'ios' | 'android' | 'web' | 'windows' | 'macos'

if (Platform.OS === 'ios') {
  // iOS-only logic
}
```

`Platform.OS` is set at runtime by RN. Use for small branches:

```tsx
const elevation = Platform.OS === 'android' ? { elevation: 4 } : { shadowOpacity: 0.1 };
```

Don't fork entire components for 5 lines of difference — use `Platform.select` or inline conditionals.

## `Platform.select`

Declarative platform branching:

```ts
const styles = StyleSheet.create({
  card: {
    padding: 16,
    backgroundColor: '#fff',
    ...Platform.select({
      ios: {
        shadowColor: '#000',
        shadowOffset: { width: 0, height: 2 },
        shadowOpacity: 0.1,
        shadowRadius: 4,
      },
      android: {
        elevation: 4,
      },
      default: {},   // web, windows, macos
    }),
  },
});
```

Each key returns a value; `Platform.select` picks the matching one.

## `Platform.Version`

Numeric on Android (API level: 28, 30, 33, 34), string on iOS (e.g. `'17.0'`):

```ts
if (Platform.OS === 'android' && Platform.Version >= 33) {
  // Android 13+ specific behavior
}

if (Platform.OS === 'ios' && parseInt(Platform.Version as string) >= 17) {
  // iOS 17+ specific
}
```

## File extensions

For whole-component swaps, Metro bundler picks files based on extension:

```
src/
├── components/
│   ├── DatePicker.tsx              # default for all platforms
│   ├── DatePicker.ios.tsx          # iOS-only override
│   ├── DatePicker.android.tsx      # Android-only override
│   ├── DatePicker.native.tsx       # native (iOS + Android, NOT web)
│   └── DatePicker.web.tsx          # web (RN Web)
```

```tsx
// import is the same — Metro resolves to the right file
import { DatePicker } from './components/DatePicker';
```

Use file extensions when:
- The two platforms need genuinely different markup.
- Native modules differ per platform.
- Otherwise, prefer `Platform.select` or inline conditionals — easier to read in one file.

## Native modules

### Expo SDK (managed)

Pre-installed, no native linking needed. Just install the JS package:

```bash
pnpm add expo-camera expo-location expo-notifications
```

```tsx
import * as Camera from 'expo-camera';
const [permission, requestPermission] = Camera.useCameraPermissions();
```

For custom native code in managed workflow, you need to migrate to dev-client or eject to bare.

### Bare RN (autolinking)

RN 0.60+ has autolinking — installing a package via npm/yarn/pnpm wires it up automatically:

```bash
pnpm add react-native-camera
cd ios && pod install                          # iOS only — install CocoaPods deps
```

After install:
- Run `npm run ios` / `npm run android` to rebuild with new native module.
- Restart Metro (`npm start --reset-cache` if cached).

Some packages need additional native config (manifest entries, Info.plist keys). Check package README.

### Custom native modules

Bare: write Objective-C/Swift (iOS) and Java/Kotlin (Android) modules. Beyond the scope of this skill.

Expo: write a config plugin that injects native code via the prebuild step. See `expo-build-properties` and `withDangerousMod` examples.

## Permissions

### Expo

Each feature-specific package handles its own permission flow:

```tsx
import * as Camera from 'expo-camera';
const [permission, requestPermission] = Camera.useCameraPermissions();
if (!permission?.granted) {
  await requestPermission();
}

import * as Location from 'expo-location';
const { status } = await Location.requestForegroundPermissionsAsync();
```

Declare permission descriptions in `app.json`:

```json
{
  "expo": {
    "ios": {
      "infoPlist": {
        "NSCameraUsageDescription": "Allow $(PRODUCT_NAME) to access your camera",
        "NSLocationWhenInUseUsageDescription": "Allow location access for map features"
      }
    },
    "android": {
      "permissions": ["CAMERA", "ACCESS_FINE_LOCATION"]
    }
  }
}
```

### Bare

Use `react-native-permissions` for unified API:

```tsx
import { check, request, RESULTS, PERMISSIONS } from 'react-native-permissions';

const status = await check(PERMISSIONS.IOS.CAMERA);
if (status !== RESULTS.GRANTED) {
  await request(PERMISSIONS.IOS.CAMERA);
}
```

Configure `Info.plist` (iOS) and `AndroidManifest.xml` (Android) with the right keys / permissions.

## Safe area

The notch (iPhone X+) and rounded corners (iPad/iPhone) eat into screen real estate. iOS has the home indicator; Android may have on-screen nav bar or gesture area.

### `react-native-safe-area-context` (preferred)

```tsx
// Wrap app once at root
import { SafeAreaProvider } from 'react-native-safe-area-context';

export default function App() {
  return (
    <SafeAreaProvider>
      <RootNavigator />
    </SafeAreaProvider>
  );
}

// Use SafeAreaView in screens
import { SafeAreaView } from 'react-native-safe-area-context';

<SafeAreaView style={{ flex: 1 }} edges={['top', 'bottom']}>
  {/* screen content */}
</SafeAreaView>

// Or insets for fine control
import { useSafeAreaInsets } from 'react-native-safe-area-context';
const insets = useSafeAreaInsets();
<View style={{ paddingTop: insets.top, paddingBottom: insets.bottom }}>...</View>
```

The RN-built-in `SafeAreaView` from `react-native` is deprecated — don't use it.

`edges` prop: which edges to apply safe area padding. Often `['top']` for screens with bottom tab nav (tab nav handles bottom safe area).

## Keyboard handling

```tsx
import { KeyboardAvoidingView, Platform } from 'react-native';

<KeyboardAvoidingView
  behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
  style={{ flex: 1 }}
  keyboardVerticalOffset={64}                  // header height
>
  {/* form */}
</KeyboardAvoidingView>
```

For more control, use `react-native-keyboard-controller`:

```tsx
import { KeyboardProvider } from 'react-native-keyboard-controller';
// Wrap app, provides better keyboard event APIs and animations.
```

## Status bar

### Expo

```tsx
import { StatusBar } from 'expo-status-bar';
<StatusBar style="auto" />
```

`style`: `'auto'` (matches color scheme), `'light'`, `'dark'`, `'inverted'`.

### Bare

```tsx
import { StatusBar } from 'react-native';
<StatusBar barStyle="dark-content" backgroundColor="#fff" translucent={false} />
```

`backgroundColor` is Android-only; iOS uses the underlying view's color.

## Pixel ratio and dimensions

```tsx
import { Dimensions, useWindowDimensions, PixelRatio } from 'react-native';

// One-time read (doesn't update on rotation)
const { width, height } = Dimensions.get('window');

// Reactive — updates on rotation/resize
const { width, height } = useWindowDimensions();

// For native conversions (rare)
const px = PixelRatio.getPixelSizeForLayoutSize(50);
```

Use `useWindowDimensions` for layouts that adapt to orientation.

## Common platform pitfalls

| Issue | Platforms | Fix |
|---|---|---|
| Shadows differ | iOS uses `shadowColor/Offset/Opacity`; Android uses `elevation` | `Platform.select` |
| Status bar overlaps content | iOS by default doesn't; Android `translucent` does | Set `translucent={false}` or wrap in SafeAreaView |
| Back button | Android has hardware back; iOS doesn't | `BackHandler` (Android) for custom logic; React Navigation handles automatically |
| Date/time picker | iOS shows wheel; Android shows native dialog | `@react-native-community/datetimepicker` handles both |
| Keyboard appearance | iOS animates over content; Android may resize layout | `KeyboardAvoidingView` with `behavior` per platform |
| Linking external apps | iOS has stricter URL scheme rules | `Linking.canOpenURL` before `openURL`; declare allowed schemes in `LSApplicationQueriesSchemes` (iOS) |
| Push notifications | Different APNs (iOS) vs FCM (Android) tokens | Use `expo-notifications` or `react-native-firebase` for unified API |
| Notch / Dynamic Island (iOS) | Only iOS | SafeAreaView handles automatically |

## Anti-patterns

- ❌ Forking entire screens for `Platform.OS === 'ios'` when 90% of code is shared — use inline conditionals or `.ios.tsx`/`.android.tsx` only for genuinely different markup.
- ❌ Ignoring safe areas — content clipped by notch/home indicator.
- ❌ Calling `NativeModules.X` directly without Platform check — module may not exist on the other platform = crash.
- ❌ Using web-only positioning (`position: 'fixed'`).
- ❌ Hardcoding pixel values without considering pixel ratio (use density-independent units; RN's "px" already handles this).
- ❌ Forgetting to declare permission usage strings in `app.json` / `Info.plist` — App Store / Play Store rejection.
- ❌ Assuming Android back button works without handling — `BackHandler.addEventListener('hardwareBackPress', ...)`.
- ❌ Mixing the deprecated `SafeAreaView` from `react-native` with `react-native-safe-area-context`.
