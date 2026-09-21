---
name: react-testing
description: |
  Testing React SPAs: React Testing Library + Vitest/Jest for components and hooks, msw for network mocks, Playwright/Cypress for e2e. Query priority, user events, async assertions, mocking patterns.

  Use this skill to:
  - Pick the right runner (Vitest vs Jest) and setup.
  - Write component tests with RTL using accessible queries.
  - Test custom hooks via renderHook.
  - Mock network with msw at the boundary.
  - Set up Playwright or Cypress for end-to-end coverage.

  Do NOT use this skill for:
  - General React conventions (see react-conventions).
  - State management testing patterns specific to a store lib (see react-state-management).
  - Form-specific testing (apply react-forms patterns inside test).
user-invocable: false
paths: ["**/*.test.{ts,tsx,js,jsx}", "src/**/__tests__/**"]
---

# React Testing Patterns

## Test framework selection

| Layer | Framework |
|---|---|
| Component, hook, plain TS unit | **Vitest** (preferred for new) or **Jest** |
| End-to-end | **Playwright** or **Cypress** |

Match what's installed. Vitest is the modern default for Vite projects; Jest is common in CRA / older setups.

## Vitest setup

`vitest.config.ts`:

```ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./vitest.setup.ts'],
    css: true,
    coverage: {
      reporter: ['text', 'html'],
      exclude: ['**/*.config.*', '**/*.test.*', 'src/main.tsx'],
    },
  },
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
});
```

`vitest.setup.ts`:

```ts
import '@testing-library/jest-dom/vitest';
import { afterEach } from 'vitest';
import { cleanup } from '@testing-library/react';

afterEach(() => cleanup());
```

Install: `pnpm add -D vitest @vitejs/plugin-react jsdom @testing-library/react @testing-library/user-event @testing-library/jest-dom`.

## Jest setup

`jest.config.ts`:

```ts
import type { Config } from 'jest';

const config: Config = {
  preset: 'ts-jest',
  testEnvironment: 'jsdom',
  setupFilesAfterEach: ['<rootDir>/jest.setup.ts'],
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
    '\\.(css|scss|less)$': 'identity-obj-proxy',
  },
};
export default config;
```

`jest.setup.ts`:

```ts
import '@testing-library/jest-dom';
```

## Component test (RTL basics)

```tsx
// src/features/users/UserCard.test.tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { UserCard } from './UserCard';

describe('UserCard', () => {
  it('renders user name and email', () => {
    render(<UserCard user={{ id: '1', name: 'Alice', email: 'a@b.c' }} />);
    expect(screen.getByRole('heading', { name: 'Alice' })).toBeInTheDocument();
    expect(screen.getByText('a@b.c')).toBeInTheDocument();
  });

  it('calls onDelete when delete button clicked', async () => {
    const onDelete = vi.fn();
    const user = userEvent.setup();
    render(<UserCard user={{ id: '1', name: 'Alice', email: 'a@b.c' }} onDelete={onDelete} />);
    await user.click(screen.getByRole('button', { name: /delete/i }));
    expect(onDelete).toHaveBeenCalledWith('1');
  });
});
```

### Query priority (USE THIS ORDER)

1. `getByRole(role, { name })` — accessible name. Mirrors how screen readers see the page.
2. `getByLabelText` — for form inputs.
3. `getByPlaceholderText` — fallback for inputs without label.
4. `getByText` — for non-interactive text.
5. `getByDisplayValue` — for inputs with current value.
6. `getByAltText` — for images.
7. `getByTitle` — for elements with title attribute.
8. `getByTestId` — last resort, when nothing else works.

`getBy*` throws if not found. `queryBy*` returns null. `findBy*` is async (returns promise that retries).

```tsx
expect(screen.queryByText('Loading...')).not.toBeInTheDocument(); // assert absence
expect(await screen.findByText('Loaded')).toBeInTheDocument();    // wait for async
```

### User events (ALWAYS prefer over fireEvent)

```ts
import userEvent from '@testing-library/user-event';

const user = userEvent.setup();
await user.click(button);
await user.type(input, 'hello');
await user.selectOptions(select, 'option-value');
await user.upload(input, file);
await user.tab();                              // keyboard navigation
await user.keyboard('{Enter}');
```

`fireEvent` is lower-level and skips realistic event sequences (mousedown→mouseup→click). Stick to `user-event`.

## Testing hooks

```tsx
// src/hooks/useDebounce.test.ts
import { describe, it, expect, vi } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useDebounce } from './useDebounce';

describe('useDebounce', () => {
  it('returns the latest value after delay', async () => {
    vi.useFakeTimers();
    const { result, rerender } = renderHook(({ value }) => useDebounce(value, 300), {
      initialProps: { value: 'a' },
    });
    expect(result.current).toBe('a');

    rerender({ value: 'b' });
    expect(result.current).toBe('a'); // not yet debounced

    act(() => {
      vi.advanceTimersByTime(300);
    });
    expect(result.current).toBe('b');

    vi.useRealTimers();
  });
});
```

## Network mocking with msw

