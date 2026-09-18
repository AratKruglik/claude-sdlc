---
name: rn-conventions
description: |
  React Native project structure, Expo vs bare workflow detection, app.json/app.config.js patterns, asset handling, fonts, styling approaches, hot-reload-friendly idioms.

  Use this skill to:
  - Detect Expo (managed/dev-client/EAS/ejected) vs bare RN workflow.
  - Pick correct project layout for each workflow.
  - Configure app.json / app.config.js with bundle ID, splash, icons, deep link schemes.
  - Handle assets, fonts, images correctly.
  - Pick a styling approach (StyleSheet / NativeWind / restyle / styled-components).

  Do NOT use this skill for:
  - Platform-specific branching (see rn-platform-specific).
  - Navigation (see rn-navigation).
  - Storage (see rn-state-and-storage).
  - Testing (see rn-testing).
user-invocable: false
paths: ["**/*.tsx", "**/*.ts", "**/*.jsx", "**/*.js"]
---

# React Native Conventions

## Workflow detection

| Marker | Workflow |
|---|---|
| `expo` in deps + `app.json` / `app.config.{js,ts}` + NO `ios/` `android/` | **Expo managed** |
| `expo` + `expo-dev-client` in deps | **Expo dev-client** (custom native code via prebuild) |
| `eas.json` present | **EAS Build** (managed or dev-client built in cloud) |
| `expo` in deps + `ios/` + `android/` folders | **Expo ejected** (treat as bare for native code) |
| No `expo`, `ios/` + `android/` folders | **Bare RN** (React Native CLI) |

Detection precedence: ejected/bare overrides managed if native folders exist.

For new RN projects in 2024+, Expo is the default. Bare projects are typically:
- Legacy projects predating Expo SDK 49.
- Projects with custom native modules that must be in source (rare with config plugins).
- Apps with complex native integrations (CarPlay, Apple Watch, Wear OS).

## Project layouts

### Expo Router (modern, file-based)

```
project-root/
├── app.json                       # OR app.config.{js,ts} for dynamic config
├── package.json
├── tsconfig.json
├── babel.config.js                # plugins: ['babel-plugin-module-resolver', etc.]
├── metro.config.js                # bundler config (optional)
├── eas.json                       # if using EAS Build
├── app/                           # Expo Router root
│   ├── _layout.tsx                # root layout (always)
│   ├── index.tsx                  # / (home)
│   ├── +not-found.tsx             # 404
│   ├── (auth)/                    # group (parens hide from URL)
│   │   ├── _layout.tsx            # auth stack
│   │   ├── login.tsx
│   │   └── signup.tsx
│   ├── (app)/                     # authenticated app group
│   │   ├── _layout.tsx            # tabs/drawer
│   │   ├── index.tsx              # /
│   │   ├── profile.tsx
│   │   └── [id].tsx               # dynamic
│   └── _root.tsx                  # SafeAreaProvider, theme provider, etc.
├── components/
│   ├── ui/                        # Button, Input, Card primitives
│   └── features/
├── hooks/
├── lib/
├── assets/
│   ├── icons/
│   ├── images/
│   └── fonts/
└── __tests__/                     # OR colocated *.test.tsx
```

### React Navigation (classical, modular routes)

```
project-root/
├── app.json
├── package.json
├── tsconfig.json
├── App.tsx                        # entry: NavigationContainer + RootNavigator
├── src/
│   ├── navigation/
│   │   ├── RootNavigator.tsx      # Auth/App switch
│   │   ├── AuthNavigator.tsx
│   │   ├── AppNavigator.tsx       # tabs/drawer
│   │   └── types.ts               # ParamList types
│   ├── screens/
│   │   ├── LoginScreen.tsx
│   │   ├── HomeScreen.tsx
│   │   └── ProfileScreen.tsx
│   ├── components/
│   ├── hooks/
│   ├── lib/
│   └── assets/
└── __tests__/
```

### Bare workflow additions

Bare RN projects also have:
- `ios/` — Xcode project, Info.plist, Podfile.
- `android/` — Gradle project, AndroidManifest.xml, build.gradle.
- `index.js` (root entry registering the app via `AppRegistry.registerComponent`).

For Expo managed, all native config flows through `app.json`/`app.config.js`. For bare, edit native files directly.

## `app.json` / `app.config.js`

Static (`app.json`):

```json
{
  "expo": {
    "name": "MyApp",
    "slug": "my-app",
    "version": "1.0.0",
    "orientation": "portrait",
    "icon": "./assets/icon.png",
    "splash": {
      "image": "./assets/splash.png",
      "resizeMode": "contain",
      "backgroundColor": "#ffffff"
    },
    "scheme": "myapp",
    "ios": {
      "bundleIdentifier": "com.example.myapp",
      "supportsTablet": true,
      "infoPlist": {
        "NSCameraUsageDescription": "Allow $(PRODUCT_NAME) to access your camera"
      }
    },
    "android": {
      "package": "com.example.myapp",
      "permissions": ["CAMERA"],
      "adaptiveIcon": {
        "foregroundImage": "./assets/adaptive-icon.png",
        "backgroundColor": "#ffffff"
      }
    },
    "plugins": [
      "expo-router",
      ["expo-camera", { "cameraPermission": "Allow $(PRODUCT_NAME) to access your camera" }]
    ],
    "extra": {
      "eas": { "projectId": "..." }
    }
  }
}
```

Dynamic (`app.config.js`):

```js
export default ({ config }) => ({
  ...config,
  name: process.env.APP_VARIANT === 'dev' ? 'MyApp (Dev)' : 'MyApp',
  ios: {
    ...config.ios,
    bundleIdentifier: process.env.APP_VARIANT === 'dev' ? 'com.example.myapp.dev' : 'com.example.myapp',
  },
});
```

