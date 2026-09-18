---
name: nextjs-testing
description: |
  Testing strategies for Next.js: Server Components, Client Components, Server Actions, Route Handlers, end-to-end with Playwright. Vitest/Jest configuration, React Testing Library patterns, msw for network mocks.

  Use this skill to:
  - Pick the right test layer for what you're testing.
  - Configure Vitest or Jest for Next.js.
  - Test Server Components without running them in isolation.
  - Test Server Actions and Route Handlers as pure functions.
  - Set up Playwright for e2e and integration of RSC.

  Do NOT use this skill for:
  - General Next.js conventions (see nextjs-conventions).
  - RSC vs Client model (see server-component-patterns).
  - Plain Node.js test patterns (see nodejs-plugin equivalents).
user-invocable: false
paths: ["**/*.test.{ts,tsx}", "**/*.spec.{ts,tsx}", "e2e/**"]
---

# Next.js Testing Patterns

Next.js testing splits along the same line as the runtime: server-side code runs in Node, client-side in jsdom or a browser. The right tool depends on the layer.

## Test framework selection

| Layer | Framework |
|---|---|
| Client Components, hooks, plain JS/TS units | **Vitest** (preferred for new projects) or **Jest** |
| Server Components | **Playwright** integration tests OR Vitest with the right config |
| Server Actions | **Vitest** (treat the action body as a pure function — extract logic) |
| Route Handlers | **Vitest** with mocked `NextRequest` |
| End-to-end (full stack) | **Playwright** (Vercel-recommended) or **Cypress** |

For new projects, prefer Vitest + Playwright. Match what exists otherwise.

## Vitest setup for Next.js

`vitest.config.ts`:

```ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./vitest.setup.ts'],
    globals: true,
    css: true,
  },
  resolve: {
    alias: { '@': path.resolve(__dirname, './') },
  },
});
```

`vitest.setup.ts`:

```ts
import '@testing-library/jest-dom/vitest';
```

Install: `pnpm add -D vitest @vitejs/plugin-react jsdom @testing-library/react @testing-library/jest-dom @testing-library/user-event`.

## Testing Client Components (RTL)

```tsx
// app/users/_components/UserFilter.test.tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { UserFilter } from './UserFilter';

describe('UserFilter', () => {
  it('calls onChange as user types', async () => {
    const onChange = vi.fn();
    const user = userEvent.setup();
    render(<UserFilter onChange={onChange} />);

    await user.type(screen.getByRole('textbox'), 'alice');

    expect(onChange).toHaveBeenLastCalledWith('alice');
  });
});
```

Query priority: `getByRole` > `getByLabelText` > `getByText` > `getByTestId` (last resort). Roles match how assistive tech sees the UI.

## Testing Server Components

Server Components are async and run on the server — they don't render in jsdom directly. Two approaches:

### Approach A — Extract data logic, test that

```ts
// app/users/page.tsx
import { db } from '@/lib/db';
import { UserList } from './_components/UserList';

export async function getUsers() {
  return db.users.findMany();
}

export default async function UsersPage() {
  const users = await getUsers();
  return <UserList users={users} />;
}

// app/users/page.test.ts
import { describe, it, expect, vi } from 'vitest';
import { getUsers } from './page';
import { db } from '@/lib/db';

vi.mock('@/lib/db', () => ({
  db: { users: { findMany: vi.fn().mockResolvedValue([{ id: '1', name: 'Alice' }]) } },
}));

describe('getUsers', () => {
  it('returns users from DB', async () => {
    expect(await getUsers()).toEqual([{ id: '1', name: 'Alice' }]);
  });
});
```

The view layer (`UserList`) is a pure component — test separately as a unit.

### Approach B — Playwright integration

```ts
// e2e/users.spec.ts
import { test, expect } from '@playwright/test';

test('users page lists users', async ({ page }) => {
  await page.goto('/users');
  await expect(page.getByRole('listitem')).toHaveCount(3);
  await expect(page.getByText('Alice')).toBeVisible();
});
```

Run against a test database with known seed data, OR mock the API layer the page consumes.

## Testing Server Actions

Server Actions are async functions — testable as pure code if you extract the logic:

