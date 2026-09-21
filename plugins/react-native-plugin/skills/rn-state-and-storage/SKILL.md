---
name: rn-state-and-storage
description: |
  State management and storage choice in React Native. State libs work mostly the same as web (Zustand, Jotai, Redux Toolkit, TanStack Query, Context); storage choice is RN-specific — AsyncStorage, MMKV, SecureStore, Keychain. Hydration patterns, splash screen handling, secrets discipline.

  Use this skill to:
  - Pick state management lib (matches web React intuition).
  - Pick storage by sensitivity (AsyncStorage / MMKV / SecureStore / Keychain).
  - Hydrate state on app start without UI flicker.
  - Persist Zustand store across app restarts.
  - Avoid storing secrets in plaintext storage.

  Do NOT use this skill for:
  - General project conventions (see rn-conventions).
  - Platform-specific code (see rn-platform-specific).
  - Navigation (see rn-navigation).
  - Testing state/storage (see rn-testing).
user-invocable: false
paths: ["**/*.tsx", "**/*.ts"]
---

# State Management and Storage in RN

State management is largely identical to web React. Storage is the genuinely RN-specific concern.

## State management — same as react-plugin

| Need | Tool |
|---|---|
| Local component state | `useState`, `useReducer` |
| Shared between siblings | Lift to common parent OR Context |
| App-wide UI state (theme, modals, sidebars) | Context, Zustand, or Jotai |
| Server data with caching | TanStack Query, SWR |
| Complex domain state | Redux Toolkit (or Zustand for simpler cases) |
| Form state | react-hook-form |

Same decision tree as web — see `react-plugin:react-state-management` skill for deep dive on each tool. RN-specific notes below.

### Context in RN

Context survives Fast Refresh ONLY if values are not held in module-level closure. Store provider state in `useState` / `useReducer` inside the provider component, not in a top-level `let`.

```tsx
// ✅ Survives Fast Refresh
export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState<Theme>('light');
  return <ThemeContext.Provider value={{ theme, setTheme }}>{children}</ThemeContext.Provider>;
}

// ❌ Lost on Fast Refresh
let theme: Theme = 'light';
export const ThemeContext = createContext({ theme, setTheme: (t: Theme) => { theme = t; } });
```

### Zustand with persistence

```ts
import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import AsyncStorage from '@react-native-async-storage/async-storage';

export const useUserStore = create(
  persist(
    (set) => ({ user: null, setUser: (user: User | null) => set({ user }) }),
    {
      name: 'user-storage',
      storage: createJSONStorage(() => AsyncStorage),
    }
  )
);
```

For sensitive data, swap AsyncStorage for SecureStore wrapper:

```ts
import * as SecureStore from 'expo-secure-store';

const secureStorage = {
  getItem: (key: string) => SecureStore.getItemAsync(key),
  setItem: (key: string, value: string) => SecureStore.setItemAsync(key, value),
  removeItem: (key: string) => SecureStore.deleteItemAsync(key),
};

storage: createJSONStorage(() => secureStorage),
```

Note: SecureStore values are limited to ~2KB on iOS. For larger sensitive data, encrypt with `expo-crypto` and store ciphertext in MMKV.

### TanStack Query in RN

Works identically to web, but consider:

- **Network detection**: `@react-native-community/netinfo` to gate queries when offline.
- **Persistence**: `@tanstack/react-query-persist-client` + AsyncStorage/MMKV for offline-first apps.
- **Refetch on app foreground**: TanStack Query has `refetchOnWindowFocus` (web); for RN, manually trigger via `AppState` listener.

```tsx
import { AppState } from 'react-native';
import { focusManager } from '@tanstack/react-query';

useEffect(() => {
  const sub = AppState.addEventListener('change', (state) => {
    focusManager.setFocused(state === 'active');
  });
  return () => sub.remove();
}, []);
```

## Storage choices

The RN-specific decision. Each has a place.

### AsyncStorage (`@react-native-async-storage/async-storage`)

Async key-value, plaintext on disk. Most common, but **NOT secure**.

```ts
import AsyncStorage from '@react-native-async-storage/async-storage';

await AsyncStorage.setItem('@theme', 'dark');
const theme = await AsyncStorage.getItem('@theme');                 // string | null
await AsyncStorage.removeItem('@theme');
await AsyncStorage.multiGet(['@a', '@b']);                          // [[key, value], ...]
await AsyncStorage.multiSet([['@a', '1'], ['@b', '2']]);
```

**Use for**:
- User preferences (theme, locale, sort orders).
- Onboarding flags ("user has seen welcome").
- Cached non-sensitive responses.

**NEVER**:
- Auth tokens.
- PII / health / financial data.
- Anything regulated (GDPR-sensitive).

### MMKV (`react-native-mmkv`)

Synchronous, fast (~30x faster than AsyncStorage), encrypted optional. Modern preferred for non-secrets.

```ts
import { MMKV } from 'react-native-mmkv';

const storage = new MMKV();
storage.set('theme', 'dark');                   // sync, no await needed
const theme = storage.getString('theme');        // 'dark' or undefined
storage.delete('theme');
storage.contains('theme');                       // boolean
storage.getAllKeys();                            // string[]
```

