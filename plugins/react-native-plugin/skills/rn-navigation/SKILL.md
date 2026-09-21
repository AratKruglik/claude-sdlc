---
name: rn-navigation
description: |
  Navigation in React Native — both React Navigation v7 (classical, modular) and Expo Router (file-based, Expo 49+). Stack, tab, drawer navigators, deep linking, typed navigation, modal presentation, authentication flow patterns.

  Use this skill to:
  - Pick navigation lib based on what's installed (@react-navigation/* vs expo-router).
  - Configure typed routes with ParamList types or Expo Router's generated types.
  - Set up deep linking (URL schemes, Universal Links, App Links).
  - Build authentication flow with conditional navigators.
  - Use modal presentation correctly.

  Do NOT use this skill for:
  - Project structure (see rn-conventions).
  - Platform-specific differences (see rn-platform-specific).
  - State / storage (see rn-state-and-storage).
  - Testing navigation (see rn-testing).
user-invocable: false
paths: ["**/*.tsx", "**/*.ts"]
---

# React Native Navigation

Two paradigms in 2024+:

- **React Navigation v7** — classical, declarative, JS-based. Most existing apps use this.
- **Expo Router** — file-based (mirrors Next.js App Router), Expo 49+. Modern Expo default.

Detect which the project uses and apply matching patterns.

## Detection

| Marker (in dependencies) | Library |
|---|---|
| `@react-navigation/native` + at least one navigator (`@react-navigation/native-stack`, `@react-navigation/bottom-tabs`, `@react-navigation/drawer`) | React Navigation v7 |
| `expo-router` | Expo Router |
| Both | Migrating; mirror what's used in the area you touch |

## React Navigation v7

### Setup

```tsx
// App.tsx
import 'react-native-gesture-handler';                       // first import
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { SafeAreaProvider } from 'react-native-safe-area-context';

const Stack = createNativeStackNavigator<RootStackParamList>();

export default function App() {
  return (
    <SafeAreaProvider>
      <NavigationContainer>
        <Stack.Navigator>
          <Stack.Screen name="Home" component={HomeScreen} />
          <Stack.Screen name="Profile" component={ProfileScreen} options={{ title: 'Profile' }} />
        </Stack.Navigator>
      </NavigationContainer>
    </SafeAreaProvider>
  );
}
```

`react-native-gesture-handler` MUST be imported first in `App.tsx` (or `index.js`) for swipe gestures to work.

### Native Stack vs JS Stack

- `@react-navigation/native-stack` — uses native iOS `UINavigationController` and Android `Fragment`. Faster, native feel. Default choice.
- `@react-navigation/stack` — pure JS/Reanimated. Customizable transitions but slower.

Prefer Native Stack unless you need custom transitions JS Stack offers.

### Tab navigator

```tsx
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { Ionicons } from '@expo/vector-icons';

const Tab = createBottomTabNavigator<MainTabParamList>();

<Tab.Navigator>
  <Tab.Screen
    name="Home"
    component={HomeScreen}
    options={{
      tabBarIcon: ({ color, size }) => <Ionicons name="home" color={color} size={size} />,
    }}
  />
  <Tab.Screen name="Profile" component={ProfileStack} />
</Tab.Navigator>
```

`tabBarIcon`, `tabBarBadge`, `tabBarLabel` — common per-screen options.

### Drawer navigator

```tsx
import { createDrawerNavigator } from '@react-navigation/drawer';

const Drawer = createDrawerNavigator<DrawerParamList>();

<Drawer.Navigator>
  <Drawer.Screen name="Home" component={HomeScreen} />
  <Drawer.Screen name="Settings" component={SettingsScreen} />
</Drawer.Navigator>
```

Common pattern: drawer wraps a stack navigator per top-level item.

### Typed navigation

```ts
// types/navigation.ts
export type RootStackParamList = {
  Home: undefined;
  Profile: { userId: string };
  Settings: { initialTab?: 'general' | 'privacy' };
  Modal: { title: string };
};

export type MainTabParamList = {
  HomeTab: undefined;
  ProfileTab: { userId: string };
};
```

