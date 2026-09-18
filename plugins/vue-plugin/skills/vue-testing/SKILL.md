---
name: vue-testing
description: |
  Testing Vue 3 SPAs: Vitest + @vue/test-utils, RTL-style alternatives, Pinia testing via createTestingPinia, composable testing, msw for network mocks, Cypress component testing, Playwright e2e.

  Use this skill to:
  - Set up Vitest for Vue 3 with jsdom + @vue/test-utils.
  - Pick mount vs shallowMount.
  - Test components by props/emits/slots contract.
  - Mock Pinia stores in tests.
  - Test composables in isolation.
  - Set up Playwright or Cypress for end-to-end.

  Do NOT use this skill for:
  - General Vue conventions (see vue-conventions).
  - State patterns (see vue-state-management).
  - Form-specific patterns (see vue-forms).
user-invocable: false
paths: ["**/*.spec.{ts,js}", "**/*.test.{ts,js}", "tests/**"]
---

# Vue 3 Testing Patterns

## Test framework selection

| Layer | Framework |
|---|---|
| Component, composable, plain TS unit | **Vitest** + `@vue/test-utils` (preferred for Vite projects) |
| Component (alt) | `@testing-library/vue` (RTL-style API) |
| Component in browser | **Cypress component testing** (slower, more realistic) |
| End-to-end | **Playwright** (preferred) or **Cypress** |

For Vue 3 + Vite, Vitest is the modern default. Match what's installed.

## Vitest setup

`vite.config.ts`:

```ts
import { defineConfig } from 'vitest/config';
import vue from '@vitejs/plugin-vue';
import path from 'path';

export default defineConfig({
  plugins: [vue()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./vitest.setup.ts'],
    coverage: {
      reporter: ['text', 'html'],
      exclude: ['**/*.config.*', '**/*.spec.*', 'src/main.ts'],
    },
  },
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
});
```

`vitest.setup.ts`:

```ts
// Add custom matchers if needed
import { afterEach } from 'vitest';
import { config } from '@vue/test-utils';

afterEach(() => {
  // cleanup mounted components
});

// Stub global components if needed
config.global.stubs = {
  RouterLink: true,
  RouterView: true,
};
```

Install: `pnpm add -D vitest @vue/test-utils @vitejs/plugin-vue jsdom`.

## `mount` vs `shallowMount`

```ts
import { mount, shallowMount } from '@vue/test-utils';

// mount renders ALL children real
const wrapper = mount(MyComponent, { props: { name: 'Alice' } });

// shallowMount stubs ALL child components (renders <ChildComponent-stub />)
const wrapper = shallowMount(MyComponent, { props: { name: 'Alice' } });
```

**Prefer `mount`** — catches integration bugs (prop passing, slot rendering). Use `shallowMount` only for very large component trees where rendering full subtrees is slow.

## Component test (basics)

```ts
// src/components/UserCard.spec.ts
import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import UserCard from './UserCard.vue';

describe('UserCard', () => {
  it('renders user name and email', () => {
    const wrapper = mount(UserCard, {
      props: { user: { id: '1', name: 'Alice', email: 'a@b.c' } },
    });
    expect(wrapper.text()).toContain('Alice');
    expect(wrapper.text()).toContain('a@b.c');
  });

  it('emits "delete" when delete button clicked', async () => {
    const wrapper = mount(UserCard, {
      props: { user: { id: '1', name: 'Alice', email: 'a@b.c' } },
    });
    await wrapper.find('[data-testid="delete-btn"]').trigger('click');
    expect(wrapper.emitted('delete')).toEqual([['1']]);
  });

  it('renders header slot when provided', () => {
    const wrapper = mount(UserCard, {
      props: { user: { id: '1', name: 'Alice', email: 'a@b.c' } },
      slots: { header: '<h2>Custom Header</h2>' },
    });
    expect(wrapper.find('h2').text()).toBe('Custom Header');
  });
});
```

### Common queries

