---
name: vue-state-management
description: |
  State management decision tree for Vue 3 SPAs: ref/reactive locally, composables for shared logic, Pinia for app-wide state, provide/inject for DI, TanStack Query Vue for server state. Vuex pointer for Vue 2 legacy.

  Use this skill to:
  - Pick the right state tool for the data shape (local / shared / server / form).
  - Implement a Pinia store (Setup syntax preferred).
  - Use provide/inject correctly with InjectionKey<T>.
  - Set up TanStack Query Vue for server state.
  - Migrate from Vuex (with caution; only if BA asks).

  Do NOT use this skill for:
  - General SFC conventions (see vue-conventions).
  - Form state (see vue-forms — vee-validate handles that).
  - Routing state (see vue-routing — use vue-router useRoute).
  - Testing stores (see vue-testing).
user-invocable: false
paths: ["src/**/*.vue", "src/**/*.ts"]
---

# Vue 3 State Management Patterns

Same intuition as react-state-management. Pinia replaces Vuex for Vue 3.

## Decision tree

| Data | Tool |
|---|---|
| Local component state (count, isOpen) | `ref`, `reactive` |
| Shared between siblings | Lift to common parent + props |
| Composable shared logic | composable returning `{ refs, actions }` |
| App-wide state (current user, theme) | Pinia or `provide`/`inject` |
| Complex domain state | Pinia |
| Server data with caching | TanStack Query Vue (`@tanstack/vue-query`) |
| Form state | vee-validate (see vue-forms) |
| URL-synced state | `vue-router` `useRoute().query` + `useRouter().push` |

## `ref` and `reactive` (covered in vue-conventions)

For component-local state, prefer `ref` (works for primitives + objects, no destructure footgun).

## Composables for shared logic

```ts
// src/composables/useCounter.ts
import { ref, computed } from 'vue';

export function useCounter(initial = 0) {
  const count = ref(initial);
  const double = computed(() => count.value * 2);
  function increment() { count.value++; }
  function reset() { count.value = initial; }
  return { count, double, increment, reset };
}
```

Each `useCounter()` call creates a fresh state — composables don't share state by default. For shared state across components, use Pinia.

## Pinia (Vue 3 default)

`pnpm add pinia`. Setup once in `main.ts`:

```ts
import { createApp } from 'vue';
import { createPinia } from 'pinia';
import App from './App.vue';

const app = createApp(App);
app.use(createPinia());
app.mount('#app');
```

### Setup syntax (preferred for Vue 3)

```ts
// src/stores/users.ts
import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import type { User } from '@/types/user';

export const useUserStore = defineStore('users', () => {
  // state
  const items = ref<User[]>([]);
  const currentUser = ref<User | null>(null);
  const loading = ref(false);

  // getters (computed)
  const count = computed(() => items.value.length);
  const isAuthenticated = computed(() => currentUser.value !== null);

  // actions
  async function fetchUsers() {
    loading.value = true;
    try {
      const res = await fetch('/api/users');
      items.value = await res.json();
    } finally {
      loading.value = false;
    }
  }

  function setCurrentUser(user: User | null) {
    currentUser.value = user;
  }

  return { items, currentUser, loading, count, isAuthenticated, fetchUsers, setCurrentUser };
});
```

Usage in components:

```vue
<script setup lang="ts">
import { useUserStore } from '@/stores/users';
import { storeToRefs } from 'pinia';

const userStore = useUserStore();

// Direct access to reactive state — but DESTRUCTURING loses reactivity
const { items, count, loading } = storeToRefs(userStore);  // ✅ keeps reactivity

// Actions can be destructured directly (they're plain functions)
const { fetchUsers, setCurrentUser } = userStore;          // ✅ OK

onMounted(() => fetchUsers());
</script>

<template>
  <p v-if="loading">Loading...</p>
  <p v-else>Total users: {{ count }}</p>
</template>
```

`storeToRefs` is the Pinia equivalent of `toRefs` — preserves reactivity when destructuring state and getters. Don't use it for actions.

### Options syntax (alternative)

```ts
export const useUserStore = defineStore('users', {
  state: () => ({
    items: [] as User[],
    currentUser: null as User | null,
    loading: false,
  }),
  getters: {
    count: (state) => state.items.length,
    isAuthenticated: (state) => state.currentUser !== null,
  },
  actions: {
    async fetchUsers() {
      this.loading = true;
      try {
        const res = await fetch('/api/users');
        this.items = await res.json();
      } finally {
        this.loading = false;
      }
    },
  },
});
```

Setup syntax is preferred for TS friendliness (better inference) and Composition API consistency. Options syntax is fine if the team prefers it.

### Persistence

```bash
pnpm add pinia-plugin-persistedstate
```

```ts
// main.ts
import { createPinia } from 'pinia';
import piniaPluginPersistedstate from 'pinia-plugin-persistedstate';

const pinia = createPinia();
pinia.use(piniaPluginPersistedstate);
```

```ts
export const useUserStore = defineStore('users', () => { /* ... */ }, {
  persist: { storage: sessionStorage },
});
```

Never persist auth tokens — XSS-readable. Use httpOnly cookies (server-set) or in-memory state cleared on logout.

### Reset

```ts
const userStore = useUserStore();
userStore.$reset();              // works only with Options syntax automatically
// Setup syntax: define a reset action manually
```

For Setup syntax stores, define a reset function:

