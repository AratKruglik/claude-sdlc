---
name: rn-testing
description: |
  Testing React Native: Jest with jest-expo / react-native preset, React Testing Library Native, native module mocking, hook testing. Optional sections for Detox (native automation) and Maestro (declarative YAML e2e).

  Use this skill to:
  - Configure Jest preset based on workflow.
  - Write component tests with @testing-library/react-native.
  - Mock native modules (react-native-reanimated, expo-*, react-native-mmkv).
  - Test custom hooks via renderHook.
  - Set up Detox or Maestro for e2e (optional, requires native toolchain).

  Do NOT use this skill for:
  - General RN conventions (see rn-conventions).
  - Web-React testing (see react-plugin:react-testing — different jsdom setup).
  - Plain Node testing patterns (see nodejs-plugin equivalents).
user-invocable: false
paths: ["**/*.test.{ts,tsx,js,jsx}", "__tests__/**"]
---

# React Native Testing

## Test framework selection

| Layer | Framework |
|---|---|
| Component, hook, plain TS unit | **Jest** with `jest-expo` (Expo) or `react-native` preset (bare) |
| End-to-end (optional) | **Detox** (native automation) or **Maestro** (declarative YAML) |

Vitest is uncommon in RN — Jest's native module mocking and Metro integration is more battle-tested. If a project specifically uses Vitest in RN, follow it; otherwise default to Jest.

## Jest setup

### Expo (managed, dev-client)

```js
// jest.config.js
module.exports = {
  preset: 'jest-expo',
  setupFilesAfterEach: ['<rootDir>/jest.setup.ts'],
  transformIgnorePatterns: [
    'node_modules/(?!((jest-)?react-native|@react-native(-community)?|expo(nent)?|@expo(nent)?/.*|@expo-google-fonts/.*|react-navigation|@react-navigation/.*|@unimodules/.*|unimodules|sentry-expo|native-base|react-native-svg)/)',
  ],
};
```

Install: `pnpm add -D jest jest-expo @testing-library/react-native @testing-library/jest-native`.

### Bare RN

```js
// jest.config.js
module.exports = {
  preset: 'react-native',
  setupFilesAfterEach: ['<rootDir>/jest.setup.ts'],
  transformIgnorePatterns: [
    'node_modules/(?!((jest-)?react-native|@react-native(-community)?|@react-navigation/.*|react-native-mmkv|react-native-reanimated)/)',
  ],
};
```

Install: `pnpm add -D jest @react-native/babel-preset @testing-library/react-native @testing-library/jest-native`.

### `jest.setup.ts`

```ts
import '@testing-library/jest-native/extend-expect';

// Common mocks for native modules
jest.mock('react-native-reanimated', () => require('react-native-reanimated/mock'));

jest.mock('@react-native-async-storage/async-storage', () =>
  require('@react-native-async-storage/async-storage/jest/async-storage-mock')
);

// Silence common warnings
jest.mock('react-native/Libraries/Animated/NativeAnimatedHelper');
```

## Component tests with RTL Native

```tsx
// src/components/UserCard.test.tsx
import { describe, it, expect, jest } from '@jest/globals';
import { render, screen, fireEvent } from '@testing-library/react-native';
import { UserCard } from './UserCard';

describe('UserCard', () => {
  it('renders user name and email', () => {
    render(<UserCard user={{ id: '1', name: 'Alice', email: 'a@b.c' }} />);
    expect(screen.getByText('Alice')).toBeOnTheScreen();
    expect(screen.getByText('a@b.c')).toBeOnTheScreen();
  });

  it('calls onPress when card pressed', () => {
    const onPress = jest.fn();
    render(<UserCard user={{ id: '1', name: 'Alice', email: 'a@b.c' }} onPress={onPress} />);
    fireEvent.press(screen.getByLabelText('User card for Alice'));
    expect(onPress).toHaveBeenCalledWith('1');
  });
});
```

### Query priority (RN-adapted)

1. `getByLabelText` — accessibility labels (most stable on RN).
2. `getByRole(role, { name })` — works for `Pressable`, `TextInput`, etc.; weaker than web due to less consistent role mapping.
3. `getByText` — for `<Text>` content.
4. `getByPlaceholderText` — `TextInput` placeholders.
5. `getByDisplayValue` — `TextInput` current value.
6. `getByTestId` — last resort (use `testID` prop on RN components).

`fireEvent.press` is the RN equivalent of `userEvent.click`. For text input:

