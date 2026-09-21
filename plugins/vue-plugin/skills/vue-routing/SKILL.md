---
name: vue-routing
description: |
  Vue Router v4 (Vue 3 default) — route configuration, nested routes, dynamic segments, navigation guards, lazy loading, typed routes, route meta, programmatic navigation. Vue Router v3 (Vue 2) pointer only.

  Use this skill to:
  - Configure routes with createRouter + createWebHistory.
  - Use useRoute / useRouter composables in components.
  - Lazy-load route components for code splitting.
  - Implement auth guards via meta + beforeEach.
  - Type route params for safer access.

  Do NOT use this skill for:
  - General Vue conventions (see vue-conventions).
  - State management (see vue-state-management).
  - Forms (see vue-forms).
  - Testing routes (see vue-testing).
user-invocable: false
paths: ["src/**/*.vue", "src/**/*.ts"]
---

# Vue Router v4 Patterns

The de-facto router for Vue 3. Use whatever the project has installed; don't introduce a new router lib.

## Setup

```ts
// src/router/index.ts
import { createRouter, createWebHistory } from 'vue-router';
import HomeView from '@/views/HomeView.vue';

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', name: 'home', component: HomeView },
    { path: '/about', name: 'about', component: () => import('@/views/AboutView.vue') }, // lazy
    { path: '/users', name: 'users', component: () => import('@/views/UsersView.vue') },
    { path: '/users/:id', name: 'user-detail', component: () => import('@/views/UserDetailView.vue'), props: true },
    { path: '/:pathMatch(.*)*', name: 'not-found', component: () => import('@/views/NotFoundView.vue') },
  ],
});

export default router;
```

```ts
// src/main.ts
import { createApp } from 'vue';
import App from './App.vue';
import router from './router';

const app = createApp(App);
app.use(router);
app.mount('#app');
```

```vue
<!-- App.vue -->
<template>
  <header>
    <RouterLink to="/">Home</RouterLink>
    <RouterLink to="/about">About</RouterLink>
  </header>
  <main>
    <RouterView />
  </main>
</template>
```

## History modes

- `createWebHistory()` — HTML5 History API (`/about`, `/users/123`). Requires server config to fall back to `index.html` for unmatched routes.
- `createWebHashHistory()` — hash-based (`/#/about`). No server config needed; less SEO-friendly.
- `createMemoryHistory()` — for SSR/testing.

Default to `createWebHistory()` unless deploying to static host without fallback.

## Route definitions

```ts
const routes = [
  // Static
  { path: '/', name: 'home', component: HomeView },

  // Dynamic segment
  { path: '/users/:id', name: 'user', component: UserView, props: true },

  // Multiple dynamic segments
  { path: '/posts/:category/:slug', component: PostView },

  // Optional segment (Vue Router v4: use route alias or two routes)
  { path: '/users/:id/:tab?', component: UserView },           // ? means optional in v4

  // Catch-all
  { path: '/:pathMatch(.*)*', component: NotFoundView },

  // Aliases (multiple URLs → one component)
  { path: '/home', component: HomeView, alias: '/' },

  // Redirects
  { path: '/old-path', redirect: '/new-path' },
  { path: '/old-user/:id', redirect: (to) => ({ path: '/users/' + to.params.id }) },
];
```

### Nested routes

```ts
{
  path: '/dashboard',
  component: DashboardLayout,
  children: [
    { path: '', component: DashboardHome },          // /dashboard
    { path: 'analytics', component: Analytics },      // /dashboard/analytics
    { path: 'settings', component: Settings },        // /dashboard/settings
  ],
}
```

`DashboardLayout.vue` includes `<RouterView />` to render children:

```vue
<template>
  <nav>
    <RouterLink to="/dashboard">Home</RouterLink>
    <RouterLink to="/dashboard/analytics">Analytics</RouterLink>
  </nav>
  <RouterView />
</template>
```

## Navigation hooks

### Composables

```vue
<script setup lang="ts">
import { useRoute, useRouter } from 'vue-router';
import { computed } from 'vue';

const route = useRoute();
const router = useRouter();

// Reactive route info
const userId = computed(() => route.params.id as string);
const filter = computed(() => (route.query.filter as string) ?? 'all');

// Programmatic
function goToProfile() {
  router.push({ name: 'user', params: { id: '123' } });
}

function replaceWithFilter(value: string) {
  router.replace({ query: { ...route.query, filter: value } });
}
</script>
```

`router.push`, `router.replace`, `router.back()`, `router.forward()`, `router.go(n)`.

### Push variants

```ts
router.push('/users/123');                                       // string path
router.push({ path: '/users/123' });                             // object with path
router.push({ name: 'user', params: { id: '123' } });            // named route
router.push({ name: 'user', params: { id: '123' }, query: { tab: 'overview' } });
router.push({ path: '/users/123', hash: '#bio' });
```

Named routes are safer — refactoring the URL doesn't break the call.

## `<RouterLink>`

```vue
<!-- Basic -->
<RouterLink to="/users">Users</RouterLink>

<!-- Named route -->
<RouterLink :to="{ name: 'user', params: { id: '123' } }">Alice</RouterLink>

<!-- Active class customization -->
<RouterLink to="/users" active-class="my-active" exact-active-class="my-exact-active">Users</RouterLink>

<!-- Custom rendering via slot -->
<RouterLink to="/users" custom v-slot="{ navigate, isActive }">
  <button :class="{ active: isActive }" @click="navigate">Users</button>
</RouterLink>

<!-- Replace instead of push -->
<RouterLink :to="{ name: 'login' }" replace>Log in</RouterLink>
```

For external links: plain `<a href="https://...">`. `<RouterLink>` is for internal navigation only.

## Lazy loading