```tsx
// Screen props
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
type Props = NativeStackScreenProps<RootStackParamList, 'Profile'>;

export function ProfileScreen({ route, navigation }: Props) {
  const { userId } = route.params;
  return /* ... */;
}

// useNavigation in nested components
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';

const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
navigation.navigate('Profile', { userId: '123' });
```

For composite navigators (tab nested in stack):

```ts
import type { CompositeScreenProps } from '@react-navigation/native';

type ProfileTabProps = CompositeScreenProps<
  BottomTabScreenProps<MainTabParamList, 'ProfileTab'>,
  NativeStackScreenProps<RootStackParamList>
>;
```

### Authentication flow

Switch top-level navigator based on auth state:

```tsx
function RootNavigator() {
  const { user } = useAuth();
  return (
    <NavigationContainer>
      {user ? <AppStack /> : <AuthStack />}
    </NavigationContainer>
  );
}
```

The whole tree unmounts on auth change — clean state. Alternative: keep both stacks mounted and use `navigation.reset` on logout.

### Modal presentation

```tsx
<Stack.Navigator>
  <Stack.Group>
    <Stack.Screen name="Home" component={HomeScreen} />
    <Stack.Screen name="Profile" component={ProfileScreen} />
  </Stack.Group>
  <Stack.Group screenOptions={{ presentation: 'modal' }}>
    <Stack.Screen name="EditProfile" component={EditProfileScreen} />
    <Stack.Screen name="Settings" component={SettingsScreen} />
  </Stack.Group>
</Stack.Navigator>
```

`presentation: 'modal'` — slides up from bottom, dismissible by swipe. iOS native style.

`presentation: 'transparentModal'` — overlay with transparent background.

Other options: `'card'` (default push), `'fullScreenModal'`, `'formSheet'` (iOS-only sheet).

### Deep linking

```tsx
const linking = {
  prefixes: ['myapp://', 'https://myapp.example.com'],
  config: {
    screens: {
      Home: '',
      Profile: 'profile/:userId',
      Settings: 'settings',
      Modal: 'modal',
      NotFound: '*',
    },
  },
};

<NavigationContainer linking={linking}>...</NavigationContainer>
```

URL scheme registration:
- Expo: `app.json` `"expo": { "scheme": "myapp" }`.
- Bare iOS: `Info.plist` `CFBundleURLTypes`.
- Bare Android: `AndroidManifest.xml` `<intent-filter>`.

For Universal Links (iOS) / App Links (Android), domain verification required (`apple-app-site-association` JSON, `assetlinks.json`).

### Common navigation actions

```tsx
navigation.navigate('Profile', { userId: '123' });
navigation.push('Profile', { userId: '456' });           // always pushes new instance
navigation.replace('Login');                              // replaces current
navigation.goBack();
navigation.popToTop();
navigation.reset({ index: 0, routes: [{ name: 'Home' }] });
navigation.setOptions({ title: 'Updated' });             // dynamic header
```

`navigate(name)` — goes to existing instance if found, else pushes new.
`push(name)` — always creates new instance (e.g., infinite drill-down lists).

## Expo Router

File-based routing in `app/` folder, mirrors Next.js App Router patterns.

### Setup

```ts
// app.json or app.config.js — enable Expo Router
{
  "expo": {
    "scheme": "myapp",
    "plugins": ["expo-router"],
    "experiments": { "typedRoutes": true }
  }
}

// package.json main entry
{ "main": "expo-router/entry" }
```

### File conventions

```
app/
├── _layout.tsx                     # root layout (always Stack/Tabs/Slot)
├── index.tsx                       # / (home)
├── +not-found.tsx                  # 404
├── (auth)/                         # group (parens hide from URL)
│   ├── _layout.tsx                 # auth stack layout
│   ├── login.tsx                   # /login
│   └── signup.tsx                  # /signup
├── (app)/
│   ├── _layout.tsx                 # tabs/drawer layout
│   ├── index.tsx                   # /
│   ├── profile.tsx                 # /profile
│   └── [id].tsx                    # /:id
└── _root.tsx                       # SafeAreaProvider, providers
```