Optional encryption:

```ts
const storage = new MMKV({
  id: 'user-storage',
  encryptionKey: 'a-secret-key-from-secure-store',
});
```

**Use for**:
- User preferences (faster than AsyncStorage).
- Frequently-read state (synchronous).
- Encrypted-at-rest data (when paired with key from SecureStore).

**Caveat**: requires JSI / native build — works in dev-client, EAS Build, bare. NOT in Expo Go (managed without dev client).

### SecureStore (`expo-secure-store`)

Keychain (iOS) / EncryptedSharedPreferences (Android). For sensitive data.

```ts
import * as SecureStore from 'expo-secure-store';

await SecureStore.setItemAsync('refresh-token', token);
const token = await SecureStore.getItemAsync('refresh-token');
await SecureStore.deleteItemAsync('refresh-token');
```

**Use for**:
- Auth tokens (JWT, refresh tokens, OAuth).
- API keys that must persist across app launches (rare — prefer not persisting).
- Biometric-protected secrets.

**Limits**:
- ~2KB per value on iOS (Keychain limit).
- Async API only.
- Expo SDK package — works in managed and bare via Expo modules.

### Keychain (`react-native-keychain`)

Bare alternative to SecureStore. Same purpose, more configuration options (access groups, biometric prompts).

```ts
import * as Keychain from 'react-native-keychain';

await Keychain.setGenericPassword('username', 'password');
const credentials = await Keychain.getGenericPassword();
if (credentials) console.log(credentials.username, credentials.password);
await Keychain.resetGenericPassword();
```

For finer control:

```ts
await Keychain.setInternetCredentials('api.example.com', 'username', 'token', {
  accessControl: Keychain.ACCESS_CONTROL.BIOMETRY_CURRENT_SET,
  accessible: Keychain.ACCESSIBLE.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
});
```

Use in bare projects or when SecureStore's API is too limited.

## Decision matrix

| Data | Storage |
|---|---|
| Auth tokens (JWT, refresh) | **SecureStore / Keychain** |
| OAuth tokens | **SecureStore / Keychain** |
| User credentials (rare — prefer not storing) | **Keychain** with biometric |
| Theme preference | MMKV or AsyncStorage |
| Locale | MMKV or AsyncStorage |
| Onboarding seen flag | MMKV or AsyncStorage |
| Cached server data (offline-first) | TanStack Query persist + MMKV/AsyncStorage |
| Large blobs (images, files) | `expo-file-system` (managed) or `react-native-fs` (bare) |
| Database-like queries | `expo-sqlite`, WatermelonDB, op-sqlite |

## Hydration on app start

Read storage, populate state, hide splash screen — in that order.

### Expo + expo-splash-screen

```tsx
// app/_layout.tsx (Expo Router) or App.tsx
import * as SplashScreen from 'expo-splash-screen';
import { useEffect, useState } from 'react';
import { useUserStore } from '@/stores/userStore';

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const [hydrated, setHydrated] = useState(false);
  const restoreUser = useUserStore((s) => s.restoreUser);

  useEffect(() => {
    (async () => {
      await restoreUser();
      setHydrated(true);
    })();
  }, [restoreUser]);

  useEffect(() => {
    if (hydrated) SplashScreen.hideAsync();
  }, [hydrated]);

  if (!hydrated) return null;
  return <App />;
}
```

### Zustand persist hydration

Zustand `persist` middleware exposes `hasHydrated`:

```tsx
const { isHydrated } = useUserStore.persist;
if (!isHydrated()) return <SplashScreen />;
```

Or subscribe via `useStore` selector:

```tsx
const hasHydrated = useUserStore((s) => s._hasHydrated);
```

### Bare RN

No Expo splash. Use `react-native-bootsplash` or implement custom splash UI.

## Sensitive data handling rules

1. **JWT and refresh tokens**: SecureStore / Keychain only. Never AsyncStorage.
2. **Don't log secrets**: redact tokens before any `console.log` / analytics call.
3. **Clear on logout**: explicitly delete all sensitive keys.
4. **Don't sync sensitive data via Settings.app / Cloud Backup**: configure SecureStore with `keychainService` and access group flags.
5. **Encrypt large sensitive blobs**: MMKV with encryption key from SecureStore (because SecureStore has size limits).

## Anti-patterns

- ❌ Storing JWT in AsyncStorage — readable by malicious apps with root/jailbreak access.
- ❌ Persisting entire Redux store including server data — bloated AsyncStorage, slow restore.
- ❌ Calling AsyncStorage in loops — batch with `multiGet` / `multiSet`.
- ❌ Forgetting to `await` AsyncStorage operations — silent races.
- ❌ Module-level mutable state — breaks Fast Refresh and SSR (RN Web).
- ❌ Logging secrets via `console.log` for "debugging".
- ❌ Mixing storage libs without a clear rationale (e.g., MMKV for some, AsyncStorage for others on the same app).
- ❌ Showing UI before hydration completes — flicker or wrong-state render.
- ❌ Storing user-modifiable data in `Constants.expoConfig.extra` — that's read-only build-time config, not runtime state.