```ts
{
  path: '/users',
  name: 'users',
  component: () => import('@/views/UsersView.vue'),     // dynamic import → code split
}
```

Vite/Webpack handle code splitting automatically. Each lazy-loaded route becomes a separate chunk.

For grouped chunks:

```ts
component: () => import(/* webpackChunkName: "users" */ '@/views/UsersView.vue')
```

## Navigation guards

### Global

```ts
router.beforeEach(async (to, from) => {
  // returning false → cancel navigation
  // returning a route object → redirect
  // returning undefined or true → continue
  if (to.meta.requiresAuth && !await isAuthenticated()) {
    return { name: 'login', query: { redirect: to.fullPath } };
  }
});

router.afterEach((to, from, failure) => {
  // analytics, scroll restoration, etc.
});
```

### Per-route

```ts
{
  path: '/admin',
  component: AdminView,
  beforeEnter: (to) => {
    if (!isAdmin()) return { name: 'home' };
  },
}
```

### Per-component

```vue
<script setup lang="ts">
import { onBeforeRouteLeave, onBeforeRouteUpdate } from 'vue-router';

onBeforeRouteLeave((to, from) => {
  if (hasUnsavedChanges.value) {
    return window.confirm('Unsaved changes — leave anyway?');
  }
});

onBeforeRouteUpdate((to, from) => {
  // Same component, route changed (e.g., /users/1 → /users/2)
  // Refetch data
});
</script>
```

### Auth guard pattern

```ts
const routes = [
  { path: '/login', name: 'login', component: LoginView, meta: { requiresAuth: false } },
  { path: '/dashboard', name: 'dashboard', component: DashboardView, meta: { requiresAuth: true } },
  { path: '/admin', name: 'admin', component: AdminView, meta: { requiresAuth: true, requiresAdmin: true } },
];

router.beforeEach(async (to) => {
  const userStore = useUserStore();
  if (to.meta.requiresAuth && !userStore.isAuthenticated) {
    return { name: 'login', query: { redirect: to.fullPath } };
  }
  if (to.meta.requiresAdmin && !userStore.isAdmin) {
    return { name: 'dashboard' };
  }
});
```

## Typed routes

Vue Router v4 doesn't auto-type params. Two approaches:

### Manual TypeScript typing

```ts
// src/router/types.ts
declare module 'vue-router' {
  interface RouteMeta {
    requiresAuth?: boolean;
    requiresAdmin?: boolean;
    title?: string;
  }
}

// Per-route typing in components
const route = useRoute();
const userId = route.params.id as string;       // cast — type-safe-ish
```

### `unplugin-vue-router` (file-based, generates types)

```bash
pnpm add -D unplugin-vue-router
```

`vite.config.ts`:

```ts
import VueRouter from 'unplugin-vue-router/vite';

export default defineConfig({
  plugins: [VueRouter({ routesFolder: 'src/pages' }), vue()],
});
```

Place files in `src/pages/`:

```
pages/
├── index.vue                    # /
├── about.vue                    # /about
├── users/
│   ├── index.vue                # /users
│   └── [id].vue                 # /users/:id
└── [...path].vue                # catch-all
```

Generated types in `typed-router.d.ts` provide compile-time safety:

```ts
const route = useRoute('/users/[id]');
const userId = route.params.id;                  // typed as string
```

## Route meta for cross-cutting concerns

```ts
{
  path: '/dashboard',
  component: DashboardView,
  meta: {
    requiresAuth: true,
    title: 'Dashboard',
    layout: 'app',
  },
}
```

Read in `App.vue` for dynamic page titles:

```vue
<script setup lang="ts">
import { watch } from 'vue';
import { useRoute } from 'vue-router';

const route = useRoute();
watch(() => route.meta.title, (title) => {
  document.title = title ? `${title} | MyApp` : 'MyApp';
}, { immediate: true });
</script>
```

## Scroll behavior

```ts
const router = createRouter({
  history: createWebHistory(),
  routes: [...],
  scrollBehavior(to, from, savedPosition) {
    if (savedPosition) return savedPosition;       // back/forward — restore position
    if (to.hash) return { el: to.hash, behavior: 'smooth' };
    return { top: 0 };                              // new route — scroll to top
  },
});
```

## Vue Router v3 (Vue 2 legacy — pointer)

```ts
import VueRouter from 'vue-router';

const router = new VueRouter({
  mode: 'history',
  routes: [
    { path: '/', component: Home },
    { path: '/users/:id', component: UserView },
  ],
});

router.beforeEach((to, from, next) => {
  if (to.meta.requiresAuth && !isAuth()) next('/login');
  else next();
});
```

Differences:
- `new VueRouter()` instead of `createRouter`.
- `mode: 'history' | 'hash'` instead of explicit history factory.
- Guards take `next` callback instead of returning a route.
- `useRoute` / `useRouter` composables don't exist; use `this.$route` / `this.$router`.

Migrating v3 → v4 is invasive (entire route file rewrites). Don't migrate as part of feature work.

## Anti-patterns

- ❌ Forgetting `<RouterView />` in App.vue or layouts — routes don't render.
- ❌ `<a href="/internal">` for internal links — full page reload, defeats SPA.
- ❌ Storing route state in component when query params suffice — duplicate truth.
- ❌ Heavy logic in `beforeEach` that runs on every nav — cache where possible.
- ❌ Mixing string paths and named routes inconsistently — pick one.
- ❌ Forgetting to handle navigation failures (e.g., guard returns false) — async errors silently dropped.
- ❌ Accessing `route.params.id` without type cast or schema validation — bare `any`-like access.
- ❌ Redirects in `beforeEach` without checking `to.name === 'login'` — infinite loop on guard.
- ❌ Long routes file — split by feature into multiple route arrays, then concat.