### Layouts

```tsx
// app/_layout.tsx
import { Stack } from 'expo-router';
import { SafeAreaProvider } from 'react-native-safe-area-context';

export default function RootLayout() {
  return (
    <SafeAreaProvider>
      <Stack>
        <Stack.Screen name="(app)" options={{ headerShown: false }} />
        <Stack.Screen name="(auth)" options={{ headerShown: false }} />
      </Stack>
    </SafeAreaProvider>
  );
}

// app/(app)/_layout.tsx — tabs
import { Tabs } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';

export default function AppLayout() {
  return (
    <Tabs>
      <Tabs.Screen name="index" options={{ title: 'Home', tabBarIcon: ({ color }) => <Ionicons name="home" color={color} /> }} />
      <Tabs.Screen name="profile" options={{ title: 'Profile' }} />
    </Tabs>
  );
}
```

### Navigation hooks

```tsx
import { useRouter, useLocalSearchParams, useGlobalSearchParams, Link } from 'expo-router';

// Programmatic
const router = useRouter();
router.push('/profile');
router.push({ pathname: '/[id]', params: { id: '123' } });
router.replace('/login');
router.back();

// Local search params (current route only)
const { id } = useLocalSearchParams<{ id: string }>();

// Global search params (any ancestor)
const { tab } = useGlobalSearchParams<{ tab?: string }>();

// Link
<Link href="/profile">Profile</Link>
<Link href={{ pathname: '/[id]', params: { id: '123' } }}>User</Link>
```

### Authentication flow with Expo Router

```tsx
// app/_layout.tsx
import { Stack, useRouter, useSegments } from 'expo-router';
import { useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';

export default function RootLayout() {
  const { user, loading } = useAuth();
  const segments = useSegments();
  const router = useRouter();

  useEffect(() => {
    if (loading) return;
    const inAuthGroup = segments[0] === '(auth)';
    if (!user && !inAuthGroup) router.replace('/login');
    else if (user && inAuthGroup) router.replace('/');
  }, [user, segments, loading, router]);

  return <Stack screenOptions={{ headerShown: false }} />;
}
```

### Typed routes (Expo Router experimental)

Enable in `app.json`:

```json
{ "expo": { "experiments": { "typedRoutes": true } } }
```

Generates `expo-router/types.ts` — `Link href`, `router.push` paths are type-checked. Wrong path = compile error.

## Deep linking comparison

| Library | Configuration |
|---|---|
| React Navigation | `linking` prop on `NavigationContainer`, mapping URL paths to screens |
| Expo Router | URL scheme in `app.json`; routes inferred from `app/` tree automatically |

For testing deep links:
- iOS Simulator: `xcrun simctl openurl booted myapp://profile/123`.
- Android Emulator: `adb shell am start -W -a android.intent.action.VIEW -d "myapp://profile/123"`.

## Authentication patterns

Two common approaches:

1. **Conditional navigator at root** (React Navigation): unmount everything on auth change.
2. **Auth check in layout effect** (Expo Router): redirect imperatively based on segments.

Both work; pick what the project uses.

## Anti-patterns

- ❌ Forgetting `react-native-gesture-handler` import at the very top of `App.tsx` / `index.js`.
- ❌ Forgetting `<NavigationContainer>` at root (React Navigation).
- ❌ Mixing typed and untyped `useNavigation()` calls — pick one approach project-wide.
- ❌ Deep nesting that confuses back-button behavior on Android.
- ❌ Storing navigation params in state when they're already in route — `route.params` is the source of truth.
- ❌ Hardcoded route names as strings — use ParamList types or Expo Router typed routes.
- ❌ Using `navigation.navigate('Login')` to log out instead of `navigation.reset` — old screens stay in stack.
- ❌ Forgetting `presentation: 'modal'` on screens that should slide up modally.
- ❌ Mixing React Navigation with Expo Router in the same app — pick one.
