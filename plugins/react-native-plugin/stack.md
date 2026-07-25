---
stack: react-native
priority: 300
aspects: [frontend]
detect:
  all:
    - file_exists: package.json
    - file_contains:
        path: package.json
        pattern: '"react-native"\s*:'
---

# React Native Stack Profile

Mobile (iOS + Android) stack provider. Triggers when `package.json` contains `"react-native"`. Highest frontend priority (300) — wins over `react-plugin` (150) and any other frontend plugin on React Native projects via aspect resolution.

Supports BOTH workflows:
- **Expo** (managed / dev-client / EAS-built) — `app.json` / `app.config.{js,ts}` + `expo` in deps. Modern default for new RN projects (2024+).
- **Bare** — `ios/` + `android/` folders, React Native CLI. Common for legacy and apps with custom native modules.

The agent detects the workflow at runtime and applies matching patterns.

## Agents per phase

- business_analysis: business-analyst        # core agent
- development: rn-architect                  # ⚡ React Native-specific
- qa: qa-engineer                            # core agent
- security: security-analyst                 # core agent
- documentation: document-writer             # core agent

## Convention skills to apply

- react-native-plugin:rn-conventions
- react-native-plugin:rn-platform-specific
- react-native-plugin:rn-navigation
- react-native-plugin:rn-state-and-storage
- react-native-plugin:rn-testing
- js-foundation:typescript-patterns
- js-foundation:npm-patterns
- frontend-design:frontend-design  # optional external; skipped automatically when absent

## Extra phases

(none)

## Phase prompts injection

For development phase, inject:
  "React Native mobile project. Detect workflow:
   - Expo managed: `expo` in deps + `app.json` or `app.config.{js,ts}` present + NO `ios/`/`android/` folders.
   - Expo dev-client / EAS: `expo` in deps + `expo-dev-client` and/or `eas.json` present.
   - Bare RN: `ios/` and `android/` folders present, no `expo` in deps.
   - Expo ejected (bare via expo eject): `ios/`/`android/` AND `expo` still in deps — treat as bare.
   Detect navigation: `@react-navigation/native` + stack/tab/drawer subpackages → React Navigation v7; `expo-router` → file-based routing (Expo 49+).
   Detect storage choice: `@react-native-async-storage/async-storage` (non-secure), `react-native-mmkv` (fast/sync), `expo-secure-store` (Keychain/EncryptedSharedPreferences), `react-native-keychain` (bare alt). Match what's installed.
   Platform-specific code via `Platform.OS` + `.ios.tsx`/`.android.tsx`/`.native.tsx`/`.web.tsx` (Metro picks correct file).
   Never use web-only APIs (`window`, `document`, `localStorage`, `sessionStorage`).
   Image assets via `require('./assets/icon.png')` with proper resolution — RN bundler handles @2x/@3x suffixes automatically.
   For Expo managed: don't edit `ios/` or `android/` directly — use `app.config.js` config plugins.
   Apply skills: react-native-plugin:rn-conventions, react-native-plugin:rn-platform-specific, react-native-plugin:rn-navigation, react-native-plugin:rn-state-and-storage, js-foundation:typescript-patterns, js-foundation:npm-patterns.
   If superpowers is available, invoke superpowers:verification-before-completion before returning."

For qa phase, inject:
  "React Native testing strategy:
   - Detect Jest preset: `jest-expo` (Expo) or `react-native` (bare). Configure `transformIgnorePatterns` for ESM-shipping RN packages.
   - Use `@testing-library/react-native` for component tests. Query priority: getByRole > getByLabelText > getByText > getByTestId. Note: getByRole has weaker role mappings on RN than web.
   - Mock native modules: `jest.mock('react-native-mmkv', ...)`, common mocks for `react-native-reanimated`, `react-native-gesture-handler`, `expo-*` modules.
   - Hooks via `renderHook` from `@testing-library/react-native` (RN 0.71+) or `@testing-library/react-hooks` (legacy).
   - Snapshot tests: high churn — use sparingly. Prefer inline snapshots for review clarity.
   - msw for API mocks: requires jsdom polyfill in jest-expo config.
   - E2E (optional, only if installed): Detox for native automation; Maestro for declarative YAML flows. Both require Xcode/Android SDK.
   Apply skill: react-native-plugin:rn-testing."

For security phase, inject:
  "React Native-specific security checks:
   - Secrets: SecureStore (`expo-secure-store`) or Keychain (`react-native-keychain`) — NOT AsyncStorage (plaintext on disk, readable by malicious apps with root/jailbreak).
   - JWT / refresh tokens: SecureStore only.
   - Deep link validation: verify URL scheme matches expected pattern; sanitize params before navigation. Universal Links / App Links require domain verification (apple-app-site-association, assetlinks.json).
   - SSL pinning for production: react-native-ssl-pinning or platform-specific. Mandatory for sensitive apps (banking, health).
   - Biometric auth: `expo-local-authentication` (managed) or `react-native-biometrics` (bare). Use for sensitive actions, not as primary auth.
   - Build-time env: `react-native-config` (bare) or Expo `extra` field — never hardcode secrets in source.
   - Code obfuscation: ProGuard (Android) and Hermes minification — verify enabled in production builds.
   - Insecure deserialization: validate JSON from server before passing to navigation params or state.
   - npm audit: run and address Critical/High."

## Pre-phase commands

(none)

## Post-pipeline checks

The plugin auto-detects the package manager from the lockfile (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, otherwise npm). NO `npm run build` — RN builds require Xcode/Android SDK and are not run in pipeline. `tsc --noEmit` provides the build-equivalent type-check safety net.

- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm test; elif [ -f yarn.lock ]; then yarn test; else npm test; fi'
- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm run lint 2>/dev/null || true; elif [ -f yarn.lock ]; then yarn run lint 2>/dev/null || true; else npm run lint --if-present; fi'
- npx --no-install tsc --noEmit