```ts
// app/users/actions.ts
'use server';
import { z } from 'zod';
import { revalidatePath } from 'next/cache';
import { db } from '@/lib/db';

const Schema = z.object({ email: z.string().email(), name: z.string().min(1) });

export async function createUser(formData: FormData) {
  const parsed = Schema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { ok: false as const, error: parsed.error.flatten() };
  const user = await db.users.create({ data: parsed.data });
  revalidatePath('/users');
  return { ok: true as const, user };
}
```

```ts
// app/users/actions.test.ts
import { describe, it, expect, vi } from 'vitest';
import { createUser } from './actions';

vi.mock('@/lib/db', () => ({
  db: { users: { create: vi.fn().mockResolvedValue({ id: '1', email: 'a@b.c', name: 'A' }) } },
}));
vi.mock('next/cache', () => ({ revalidatePath: vi.fn() }));

describe('createUser', () => {
  it('returns ok with valid input', async () => {
    const fd = new FormData();
    fd.set('email', 'a@b.c');
    fd.set('name', 'Alice');
    const result = await createUser(fd);
    expect(result.ok).toBe(true);
  });

  it('returns error on invalid input', async () => {
    const fd = new FormData();
    fd.set('email', 'invalid');
    const result = await createUser(fd);
    expect(result.ok).toBe(false);
  });
});
```

For the auth check at the top of the action, mock `auth()` similarly.

## Testing Route Handlers

```ts
// app/api/users/route.test.ts
import { describe, it, expect, vi } from 'vitest';
import { NextRequest } from 'next/server';
import { GET, POST } from './route';

vi.mock('@/lib/db', () => ({
  db: { users: { findMany: vi.fn().mockResolvedValue([]), create: vi.fn() } },
}));

describe('GET /api/users', () => {
  it('returns 200 with users', async () => {
    const res = await GET();
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual([]);
  });
});

describe('POST /api/users', () => {
  it('returns 400 on invalid body', async () => {
    const req = new NextRequest('http://localhost/api/users', {
      method: 'POST',
      body: JSON.stringify({ email: 'bad' }),
    });
    const res = await POST(req);
    expect(res.status).toBe(400);
  });
});
```

For dynamic routes:

```ts
import { GET } from './[id]/route';
const res = await GET(new NextRequest('...'), { params: Promise.resolve({ id: '123' }) });
```

(In Next.js 15+ params is Promise; otherwise plain object.)

## Network mocking with msw

For component tests that hit `fetch`:

```ts
// vitest.setup.ts
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
```

Per-test override:

```ts
import { http, HttpResponse } from 'msw';
server.use(http.get('...', () => HttpResponse.error()));
```

## Playwright setup

`playwright.config.ts`:

```ts
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
  },
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
  },
  projects: [
    { name: 'chromium', use: { browserName: 'chromium' } },
    { name: 'firefox', use: { browserName: 'firefox' } },
    { name: 'webkit', use: { browserName: 'webkit' } },
  ],
});
```

Install: `pnpm dlx playwright install`.

## Coverage discipline

Target ≥80% on services, route handlers, server actions, and Client Components with logic. Skip:

- Pure presentational components (snapshot churn outweighs value).
- Layouts (mostly composition).
- `next.config.js`, `middleware.ts` config bodies (test the behavior end-to-end).

Configure exclusions:

```ts
// vitest.config.ts
test: {
  coverage: {
    exclude: [
      'app/**/layout.tsx',
      'app/**/loading.tsx',
      'app/**/error.tsx',
      'app/**/not-found.tsx',
      '**/*.config.{js,ts,mjs}',
      'middleware.ts',
    ],
  },
}
```

## Iteration cap (from QA agent)

The qa-engineer agent has a hard 3-attempt cap on fixing failing tests. If a test is fundamentally fragile after 3 attempts, mark it `it.skip(...)` with a comment explaining why and report in the QA summary. Don't iterate past the cap.

## Anti-patterns

- ❌ Trying to render a Server Component in jsdom directly. Extract data logic, test that; integration-test the rendered HTML via Playwright.
- ❌ Asserting on implementation details (CSS classes, internal state). Assert on user-visible behavior.
- ❌ `getByTestId` as the first choice. Use `getByRole` / `getByLabelText` first.
- ❌ Real network calls in unit tests. Use msw or vi.mock at the module boundary.
- ❌ Snapshot tests of large component trees. They turn into review noise.
- ❌ E2E tests against `localhost:3000` without `webServer` config — Playwright won't start the dev server.
- ❌ Mocking the SUT instead of its dependencies.
