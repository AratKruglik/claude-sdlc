---
name: angular-testing
description: |
  Testing Angular 18-21: TestBed, component harnesses (@angular/cdk/testing), Karma+Jasmine (default historical) vs Jest (jest-preset-angular, modern), Angular Testing Library (RTL-style). HttpClient mocking via HttpTestingController. NgRx Effects testing. Cypress / Playwright e2e.

  Use this skill to:
  - Detect runner (Karma+Jasmine vs Jest) and configure correctly.
  - Write component tests with TestBed.
  - Use component harnesses for Material / custom UI components.
  - Mock HttpClient via provideHttpClientTesting + HttpTestingController.
  - Test signal-based inputs with componentRef.setInput().
  - Test NgRx Effects with provideMockActions.

  Do NOT use this skill for:
  - General Angular conventions (see angular-conventions).
  - Routing patterns broadly (see angular-routing — covers testing routes briefly).
  - Form patterns broadly (see angular-forms).
user-invocable: false
paths: ["**/*.spec.ts", "src/**/*.ts"]
---

# Angular Testing

## Test framework selection

| Layer | Framework |
|---|---|
| Component, service, pipe, directive unit | **Karma + Jasmine** (Angular CLI default historically) OR **Jest** (`jest-preset-angular`, modern preferred) |
| Component (alt RTL-style) | `@testing-library/angular` |
| End-to-end | **Playwright** or **Cypress** (`ng add @cypress/schematic`) |

Match what's installed. Modern Angular projects (17+) often switch to Jest for speed; legacy projects stick with Karma.

## Karma + Jasmine setup (default)

`ng new` ships with Karma + Jasmine pre-configured. Tests in `*.spec.ts`. Run via `ng test` (watch mode) or `ng test --watch=false --browsers=ChromeHeadless` (CI).

`karma.conf.js` and `tsconfig.spec.json` already in project. Don't modify unless customizing.

## Jest setup (modern)

```bash
pnpm add -D jest jest-preset-angular @types/jest
```

`jest.config.ts`:

```ts
import type { Config } from 'jest';

const config: Config = {
  preset: 'jest-preset-angular',
  setupFilesAfterEach: ['<rootDir>/setup-jest.ts'],
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
  },
  testPathIgnorePatterns: ['/node_modules/', '/dist/'],
};

export default config;
```

`setup-jest.ts`:

```ts
import 'jest-preset-angular/setup-jest';
```

Update `tsconfig.spec.json`:

```json
{
  "extends": "./tsconfig.json",
  "compilerOptions": {
    "types": ["jest", "node"]
  }
}
```

In `package.json`:

```json
"scripts": {
  "test": "jest"
}
```

Remove Karma config / packages from `devDependencies` (cleanup), or keep both temporarily during migration.

## TestBed basics

```ts
import { TestBed, ComponentFixture } from '@angular/core/testing';
import { UserCardComponent } from './user-card.component';

describe('UserCardComponent', () => {
  let fixture: ComponentFixture<UserCardComponent>;
  let component: UserCardComponent;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [UserCardComponent],         // standalone — import the component itself
    }).compileComponents();

    fixture = TestBed.createComponent(UserCardComponent);
    component = fixture.componentInstance;
  });

  it('renders user name', () => {
    component.user = { id: '1', name: 'Alice', email: 'a@b.c' };
    fixture.detectChanges();
    expect(fixture.nativeElement.textContent).toContain('Alice');
  });
});
```

For NgModule projects: `TestBed.configureTestingModule({ declarations: [UserCardComponent], imports: [...required modules...] })`.

`fixture.detectChanges()` triggers Angular's change detection — re-render with current state. Required after any input/state change.

### Signal-based inputs (Angular 17.1+)

```ts
beforeEach(async () => {
  await TestBed.configureTestingModule({ imports: [UserCardComponent] }).compileComponents();
  fixture = TestBed.createComponent(UserCardComponent);
});

it('renders user name from signal input', () => {
  fixture.componentRef.setInput('user', { id: '1', name: 'Alice', email: 'a@b.c' });
  fixture.detectChanges();
  expect(fixture.nativeElement.textContent).toContain('Alice');
});
```

`componentRef.setInput('name', value)` is the correct way to set signal-based inputs. Direct `component.user = ...` won't trigger reactivity.

## Mocking dependencies

```ts
const mockUsersService = {
  loadUsers: jest.fn().mockResolvedValue(undefined),
  users: signal([{ id: '1', name: 'Alice' }]),
  loading: signal(false),
};

beforeEach(async () => {
  await TestBed.configureTestingModule({
    imports: [UsersListComponent],
    providers: [
      { provide: UsersService, useValue: mockUsersService },
    ],
  }).compileComponents();
});
```