```ts
// vitest.setup.ts
import { setupServer } from 'msw/node';
import { http, HttpResponse } from 'msw';
import { afterAll, afterEach, beforeAll } from 'vitest';

const server = setupServer(
  http.get('/api/users', () => HttpResponse.json([{ id: '1', name: 'Alice' }])),
  http.post('/api/users', async ({ request }) => {
    const body = await request.json();
    return HttpResponse.json({ id: '2', ...body }, { status: 201 });
  }),
);

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

export { server };
```

Per-test override:

```ts
import { http, HttpResponse } from 'msw';
import { server } from '../vitest.setup';

it('shows error on 500', async () => {
  server.use(http.get('/api/users', () => HttpResponse.json({ error: 'oops' }, { status: 500 })));
  render(<UsersPage />);
  expect(await screen.findByText(/error/i)).toBeInTheDocument();
});
```

## Testing components that use TanStack Query

```tsx
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render } from '@testing-library/react';

function renderWithQuery(ui: React.ReactElement) {
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false } },          // don't retry in tests
  });
  return render(<QueryClientProvider client={qc}>{ui}</QueryClientProvider>);
}

it('shows users from API', async () => {
  renderWithQuery(<UsersList />);
  expect(await screen.findByText('Alice')).toBeInTheDocument();
});
```

## Testing routing (React Router)

```tsx
import { MemoryRouter, Routes, Route } from 'react-router-dom';

it('navigates to user detail', async () => {
  const user = userEvent.setup();
  render(
    <MemoryRouter initialEntries={['/users']}>
      <Routes>
        <Route path="/users" element={<UsersList />} />
        <Route path="/users/:id" element={<UserDetail />} />
      </Routes>
    </MemoryRouter>
  );

  await user.click(screen.getByRole('link', { name: 'Alice' }));
  expect(await screen.findByText('User Detail: 1')).toBeInTheDocument();
});
```

For data routers (with `loader` etc.), use `createMemoryRouter` and `RouterProvider`.

## Testing forms (react-hook-form)

```tsx
it('shows validation errors and submits valid data', async () => {
  const onSubmit = vi.fn();
  const user = userEvent.setup();
  render(<LoginForm onSubmit={onSubmit} />);

  // Submit empty
  await user.click(screen.getByRole('button', { name: /log in/i }));
  expect(await screen.findByText(/invalid email/i)).toBeInTheDocument();
  expect(onSubmit).not.toHaveBeenCalled();

  // Fill correctly
  await user.type(screen.getByLabelText(/email/i), 'a@b.c');
  await user.type(screen.getByLabelText(/password/i), 'longenough');
  await user.click(screen.getByRole('button', { name: /log in/i }));

  await waitFor(() => {
    expect(onSubmit).toHaveBeenCalledWith({ email: 'a@b.c', password: 'longenough' });
  });
});
```

## Playwright e2e

`playwright.config.ts`:

```ts
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:5173',
    reuseExistingServer: !process.env.CI,
  },
  use: { baseURL: 'http://localhost:5173', trace: 'on-first-retry' },
  projects: [
    { name: 'chromium', use: { browserName: 'chromium' } },
  ],
});
```

```ts
// e2e/login.spec.ts
import { test, expect } from '@playwright/test';

test('user can log in', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel(/email/i).fill('a@b.c');
  await page.getByLabel(/password/i).fill('longenough');
  await page.getByRole('button', { name: /log in/i }).click();
  await expect(page).toHaveURL('/dashboard');
  await expect(page.getByRole('heading', { name: /welcome/i })).toBeVisible();
});
```

## Cypress e2e (alternative)

```ts
// cypress/e2e/login.cy.ts
describe('login', () => {
  it('user can log in', () => {
    cy.visit('/login');
    cy.get('[name=email]').type('a@b.c');
    cy.get('[name=password]').type('longenough');
    cy.contains('button', 'Log in').click();
    cy.url().should('include', '/dashboard');
  });
});
```

Cypress feels more "live" (interactive runner) but each test is browser-resident, slower at scale than Playwright.

## Coverage discipline

Target ≥80% on:
- Custom hooks.
- Components with logic (state, conditional rendering).
- Utility functions.

Skip / lower bar:
- Pure presentational components (snapshot churn outweighs value).
- Wiring code (route definitions, store setup).
- `main.tsx`.

Configure exclusions:

```ts
// vitest.config.ts
test: {
  coverage: {
    exclude: [
      'src/main.tsx',
      'src/App.tsx',
      '**/*.config.*',
      '**/types.ts',
      '**/*.stories.tsx',
    ],
  },
}
```

## Iteration cap (from QA agent)

The qa-engineer agent has a hard 3-attempt cap on fixing failing tests. Mark genuinely flaky tests `it.skip(...)` with a comment after attempt #3, and report in the QA summary.

## Anti-patterns

- ❌ `getByTestId` everywhere instead of accessible queries.
- ❌ `fireEvent` for interactions when `userEvent` would be more realistic.
- ❌ Stubbing `fetch` directly when msw exists in the project.
- ❌ Snapshot tests of large component trees — review noise.
- ❌ Testing implementation details (CSS classes, internal state).
- ❌ Forgetting `act()` warnings — they signal real issues with async state updates.
- ❌ E2E tests that depend on real backend without `webServer` config or seed data.
- ❌ `setTimeout` waits in tests — use `findBy*` (which retries) or `waitFor`.
- ❌ Mocking the SUT instead of its dependencies.
