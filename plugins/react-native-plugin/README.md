# react-native-plugin

React Native mobile stack provider for the [SDLC marketplace](../../README.md).

Adds a React Native-specific implementation agent (`rn-architect`) and 5 skills covering project conventions for both Expo and bare workflows, platform-specific code, navigation (React Navigation v7 + Expo Router), state and storage choices (AsyncStorage / MMKV / SecureStore / Keychain), and testing with Jest + RTL Native plus optional Detox/Maestro e2e. Activates automatically on projects with `react-native` in `package.json`. Highest frontend priority (300) — wins over `react-plugin` (150) on RN projects.

## What this plugin adds

| Component | Purpose |
|---|---|
| `stack.md` | Stack profile, priority=300, aspects=[frontend]. |
| `agents/rn-architect.md` | Developer for React Native (Sonnet implement pass, Opus plan pass). Replaces vanilla `developer` and `react-architect` for RN projects. |
| `skills/rn-conventions/` | Expo vs bare workflow detection, project layouts (Expo Router + classic), `app.json`/`app.config.js`, asset/font handling, styling approaches, Fast Refresh. |
| `skills/rn-platform-specific/` | `Platform.OS`/`Platform.select`, `.ios.tsx`/`.android.tsx` extensions, native modules (autolinking + Expo SDK), permissions, safe area, status bar. |
| `skills/rn-navigation/` | React Navigation v7 (Native Stack / Tabs / Drawer), Expo Router (file-based), typed navigation, deep linking, modal presentation, auth flow. |
| `skills/rn-state-and-storage/` | State libs decision tree (Zustand / Jotai / RTK / TanStack Query / Context), storage by sensitivity (AsyncStorage / MMKV / SecureStore / Keychain), hydration on app start. |
| `skills/rn-testing/` | Jest + jest-expo / RN preset, RTL Native, native module mocking, msw, plus optional Detox (native automation) and Maestro (declarative YAML e2e). |
| `hooks/hooks.json` | Auto-format TS/JS/JSX/TSX/native variants via Prettier + ESLint after Edit/Write (silent if not installed). |

## What it does NOT cover

- **React web** — `react-plugin` (frontend-only).
- **Next.js** — `nextjs-plugin` (multi-aspect, web-focused).
- **Vue** — `vue-plugin`.
- **Backend code** — `nodejs-plugin` / `nestjs-plugin`.
- **React Native Web** — separate compilation target; if a project targets both mobile and web from one codebase, flag in BLOCKERS for guidance per project.
- **Native module authoring** (writing Objective-C/Swift/Java/Kotlin) — out of scope for v0.0.1; agent prompts user toward Expo config plugins where possible.
- **EAS Build / App Store / Play Store deployment** — pipeline focuses on code, not deploy.

## Cross-plugin skill reuse

`react-native-plugin` declares `dependencies: ["sdlc", "js-foundation"]` in `plugin.json` — Claude Code auto-installs `js-foundation` when you install this. The stack profile references skills from both plugins in `convention_skills`:

- `js-foundation:typescript-patterns` — strict TypeScript discipline.
- `js-foundation:npm-patterns` — package manager detection, semver, lockfile hygiene.
- `react-native-plugin:rn-conventions` — workflow detection, project structure, asset handling.
- `react-native-plugin:rn-platform-specific` — iOS/Android branching.
- `react-native-plugin:rn-navigation` — React Navigation + Expo Router.
- `react-native-plugin:rn-state-and-storage` — state libs + native storage.
- `react-native-plugin:rn-testing` — Jest + RTL Native + optional e2e.

## Installation

```
/plugin marketplace add AratKruglik/claude-sdlc
/plugin install react-native-plugin@sdlc-marketplace
```

`sdlc` core and `js-foundation` install automatically as dependencies.

## Usage

On any React Native project (Expo OR bare), the plugin activates automatically:

```
/sdlc:start "Add user profile screen with avatar upload"
```

The orchestrator detects the RN stack profile, claims the `frontend` aspect, and dispatches `rn-architect` for the development phase. All other phases (BA, QA, Security, Docs) use the core agents.

## Verification

```
/sdlc:list-stacks
```

Should show `react-native priority=300` with active match (frontend) on an RN project. If `react` is also in deps (always is, since RN depends on React), `react-plugin` shows as no-match-loser (300 > 150).