```ts
wrapper.find('selector')             // CSS selector
wrapper.findAll('selector')          // all matching
wrapper.findComponent(Foo)           // by component
wrapper.findByText('text')           // not built-in; use @testing-library/vue or .text() check
wrapper.text()                        // rendered text content
wrapper.html()                        // rendered HTML
wrapper.attributes('aria-invalid')   // attribute value
wrapper.classes()                     // CSS classes array
wrapper.props()                       // props object
wrapper.emitted()                     // map of emitted events
wrapper.vm                            // component instance (use sparingly)
```

### Triggering events

```ts
await wrapper.find('button').trigger('click');
await wrapper.find('input').trigger('input');
await wrapper.find('input').setValue('hello');     // shortcut for v-model inputs
await wrapper.find('select').setValue('option-value');
await wrapper.find('input[type=checkbox]').setChecked(true);
```

ALWAYS `await` — Vue's reactivity is async; assertions before `nextTick()` see stale state.

## `@testing-library/vue` (RTL-style alternative)

```ts
import { render, screen } from '@testing-library/vue';
import userEvent from '@testing-library/user-event';
import UserCard from './UserCard.vue';

it('calls onDelete when delete clicked', async () => {
  const user = userEvent.setup();
  render(UserCard, { props: { user: { id: '1', name: 'Alice', email: 'a@b.c' } } });
  await user.click(screen.getByRole('button', { name: /delete/i }));
  // emitted events accessed via wrapper.emitted() in test-utils;
  // RTL approach: pass spies as props OR mock store
});
```

Query priority same as React Testing Library: `getByRole` > `getByLabelText` > `getByText` > `getByTestId`.

Pick `@vue/test-utils` for Vue-idiomatic API; `@testing-library/vue` for cross-framework consistency.

## Testing Pinia stores

### Direct test

```ts
import { setActivePinia, createPinia } from 'pinia';
import { beforeEach, describe, it, expect } from 'vitest';
import { useUserStore } from '@/stores/users';

describe('userStore', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  it('starts empty', () => {
    const store = useUserStore();
    expect(store.items).toEqual([]);
    expect(store.count).toBe(0);
  });

  it('adds users via fetchUsers', async () => {
    const store = useUserStore();
    await store.fetchUsers();
    expect(store.items.length).toBeGreaterThan(0);
  });
});
```

### Mocking stores in component tests

```bash
pnpm add -D @pinia/testing
```

```ts
import { mount } from '@vue/test-utils';
import { createTestingPinia } from '@pinia/testing';
import { vi } from 'vitest';
import UserList from './UserList.vue';
import { useUserStore } from '@/stores/users';

it('renders users from store', () => {
  const wrapper = mount(UserList, {
    global: {
      plugins: [createTestingPinia({
        initialState: {
          users: { items: [{ id: '1', name: 'Alice', email: 'a@b.c' }] },
        },
        createSpy: vi.fn,                // for mocking actions
      })],
    },
  });
  expect(wrapper.text()).toContain('Alice');

  const store = useUserStore();
  expect(store.fetchUsers).toBeDefined();
  // store.fetchUsers is a vi.fn() — assert it's called
});
```

`createTestingPinia` stubs all actions by default — they don't run real logic. Useful for component tests that just need the state shape.

## Testing composables

Composables that don't touch DOM can be tested directly:

```ts
import { describe, it, expect } from 'vitest';
import { ref } from 'vue';
import { useCounter } from './useCounter';

describe('useCounter', () => {
  it('increments', () => {
    const { count, increment } = useCounter(0);
    expect(count.value).toBe(0);
    increment();
    expect(count.value).toBe(1);
  });

  it('resets', () => {
    const { count, increment, reset } = useCounter(5);
    increment();
    increment();
    expect(count.value).toBe(7);
    reset();
    expect(count.value).toBe(5);
  });
});
```

For composables that use lifecycle hooks (`onMounted`, etc.), wrap in a test component:

```ts
import { mount } from '@vue/test-utils';
import { defineComponent } from 'vue';
import { useUsers } from './useUsers';

it('fetches users on mount', async () => {
  let result: ReturnType<typeof useUsers>;
  mount(defineComponent({
    setup() {
      result = useUsers();
      return () => null;
    },
  }));
  await flushPromises();
  expect(result!.users.value.length).toBeGreaterThan(0);
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
import { server } from '../vitest.setup';
import { http, HttpResponse } from 'msw';

server.use(http.get('/api/users', () => HttpResponse.error()));
```