```tsx
fireEvent.changeText(screen.getByLabelText('Email'), 'a@b.c');
```

For scroll, swipe, gesture interactions: more complex setup, often easier in e2e.

## Mocking native modules

### Common patterns

```ts
// react-native-mmkv
jest.mock('react-native-mmkv', () => ({
  MMKV: jest.fn().mockImplementation(() => ({
    set: jest.fn(),
    getString: jest.fn(),
    delete: jest.fn(),
    contains: jest.fn(),
  })),
}));

// expo-secure-store
jest.mock('expo-secure-store', () => ({
  getItemAsync: jest.fn().mockResolvedValue(null),
  setItemAsync: jest.fn().mockResolvedValue(undefined),
  deleteItemAsync: jest.fn().mockResolvedValue(undefined),
}));

// react-native-keychain
jest.mock('react-native-keychain', () => ({
  setGenericPassword: jest.fn().mockResolvedValue(undefined),
  getGenericPassword: jest.fn().mockResolvedValue(false),
  resetGenericPassword: jest.fn().mockResolvedValue(undefined),
}));

// expo-file-system
jest.mock('expo-file-system', () => ({
  documentDirectory: '/test/',
  readAsStringAsync: jest.fn(),
  writeAsStringAsync: jest.fn(),
}));
```

### Reanimated mock

```ts
jest.mock('react-native-reanimated', () => require('react-native-reanimated/mock'));
```

The official mock disables animations and provides synchronous values — usually what tests want.

### Gesture Handler mock

```ts
jest.mock('react-native-gesture-handler', () => {
  const View = require('react-native').View;
  return {
    Swipeable: View,
    DrawerLayout: View,
    State: {},
    ScrollView: View,
    PanGestureHandler: View,
    BaseButton: View,
    Directions: {},
  };
});
```

Or import from `react-native-gesture-handler/jestSetup` if shipped.

### Navigation mock

```ts
const mockNavigate = jest.fn();
jest.mock('@react-navigation/native', () => ({
  useNavigation: () => ({ navigate: mockNavigate, goBack: jest.fn() }),
  useRoute: () => ({ params: { userId: '123' } }),
}));
```

For Expo Router:

```ts
jest.mock('expo-router', () => ({
  useRouter: () => ({ push: jest.fn(), replace: jest.fn(), back: jest.fn() }),
  useLocalSearchParams: () => ({ id: '123' }),
}));
```

## Hooks testing

```tsx
// src/hooks/useDebounce.test.ts
import { renderHook, act } from '@testing-library/react-native';
import { useDebounce } from './useDebounce';

describe('useDebounce', () => {
  it('debounces value updates', () => {
    jest.useFakeTimers();
    const { result, rerender } = renderHook(({ value }) => useDebounce(value, 300), {
      initialProps: { value: 'a' },
    });
    expect(result.current).toBe('a');

    rerender({ value: 'b' });
    expect(result.current).toBe('a');

    act(() => { jest.advanceTimersByTime(300); });
    expect(result.current).toBe('b');

    jest.useRealTimers();
  });
});
```

For RN < 0.71, use `@testing-library/react-hooks` instead.

## Network mocking with msw

msw works in RN tests via the jsdom polyfill in jest-expo:

```ts
// jest.setup.ts
import { setupServer } from 'msw/node';
import { http, HttpResponse } from 'msw';

const server = setupServer(
  http.get('https://api.example.com/users', () =>
    HttpResponse.json([{ id: '1', name: 'Alice' }])
  )
);

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

export { server };
```

Per-test override:

```ts
import { http, HttpResponse } from 'msw';
server.use(http.get('https://api.example.com/users', () => HttpResponse.error()));
```

## Snapshot tests — sparingly

```tsx
import { render } from '@testing-library/react-native';
import { UserCard } from './UserCard';

it('matches snapshot', () => {
  const { toJSON } = render(<UserCard user={{ id: '1', name: 'Alice', email: 'a@b.c' }} />);
  expect(toJSON()).toMatchSnapshot();
});
```

RN snapshot trees are LARGE — 500+ lines per component is normal. Review noise outweighs value for most components. Use only for stable design-system primitives.

Prefer `toMatchInlineSnapshot()` for small expected outputs — keeps them in test file for easy review.

## Coverage discipline

Target ≥80% on:
- Custom hooks.
- Utility functions (`lib/`).
- State-management slices / Zustand stores / TanStack Query hooks.
- Components with conditional rendering or event logic.