Use dynamic config for env-aware bundle IDs (dev vs prod), feature flags, etc.

### Common app.config.js patterns

- **Multiple variants** (dev/staging/prod) via env vars.
- **Config plugins** to inject native changes without ejecting:

```js
plugins: [
  ['expo-build-properties', { ios: { useFrameworks: 'static' }, android: { kotlinVersion: '1.9.0' } }],
  ['./plugins/withCustomManifest', { /* options */ }],
]
```

- **Read from .env** via `expo-constants`:

```ts
import Constants from 'expo-constants';
const apiUrl = Constants.expoConfig?.extra?.apiUrl;
```

## Asset handling

### Images

```tsx
import { Image } from 'react-native';
import { Image as ExpoImage } from 'expo-image';

// Static, bundled with app
<Image source={require('./assets/logo.png')} style={{ width: 100, height: 100 }} />

// Remote
<Image source={{ uri: 'https://example.com/photo.jpg' }} style={{ width: 100, height: 100 }} />

// Expo Image — better caching, faster decode, supports placeholders
<ExpoImage
  source={require('./assets/logo.png')}
  contentFit="cover"
  transition={300}
  placeholder={blurhash}
/>
```

For multiple resolutions: name files `logo.png`, `logo@2x.png`, `logo@3x.png` — RN bundler picks based on screen density.

### Fonts

**Expo:**

```tsx
import { useFonts } from 'expo-font';

export default function Layout() {
  const [loaded] = useFonts({
    'Inter-Regular': require('./assets/fonts/Inter-Regular.ttf'),
    'Inter-Bold': require('./assets/fonts/Inter-Bold.ttf'),
  });
  if (!loaded) return null;
  return <App />;
}
```

Pair with `expo-splash-screen` to prevent FOUC:

```tsx
import * as SplashScreen from 'expo-splash-screen';
SplashScreen.preventAutoHideAsync();

const [loaded] = useFonts({...});
useEffect(() => { if (loaded) SplashScreen.hideAsync(); }, [loaded]);
```

**Bare:** link via `react-native-asset` or manually in Xcode/Android Studio.

### Vector icons

```tsx
import { Ionicons, MaterialIcons, Feather } from '@expo/vector-icons';
<Ionicons name="home" size={24} color="black" />
```

Bare projects: install `react-native-vector-icons`, link manually.

## Styling approaches

### `StyleSheet.create` (default, fastest)

```tsx
const styles = StyleSheet.create({
  container: { flex: 1, padding: 16 },
  title: { fontSize: 18, fontWeight: '600' },
});

<View style={styles.container}>
  <Text style={styles.title}>Hi</Text>
</View>
```

`StyleSheet.create` returns numeric IDs for style references — slightly more performant than inline objects on first render (deduplicates).

### NativeWind (Tailwind for RN)

```tsx
import { View, Text } from 'react-native';
<View className="flex-1 p-4">
  <Text className="text-lg font-semibold">Hi</Text>
</View>
```

Install: `pnpm add nativewind tailwindcss`. Configure `tailwind.config.js` and `babel.config.js`.

### restyle (Shopify, theme-driven)

```tsx
import { Box, Text } from '@theme';
<Box flex={1} padding="m">
  <Text variant="header">Hi</Text>
</Box>
```

Best for design-system-heavy apps.

### styled-components/native

```tsx
import styled from 'styled-components/native';
const Container = styled.View`flex: 1; padding: 16px;`;
```

Familiar to web devs but slightly slower than StyleSheet at scale.

Pick what's installed. Don't introduce a new approach.

## Fast Refresh and module-level state

React Native uses Metro + Fast Refresh. Module-level mutable state breaks Fast Refresh — components don't re-render when the module changes.

```ts
// ❌ Module-level mutable
let counter = 0;
export function increment() { counter++; }
```

```ts
// ✅ Use Context, Zustand, or other React-aware state
import { create } from 'zustand';
export const useCounter = create<{ count: number; inc: () => void }>((set) => ({
  count: 0,
  inc: () => set((s) => ({ count: s.count + 1 })),
}));
```

Hooks are Fast-Refresh-friendly by default.

## EAS Build (Expo managed deployment)

`eas.json`:

```json
{
  "cli": { "version": ">= 5.0.0" },
  "build": {
    "development": { "developmentClient": true, "distribution": "internal" },
    "preview": { "distribution": "internal" },
    "production": {}
  },
  "submit": { "production": {} }
}
```

Run via `npx eas-cli build --profile production --platform all`. Cloud builds → `.ipa` (iOS) / `.aab` (Android) artifacts. Out of pipeline scope; documented for awareness.

## Anti-patterns

- ❌ Editing `ios/` or `android/` files in Expo managed workflow. Use `app.config.js` config plugins.
- ❌ Module-level mutable state — breaks Fast Refresh.
- ❌ Storing JWTs in AsyncStorage.
- ❌ Using `<ScrollView>` for long dynamic lists (use `FlatList` or `FlashList`).
- ❌ Forgetting `<SafeAreaView>` — content clipped by notch/home indicator.
- ❌ Hardcoding bundle IDs / API URLs — use `app.config.js` env-driven values.
- ❌ Using web HTML primitives (`<div>`, `<span>`, `<a>`) — RN uses `<View>`, `<Text>`, `<Pressable>`/`<Link>`.
- ❌ `process.env.X` for runtime config in managed Expo — use `Constants.expoConfig.extra` or build-time replacement via babel.
- ❌ Snapshot tests of large component trees — high churn on RN especially.