```ts
function $reset() {
  items.value = [];
  currentUser.value = null;
  loading.value = false;
}
return { /* ... */, $reset };
```

## `provide` / `inject`

Dependency injection for app-wide deps that don't justify a Pinia store. Common: theme, locale, current authenticated user.

```ts
// src/keys.ts
import type { InjectionKey, Ref } from 'vue';

export interface ThemeContext {
  theme: Ref<'light' | 'dark'>;
  setTheme: (t: 'light' | 'dark') => void;
}

export const ThemeKey: InjectionKey<ThemeContext> = Symbol('theme');
```

```vue
<!-- App.vue — provider -->
<script setup lang="ts">
import { provide, ref } from 'vue';
import { ThemeKey } from '@/keys';

const theme = ref<'light' | 'dark'>('light');
function setTheme(t: 'light' | 'dark') {
  theme.value = t;
}
provide(ThemeKey, { theme, setTheme });
</script>
```

```vue
<!-- Any descendant — consumer -->
<script setup lang="ts">
import { inject } from 'vue';
import { ThemeKey } from '@/keys';

const themeCtx = inject(ThemeKey);
if (!themeCtx) throw new Error('ThemeKey not provided');
const { theme, setTheme } = themeCtx;
</script>

<template>
  <p>Current theme: {{ theme }}</p>
  <button @click="setTheme(theme === 'light' ? 'dark' : 'light')">Toggle</button>
</template>
```

`InjectionKey<T>` provides type safety — `inject(key)` returns `T | undefined`.

Use provide/inject for: theme, locale, current user, feature flags shared across the tree. For everything else (frequent updates, complex state), prefer Pinia.

## TanStack Query Vue (`@tanstack/vue-query`)

Server state with caching, deduplication, refetching.

```ts
// main.ts
import { VueQueryPlugin } from '@tanstack/vue-query';
app.use(VueQueryPlugin);
```

```ts
// src/composables/useUsers.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/vue-query';
import { ref } from 'vue';
import type { User } from '@/types/user';

export function useUsers() {
  return useQuery<User[]>({
    queryKey: ['users'],
    queryFn: async () => {
      const res = await fetch('/api/users');
      if (!res.ok) throw new Error('Failed to fetch');
      return res.json();
    },
  });
}

export function useUser(id: string) {
  return useQuery<User>({
    queryKey: ['users', id],
    queryFn: () => fetch(`/api/users/${id}`).then((r) => r.json()),
    enabled: !!id,
  });
}

export function useCreateUser() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: Omit<User, 'id'>) =>
      fetch('/api/users', { method: 'POST', body: JSON.stringify(input) }).then((r) => r.json()),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['users'] });
    },
  });
}
```

Usage:

```vue
<script setup lang="ts">
import { useUsers, useCreateUser } from '@/composables/useUsers';

const { data: users, isLoading, error } = useUsers();
const { mutate: createUser, isPending } = useCreateUser();
</script>

<template>
  <p v-if="isLoading">Loading...</p>
  <p v-else-if="error">Error: {{ error }}</p>
  <ul v-else>
    <li v-for="user in users" :key="user.id">{{ user.name }}</li>
  </ul>
</template>
```

Same query key conventions as React Query — hierarchical arrays.

## VueUse useStorage

Reactive `localStorage` / `sessionStorage` wrapper. NEVER for auth tokens.

```ts
import { useStorage } from '@vueuse/core';

const theme = useStorage('theme', 'light');     // Ref<string>, syncs to localStorage
theme.value = 'dark';                            // updates storage automatically
```

For SSR-safety and serialization options, see VueUse docs.

## URL-synced state

Use `vue-router`:

```ts
import { useRoute, useRouter } from 'vue-router';

const route = useRoute();
const router = useRouter();

// Read query param
const filter = computed(() => (route.query.filter as string) ?? 'all');

// Update
function setFilter(value: string) {
  router.push({ query: { ...route.query, filter: value } });
}
```

Use for filters, pagination, sort orders, search queries — anything users want to bookmark/share.

## Vuex (Vue 2 legacy — pointer only)

For Vue 2 codebases:

```ts
// store/index.ts (Vue 2 + Vuex 3)
import Vuex from 'vuex';

export default new Vuex.Store({
  state: { count: 0 },
  mutations: { increment(state) { state.count++; } },
  actions: { incrementAsync({ commit }) { setTimeout(() => commit('increment'), 100); } },
  getters: { double: (state) => state.count * 2 },
});
```

Migrating Vuex 3 → Pinia: typically rewrites all store modules. Don't migrate as part of feature work — only with explicit BA spec.

## Anti-patterns

- ❌ Destructuring Pinia store state without `storeToRefs` — breaks reactivity.
- ❌ Storing auth tokens in `useStorage` (localStorage XSS risk).
- ❌ Pinia store for transient UI state (modal open, sidebar collapsed) — use ref/reactive in component.
- ❌ Forgetting `app.use(createPinia())` in `main.ts` — stores throw "no active pinia" error.
- ❌ Mutating Pinia store state from outside actions — direct mutations work but bypass devtools tracking.
- ❌ Reaching for Vuex in a Vue 3 project — use Pinia.
- ❌ Forgetting `invalidateQueries` after mutations in TanStack Query — stale UI.
- ❌ Long composables that "do everything" — split by concern.
- ❌ Mixing multiple state libs without a clear boundary (Pinia + custom Context + Vuex shim).
