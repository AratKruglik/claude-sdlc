---
stack: angular
priority: 200
aspects: [frontend]
detect:
  all:
    - file_exists: package.json
    - file_contains:
        path: package.json
        pattern: '"@angular/core"\s*:'
---

# Angular Stack Profile

Angular 18-21 SPA frontend stack provider. Triggers when `package.json` contains `"@angular/core"`. Priority=200 — opinionated full framework (like NestJS). Wins over `react-plugin` / `vue-plugin` (150) on extremely-rare cross-stack projects via priority.

**Targets Angular 17+** with focus on 18-21 modern era (signals stable, standalone-first, new control flow `@if`/`@for`/`@switch`). NgModule legacy projects also covered — agent detects style at runtime and mirrors.

Composes naturally with backend plugins (nodejs / nestjs / laravel) via aspect resolution.

## Agents per phase

- business_analysis: business-analyst        # core agent
- development: angular-architect             # ⚡ Angular-specific
- qa: qa-engineer                            # core agent
- security: security-analyst                 # core agent
- documentation: document-writer             # core agent

## Convention skills to apply

- angular-plugin:angular-conventions
- angular-plugin:angular-state-and-rx
- angular-plugin:angular-routing
- angular-plugin:angular-forms
- angular-plugin:angular-testing
- js-foundation:typescript-patterns
- js-foundation:npm-patterns
- frontend-design:frontend-design  # optional external; skipped automatically when absent

## Extra phases

(none)

## Phase prompts injection

For development phase, inject:
  "Angular SPA project. Detect Angular version from `\"@angular/core\"` semver — 17/18/19/20/21+ → modern signal-first; <17 → legacy NgModule patterns dominate.
   Detect project style:
   - presence of `bootstrapApplication(AppComponent, { providers: [...] })` in `main.ts` + NO `*.module.ts` files → standalone-first.
   - `platformBrowserDynamic().bootstrapModule(AppModule)` in main.ts + `app.module.ts` exists → NgModule legacy.
   - both present → ongoing migration; mirror the area you're touching, prefer standalone for new code in Angular 17+.
   Detect state management:
   - signals (built-in, Angular 17+).
   - `@ngrx/store` + Effects + Selectors → full Redux pattern.
   - `@ngrx/component-store` → per-component reactive store.
   - `@ngrx/signals` → newer signal-based store API.
   - Plain `@Injectable({ providedIn: 'root' })` services → simplest shared state.
   Detect forms approach: `ReactiveFormsModule` import → Reactive Forms (preferred); `FormsModule` only → Template-driven (`[(ngModel)]`).
   Detect SSR: `@angular/ssr` (Angular 17+) or `@nguniversal/express-engine` (older) → Angular Universal present (pointer-only in this plugin; recommend separate spec for full SSR feature).
   Detect UI library: `@angular/material` (Angular Material), `primeng` (PrimeNG), `ng-zorro-antd` (NG-ZORRO), `@taiga-ui/core` (Taiga UI), Bootstrap-based (`@ng-bootstrap/ng-bootstrap`). Mirror its component patterns.
   Detect testing runner: `karma.conf.js` + `karma-jasmine` → Karma+Jasmine (Angular CLI default historically); `jest.config.{js,ts}` + `jest-preset-angular` → Jest (modern preferred).
   New code conventions:
   - Standalone components: `@Component({ standalone: true, imports: [...] })`. No NgModule needed.
   - Use `inject()` function (Angular 14.1+) over constructor injection — type-narrowing-friendly.
   - Use new control flow (`@if`, `@for` with `track`, `@switch`) for Angular 17+ — better perf than `*ngIf`/`*ngFor`/`*ngSwitch`.
   - Use signals (`signal()`, `computed()`, `effect()`) for component state in Angular 17+.
   - Use `input()` / `output()` signal-based APIs (Angular 17.1+) over `@Input()`/`@Output()` for new code where appropriate.
   - Use `takeUntilDestroyed()` (Angular 16+) for RxJS subscription cleanup — replaces manual Subject pattern.
   Apply skills: angular-plugin:angular-conventions, angular-plugin:angular-state-and-rx, angular-plugin:angular-routing, angular-plugin:angular-forms, js-foundation:typescript-patterns, js-foundation:npm-patterns.
   If superpowers is available, invoke superpowers:verification-before-completion before returning."