`useValue` swaps the real service with a mock. `useFactory: () => mock` for factory-style.

For Karma+Jasmine: replace `jest.fn()` with `jasmine.createSpy('name')` or `jasmine.createSpyObj('UsersService', ['loadUsers'])`.

## HttpClient testing

```ts
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting, HttpTestingController } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { UsersService } from './users.service';

describe('UsersService', () => {
  let service: UsersService;
  let httpMock: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
      ],
    });

    service = TestBed.inject(UsersService);
    httpMock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    httpMock.verify();                       // assert no outstanding requests
  });

  it('fetches users', () => {
    let result: User[] | undefined;
    service.loadUsers().subscribe((users) => (result = users));

    const req = httpMock.expectOne('/api/users');
    expect(req.request.method).toBe('GET');
    req.flush([{ id: '1', name: 'Alice', email: 'a@b.c' }]);

    expect(result).toEqual([{ id: '1', name: 'Alice', email: 'a@b.c' }]);
  });

  it('handles error', () => {
    let error: any;
    service.loadUsers().subscribe({
      error: (err) => (error = err),
    });

    const req = httpMock.expectOne('/api/users');
    req.error(new ProgressEvent('Network error'), { status: 500 });

    expect(error).toBeDefined();
  });
});
```

`httpMock.verify()` in `afterEach` fails the test if any HTTP requests were made but not handled — catches accidental real network calls.

## Component harnesses (`@angular/cdk/testing`)

For Material UI (or custom components with harnesses):

```ts
import { HarnessLoader } from '@angular/cdk/testing';
import { TestbedHarnessEnvironment } from '@angular/cdk/testing/testbed';
import { MatButtonHarness } from '@angular/material/button/testing';
import { MatInputHarness } from '@angular/material/input/testing';

describe('LoginComponent', () => {
  let fixture: ComponentFixture<LoginComponent>;
  let loader: HarnessLoader;

  beforeEach(async () => {
    await TestBed.configureTestingModule({ imports: [LoginComponent] }).compileComponents();
    fixture = TestBed.createComponent(LoginComponent);
    loader = TestbedHarnessEnvironment.loader(fixture);
  });

  it('logs in on submit', async () => {
    const emailInput = await loader.getHarness(MatInputHarness.with({ selector: '[formControlName="email"]' }));
    await emailInput.setValue('a@b.c');

    const submitBtn = await loader.getHarness(MatButtonHarness.with({ text: /Log in/i }));
    await submitBtn.click();

    fixture.detectChanges();
    expect(/* assert post-submit state */);
  });
});
```

Harnesses provide stable APIs that survive Material upgrades — preferred over `By.css('.mat-button')` queries.

For custom components, write your own harness extending `ComponentHarness`. See Material docs.

## Angular Testing Library (RTL-style)

```bash
pnpm add -D @testing-library/angular @testing-library/jest-dom
```

```ts
import { render, screen } from '@testing-library/angular';
import { UserCardComponent } from './user-card.component';

it('renders user name', async () => {
  await render(UserCardComponent, {
    inputs: { user: { id: '1', name: 'Alice', email: 'a@b.c' } },
  });

  expect(screen.getByText('Alice')).toBeInTheDocument();
});

it('emits delete on click', async () => {
  const deleteSpy = jest.fn();
  await render(UserCardComponent, {
    inputs: { user: { id: '1', name: 'Alice', email: 'a@b.c' } },
    on: { delete: deleteSpy },
  });

  const button = screen.getByRole('button', { name: /delete/i });
  await userEvent.click(button);

  expect(deleteSpy).toHaveBeenCalledWith('1');
});
```

Same query priority as React/Vue Testing Library: `getByRole` > `getByLabelText` > `getByText` > `getByTestId`.

For new tests in modern Angular projects, RTL-style is often cleaner than raw TestBed + DOM queries.

## NgRx Effects testing

```bash
pnpm add -D @ngrx/effects @ngrx/store
```