```
/sdlc:doctor
```

Confirms 6 plugins installed (sdlc + nodejs-plugin + nestjs-plugin + nextjs-plugin + react-plugin + react-native-plugin), no degraded mode warnings.

## Composition with other plugins

`react-native-plugin` is mobile-only — claims `frontend` aspect. Typical RN apps are standalone mobile (no co-resident backend in the same package.json). For RN + Node.js API monorepos:

- `apps/mobile/package.json` (RN) — only `react-native-plugin` detects.
- `apps/api/package.json` (Node.js / NestJS) — backend plugin detects.

The orchestrator runs per-cwd, so each app gets the right architect.

## Detection edge cases

| Condition | Outcome |
|---|---|
| `package.json` has `react-native` + `react` | `react-native-plugin` (300) wins frontend. `react-plugin` (150) loses via priority. |
| `package.json` has `react-native` + `expo` | `react-native-plugin` wins. Agent detects Expo workflow at runtime (managed/dev-client/EAS). |
| `package.json` has `react-native` + `next` | `nextjs-plugin` (250) tries to win backend AND frontend. `react-native-plugin` (300) wins frontend; nextjs takes backend. Unusual configuration — likely RN + Next.js Web monorepo with shared deps. |
| Pure web React | `react-native` not in deps; `react-plugin` (150) wins frontend. |

## Workflow detection (Expo vs bare)

The agent detects at runtime:

| Markers | Workflow |
|---|---|
| `expo` in deps + `app.json` / `app.config.{js,ts}` + NO `ios/` `android/` folders | Expo managed |
| `expo` + `expo-dev-client` in deps | Expo dev-client (custom native code via prebuild) |
| `eas.json` present | EAS Build (managed or dev-client built in cloud) |
| `expo` in deps + `ios/` + `android/` folders | Expo ejected (treat as bare) |
| No `expo`, `ios/` + `android/` folders | Bare RN |

## Package manager detection

`post_pipeline_checks` auto-detect from lockfile:

| Lockfile present | Runner used |
|---|---|
| `pnpm-lock.yaml` | `pnpm test`, `pnpm run lint` |
| `yarn.lock` | `yarn test`, `yarn run lint` |
| (default) | `npm test`, `npm run lint --if-present` |

NOTE: NO `npm run build` — RN builds require Xcode (iOS) and Android SDK and are NOT run in pipeline. `npx --no-install tsc --noEmit` is the type-check safety net instead.

For real device/simulator testing, use platform-specific tools outside the pipeline:
- iOS: `npm run ios` / `expo start --ios` / EAS Build artifact in TestFlight.
- Android: `npm run android` / `expo start --android` / EAS Build → `.aab` to internal track.

The `rn-architect` agent applies the same package-manager detection for any install/script invocations during development.

## Local override

To customize per-project (e.g., custom monorepo runners like Nx/Turborepo, alternate test scripts, skip security phase if external SAST handles it), create `.claude/sdlc.local.yaml` in the project root and set `post_pipeline_checks` explicitly. Recognized top-level keys: `post_pipeline_checks` (replaces plugin defaults), `phase_command_overrides` (passed as context to agents), `extra_phase_prompts` (appends per-phase guidance), `skip_phases`, `convention_skills_extra`.

## Coverage scope (v0.0.1)

This plugin covers the **full RN surface** — both Expo (managed/dev-client/EAS/ejected) and bare workflows, both navigation systems (React Navigation v7 + Expo Router), all four storage choices (AsyncStorage / MMKV / SecureStore / Keychain), state libs from the React ecosystem, react-hook-form, Jest + RTL Native testing.

E2E coverage (Detox + Maestro) is documented in `rn-testing` skill as **optional** sections — applied only when the project has those tools installed. Both require Xcode / Android SDK and are not pipeline operations.

The agent detects what's installed (workflow type, navigation lib, storage choice, state lib) and applies matching patterns rather than imposing one opinionated stack.

Smoke testing (end-to-end pipeline run on a real RN fixture) is deferred — needs Xcode/Android SDK for full validation. Verification in v0.0.1 is limited to schema/structure validation via `/sdlc:list-stacks`, `/sdlc:doctor`, and GitHub Actions lint.