For qa phase, inject:
  "Angular testing strategy:
   - Detect runner: Karma+Jasmine (`karma.conf.js`) → run `ng test --watch=false`; Jest (`jest.config.{js,ts}` + `jest-preset-angular`) → `npm test` (Jest defaults to single-run in CI mode).
   - TestBed setup: `TestBed.configureTestingModule({ imports: [StandaloneComponent], providers: [...] }).compileComponents()`. For NgModule projects: use `declarations` + `imports`.
   - Mock providers: `{ provide: UsersService, useValue: mock }` or `useFactory: () => mock`.
   - HttpClient testing: `provideHttpClient()` + `provideHttpClientTesting()` + `HttpTestingController` from `@angular/common/http/testing`. Always call `httpMock.verify()` in afterEach to catch outstanding requests.
   - Component harnesses (`@angular/cdk/testing`): query and interact via component-specific APIs (e.g., `MatButtonHarness`); preferred over raw DOM access for Material components.
   - Angular Testing Library (`@testing-library/angular`): RTL-style API (preferred for new tests). `await render(Component, { inputs: {...} })`. Query via `screen.getByRole`/`getByLabelText`.
   - Signal inputs in tests (Angular 17.1+): `componentRef.setInput('name', value)` instead of direct property assignment.
   - NgRx Effects: `provideMockActions(() => actions$)`, dispatch input actions via `actions$.next(action)`, assert outputs via `firstValueFrom(effect$)`.
   - E2E (optional): Cypress (`ng add @cypress/schematic` integrates) or Playwright. Same patterns as react/vue.
   Apply skill: angular-plugin:angular-testing."

For security phase, inject:
  "Angular-specific security checks:
   - Built-in XSS sanitization: Angular auto-escapes interpolations and property bindings. `DomSanitizer.bypassSecurityTrust*` is the escape hatch — flag every usage and verify upstream sanitization (DOMPurify or trusted source).
   - `[innerHTML]` binding goes through Angular's sanitizer by default but still risky for user content; pair with explicit DOMPurify for defense-in-depth.
   - Auth tokens: never localStorage/sessionStorage (XSS-readable). Use httpOnly cookies (server-set) or in-memory service (cleared on logout).
   - `environment.ts` / `environment.prod.ts` files: PUBLIC after build (bundled into JS shipped to browser). Never put secrets there.
   - Angular's strict mode (`tsconfig.json` `\"strict\": true`, `\"strictTemplates\": true`) — verify enabled; catches many real issues.
   - Route guards: every protected route MUST have `canActivate` (functional guard preferred in 17+). Verify auth check is correct.
   - HttpInterceptors for auth: token attached server-side via httpOnly cookie OR added by interceptor from in-memory service. Never read token from storage that's XSS-readable.
   - CSP headers if configurable in deployment (Nginx/CDN level — not Angular-specific).
   - `npm audit`: address Critical/High.
   - Dependency injection: never `provide` a token with `useValue` containing secrets that could leak via Angular DevTools."

## Pre-phase commands

(none)

## Post-pipeline checks

The plugin auto-detects the package manager from the lockfile (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, otherwise npm). `ng test` defaults to watch mode — `--watch=false` flag forces single run for CI/pipeline contexts. `ng build` (Angular Compiler) does AOT compilation, template type-check, DI validation — most valuable single check; plain `tsc --noEmit` cannot validate templates.

- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm test --watch=false 2>/dev/null || pnpm test; elif [ -f yarn.lock ]; then yarn test --watch=false 2>/dev/null || yarn test; else npm test -- --watch=false 2>/dev/null || npm test; fi'
- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm run lint 2>/dev/null || true; elif [ -f yarn.lock ]; then yarn run lint 2>/dev/null || true; else npm run lint --if-present; fi'
- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm run build; elif [ -f yarn.lock ]; then yarn build; else npm run build; fi'