```ts
import { Actions } from '@ngrx/effects';
import { provideMockActions } from '@ngrx/effects/testing';
import { TestBed } from '@angular/core/testing';
import { Observable, of, throwError } from 'rxjs';
import { UsersEffects } from './users.effects';
import { UsersActions } from './users.actions';

describe('UsersEffects', () => {
  let actions$: Observable<any>;
  let effects: UsersEffects;
  let mockHttp: { get: jest.Mock };

  beforeEach(() => {
    mockHttp = { get: jest.fn() };

    TestBed.configureTestingModule({
      providers: [
        UsersEffects,
        provideMockActions(() => actions$),
        { provide: HttpClient, useValue: mockHttp },
      ],
    });

    effects = TestBed.inject(UsersEffects);
  });

  it('loadUsers$ → loadUsersSuccess on HTTP success', (done) => {
    const users = [{ id: '1', name: 'Alice' }];
    mockHttp.get.mockReturnValue(of(users));

    actions$ = of(UsersActions.loadUsers());

    effects.loadUsers$.subscribe((action) => {
      expect(action).toEqual(UsersActions.loadUsersSuccess({ users }));
      done();
    });
  });

  it('loadUsers$ → loadUsersFailure on HTTP error', (done) => {
    mockHttp.get.mockReturnValue(throwError(() => new Error('Network down')));

    actions$ = of(UsersActions.loadUsers());

    effects.loadUsers$.subscribe((action) => {
      expect(action).toEqual(UsersActions.loadUsersFailure({ error: 'Network down' }));
      done();
    });
  });
});
```

`provideMockActions(() => actions$)` lets you control the input action stream. Effects fire when `actions$` emits a matching action.

## NgRx Store testing

```ts
import { provideMockStore, MockStore } from '@ngrx/store/testing';

beforeEach(() => {
  TestBed.configureTestingModule({
    imports: [UsersListComponent],
    providers: [
      provideMockStore({
        initialState: { users: { items: [{ id: '1', name: 'Alice' }], loading: false, error: null } },
        selectors: [
          { selector: selectUserCount, value: 1 },
        ],
      }),
    ],
  });

  store = TestBed.inject(MockStore);
});

it('renders user list from store', () => {
  fixture.detectChanges();
  expect(fixture.nativeElement.textContent).toContain('Alice');
});

it('overrides selector value', () => {
  store.overrideSelector(selectUserCount, 5);
  store.refreshState();
  expect(/* assert based on count = 5 */);
});
```

## Cypress / Playwright e2e

### Cypress (`ng add @cypress/schematic`)

```ts
// cypress/e2e/login.cy.ts
describe('login', () => {
  it('user can log in', () => {
    cy.visit('/login');
    cy.get('[formControlName=email]').type('a@b.c');
    cy.get('[formControlName=password]').type('longenough');
    cy.contains('button', /log in/i).click();
    cy.url().should('include', '/dashboard');
    cy.contains('Welcome').should('be.visible');
  });
});
```

### Playwright

```ts
// playwright.config.ts
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  webServer: {
    command: 'ng serve',
    url: 'http://localhost:4200',
    reuseExistingServer: !process.env.CI,
  },
  use: { baseURL: 'http://localhost:4200', trace: 'on-first-retry' },
});

// e2e/login.spec.ts
import { test, expect } from '@playwright/test';

test('user can log in', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel(/email/i).fill('a@b.c');
  await page.getByLabel(/password/i).fill('longenough');
  await page.getByRole('button', { name: /log in/i }).click();
  await expect(page).toHaveURL(/\/dashboard/);
});
```

## Coverage discipline

Target ≥80% on:
- Services (state holders, HTTP wrappers).
- Pipes / directives with logic.
- Components with conditional rendering or event handling.
- NgRx reducers, selectors, effects.

Skip / lower bar:
- Pure presentational components (snapshot churn outweighs value).
- `app.module.ts` / `*.routes.ts` (configuration).
- `main.ts` (bootstrap).

Karma config:
```js
codeCoverage: { include: ['src/**/*.ts'], exclude: ['src/main.ts', 'src/**/*.module.ts', '**/*.spec.ts'] }
```

Jest config:
```ts
coveragePathIgnorePatterns: ['/node_modules/', '\\.module\\.ts$', 'src/main.ts']
```

## Iteration cap (from QA agent)

The qa-engineer agent has a hard 3-attempt cap on fixing failing tests. After attempt #3, mark `xit(...)` (Jasmine) or `it.skip(...)` (Jest) with a comment, report in QA summary.

## Anti-patterns

- ❌ Forgetting `httpMock.verify()` in `afterEach` — leaves outstanding requests undetected.
- ❌ Setting signal-based inputs via property assignment (`component.user = X`) instead of `componentRef.setInput()`.
- ❌ Forgetting `fixture.detectChanges()` after state changes — assertions see stale DOM.
- ❌ Testing private methods (test public surface — props in, emits out, rendered DOM).
- ❌ `getByTestId` everywhere instead of accessible queries.
- ❌ Real network calls in unit tests (slow, flaky) — use `provideHttpClientTesting`.
- ❌ Snapshot tests of large component trees — review noise.
- ❌ E2E tests against real backend without seed/mocked endpoints.
- ❌ Mocking the SUT instead of its dependencies.
- ❌ Karma `--watch=true` in CI — tests hang waiting for changes.
- ❌ Mixing `jasmine.createSpy()` and `jest.fn()` in the same project — pick one runner.