## Testing components with router

```ts
import { mount } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';

const router = createRouter({
  history: createMemoryHistory(),
  routes: [
    { path: '/', component: { template: '<div>Home</div>' } },
    { path: '/users', component: { template: '<div>Users</div>' } },
  ],
});

it('navigates on click', async () => {
  router.push('/');
  await router.isReady();

  const wrapper = mount(MyNav, {
    global: { plugins: [router] },
  });

  await wrapper.find('a[href="/users"]').trigger('click');
  await router.isReady();
  expect(router.currentRoute.value.path).toBe('/users');
});
```

## Testing forms (vee-validate)

```ts
import { mount, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import LoginForm from './LoginForm.vue';

it('shows validation errors and submits valid data', async () => {
  const wrapper = mount(LoginForm);

  // Submit empty
  await wrapper.find('form').trigger('submit.prevent');
  await flushPromises();
  expect(wrapper.text()).toContain('Invalid email');

  // Fill correctly
  await wrapper.find('input[type=email]').setValue('a@b.c');
  await wrapper.find('input[type=password]').setValue('longenough');
  await wrapper.find('form').trigger('submit.prevent');
  await flushPromises();
  expect(wrapper.emitted('login')).toBeTruthy();
});
```

`flushPromises` from `@vue/test-utils` waits for all pending Promises — necessary after async validation.

## Cypress component testing (in-browser)

Slower but more realistic — runs actual browser DOM, native events, real CSS.

```ts
// cypress/component/UserCard.cy.ts
import UserCard from '@/components/UserCard.vue';

describe('UserCard', () => {
  it('renders and emits delete', () => {
    const onDelete = cy.spy().as('onDelete');
    cy.mount(UserCard, {
      props: { user: { id: '1', name: 'Alice', email: 'a@b.c' } },
      attrs: { onDelete },
    });
    cy.contains('Alice').should('be.visible');
    cy.get('[data-testid=delete-btn]').click();
    cy.get('@onDelete').should('have.been.calledWith', '1');
  });
});
```

Setup: `cypress.config.ts` with `component: { devServer: { framework: 'vue', bundler: 'vite' } }`.

## Playwright e2e

```ts
// playwright.config.ts
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:5173',
    reuseExistingServer: !process.env.CI,
  },
  use: { baseURL: 'http://localhost:5173', trace: 'on-first-retry' },
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
});
```

## Coverage discipline

Target ≥80% on:
- Composables.
- Pinia stores (state shape + actions).
- Utility functions (`lib/`).
- Components with logic (state, conditional rendering, event handling).

Skip / lower bar:
- Pure presentational components (snapshot churn).
- `App.vue` / route layouts (mostly composition).
- `main.ts`.

```ts
// vite.config.ts test block
test: {
  coverage: {
    exclude: [
      'src/main.ts',
      'src/App.vue',
      'src/router/**',
      '**/*.config.*',
      '**/types/**',
    ],
  },
}
```

## Iteration cap (from QA agent)

The qa-engineer agent has a hard 3-attempt cap on fixing failing tests. After attempt #3, mark `it.skip(...)` with a comment and report in QA summary.

## Anti-patterns

- ❌ Forgetting `await` before `wrapper.find('input').setValue('x')` — Vue's reactivity is async.
- ❌ Asserting on internal state via `wrapper.vm.someRef` — test the public contract (props/emits/slots/rendered HTML).
- ❌ Snapshot tests of large component trees — review noise.
- ❌ Real network calls in unit tests (slow, flaky) — use msw.
- ❌ `getByTestId` everywhere instead of accessible queries.
- ❌ Forgetting `flushPromises()` after async operations.
- ❌ E2E tests against real backend without seed data or mocked endpoints.
- ❌ Mocking the SUT instead of its dependencies.
- ❌ `setActivePinia(createPinia())` skipped in `beforeEach` — store state leaks between tests.
- ❌ `mount` with stubs that hide real bugs — use `shallowMount` deliberately, not as default.