Skip / lower bar:
- Pure presentational components (snapshot churn outweighs value).
- Navigation wiring (`navigation/*`).
- `App.tsx` / root layout.

```ts
// jest.config.js
module.exports = {
  preset: 'jest-expo',
  collectCoverageFrom: [
    'src/**/*.{ts,tsx}',
    '!src/navigation/**',
    '!src/**/*.types.ts',
    '!src/App.tsx',
    '!**/node_modules/**',
  ],
};
```

## Detox e2e (OPTIONAL — only if installed)

Native automation framework. Drives real iOS Simulator / Android Emulator. Higher fidelity, higher setup cost.

### Detection

```json
// package.json
"devDependencies": { "detox": "^20.x" }
"detox": { "configurations": {...} }
```

If `detox` not in deps, skip this section.

### Setup overview

1. Install: `pnpm add -D detox @config-plugins/detox`.
2. Configure `.detoxrc.js` with iOS Simulator / Android Emulator targets.
3. Build the app for testing: `detox build --configuration ios.sim.debug`.
4. Run tests: `detox test --configuration ios.sim.debug`.

Requires:
- macOS with Xcode (for iOS).
- Android SDK + emulator image (for Android).
- Java 17+ for Gradle.

### Test pattern

```ts
import { device, element, by, expect } from 'detox';

describe('Login flow', () => {
  beforeAll(async () => {
    await device.launchApp({ newInstance: true });
  });

  it('user can log in and reach dashboard', async () => {
    await element(by.id('login-email')).typeText('a@b.c');
    await element(by.id('login-password')).typeText('longenough');
    await element(by.id('login-submit')).tap();
    await expect(element(by.id('dashboard-title'))).toBeVisible();
  });
});
```

Async assertions are first-class: `toBeVisible`, `toExist`, `toHaveText`, `toHaveLabel`.

`testID` props on RN components map to Detox's `by.id()`. Use accessibility labels for `by.label()`.

### Detox limits

- Setup overhead is significant.
- Test stability depends on native config.
- Iteration loop slow (~minutes per test on cold starts).
- Hard to run in CI without dedicated mac runners (iOS).

For most projects, Detox is overkill. Use it when:
- Critical user flows MUST be regression-protected.
- Team has the infrastructure.

## Maestro e2e (OPTIONAL — alternative to Detox)

Declarative YAML-based e2e. Simpler than Detox, less flexible.

### Detection

If `maestro` CLI is installed (no npm package required) and `.maestro/` folder exists with YAML flows.

### Flow example

```yaml
# .maestro/login.yaml
appId: com.example.myapp
---
- launchApp
- tapOn:
    id: "login-email"
- inputText: "a@b.c"
- tapOn:
    id: "login-password"
- inputText: "longenough"
- tapOn:
    id: "login-submit"
- assertVisible:
    id: "dashboard-title"
```

Run: `maestro test .maestro/login.yaml`.

### Maestro vs Detox

| Aspect | Maestro | Detox |
|---|---|---|
| Test format | YAML | JavaScript/TypeScript |
| Setup complexity | Low (CLI install) | High (native build config) |
| Flexibility | Limited (declarative) | High (full programmability) |
| Speed | Fast | Slow |
| Custom logic | Limited (JS expressions) | Full Node access |
| CI integration | Easy | Mac runners required for iOS |

Use Maestro for smoke flows; use Detox when you need programmability.

## Iteration cap (from QA agent)

The qa-engineer agent has a hard 3-attempt cap on fixing failing tests. Mark genuinely flaky tests `it.skip(...)` with a comment after attempt #3 — RN tests are particularly prone to flakiness from native module mocks.

## Anti-patterns

- ❌ Forgetting `transformIgnorePatterns` — RN packages ship ES modules, Jest barfs without transform.
- ❌ Snapshot tests of full screens — review noise from any layout change.
- ❌ Real native module calls in unit tests — flaky and slow.
- ❌ `getByTestId` everywhere instead of accessible queries.
- ❌ Forgetting `jest.useFakeTimers()` for animation/debounce tests — real timers slow tests by 100x.
- ❌ E2E tests against real backend without seed data or msw — flaky.
- ❌ Mocking the SUT instead of its dependencies.
- ❌ Skipping `beforeEach(() => jest.clearAllMocks())` — state leaks between tests.
- ❌ Mixing Detox and Maestro in same project — pick one e2e tool.
