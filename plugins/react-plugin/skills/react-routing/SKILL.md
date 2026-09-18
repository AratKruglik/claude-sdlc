---
name: react-routing
description: |
  Routing libraries for React SPAs: React Router v6/v7 (most common), TanStack Router (typed, modern), wouter (minimal). Detect what's installed and apply matching patterns. Lazy loading, navigation guards, typed params.

  Use this skill to:
  - Configure routes (declarative or file-based).
  - Use navigation hooks (useNavigate, useParams, useSearchParams).
  - Lazy-load routes for code splitting.
  - Implement protected routes / auth guards.
  - Type-safe params via Zod or framework's built-ins.

  Do NOT use this skill for:
  - General React conventions (see react-conventions).
  - State management (see react-state-management).
  - Form handling (see react-forms).
  - Next.js routing (different model — see nextjs-plugin).
user-invocable: false
paths: ["src/**/*.tsx", "src/**/*.jsx"]
---

# React Routing Patterns

Choose the routing library based on what's already in `package.json`. Don't introduce a new one without BA approval.

## Detection

| Marker (in dependencies) | Library |
|---|---|
| `react-router-dom` | React Router v6 (≤6.x) or v7 |
| `@tanstack/react-router` | TanStack Router |
| `wouter` | wouter (minimal alternative) |
| (none) | Single-page; introduce only if BA spec adds multi-page |

## React Router v6 / v7

The de-facto standard. v7 unified `react-router-dom` and the framework features; for SPA usage the API is similar.

### Declarative routes (most common)

```tsx
// src/main.tsx
import { createBrowserRouter, RouterProvider } from 'react-router-dom';
import App from './App';
import UsersList from './pages/UsersList';
import UserDetail from './pages/UserDetail';
import Login from './pages/Login';
import NotFound from './pages/NotFound';

const router = createBrowserRouter([
  {
    path: '/',
    element: <App />,
    errorElement: <NotFound />,
    children: [
      { index: true, element: <Home /> },
      { path: 'users', element: <UsersList /> },
      { path: 'users/:id', element: <UserDetail /> },
      { path: 'login', element: <Login /> },
    ],
  },
]);

ReactDOM.createRoot(document.getElementById('root')!).render(
  <RouterProvider router={router} />
);
```

`<App />` is the layout; `<Outlet />` inside renders the matched child route:

```tsx
// src/App.tsx
import { Outlet } from 'react-router-dom';

export default function App() {
  return (
    <div>
      <Header />
      <main><Outlet /></main>
      <Footer />
    </div>
  );
}
```

### Navigation hooks

```tsx
import { Link, NavLink, useNavigate, useParams, useSearchParams, useLocation } from 'react-router-dom';

// Declarative — Link or NavLink
<Link to="/users">Users</Link>
<NavLink to="/users" className={({ isActive }) => isActive ? 'active' : ''}>Users</NavLink>

// Programmatic
const navigate = useNavigate();
navigate('/users');                          // push
navigate('/users', { replace: true });       // replace
navigate(-1);                                 // back

// Params from dynamic segments
const { id } = useParams<{ id: string }>();

// Search params (query string)
const [searchParams, setSearchParams] = useSearchParams();
const filter = searchParams.get('filter') ?? 'all';
setSearchParams({ filter: 'active' });

// Current location
const location = useLocation();
console.log(location.pathname, location.search, location.hash);
```

### Loaders and actions (data router APIs)

In React Router v6.4+ / v7, route loaders fetch data before render:

```tsx
// src/routes/users.tsx
import { LoaderFunction, useLoaderData } from 'react-router-dom';

export const loader: LoaderFunction = async () => {
  const res = await fetch('/api/users');
  if (!res.ok) throw new Response('Failed', { status: 500 });
  return res.json();
};

export function UsersList() {
  const users = useLoaderData() as User[];
  return <ul>{users.map((u) => <li key={u.id}>{u.name}</li>)}</ul>;
}
```

Wire in route config:

```ts
{ path: 'users', element: <UsersList />, loader: usersLoader }
```

For mutations:

```tsx
import { ActionFunction, redirect, useActionData } from 'react-router-dom';

export const action: ActionFunction = async ({ request }) => {
  const formData = await request.formData();
  // ... validate, save
  return redirect('/users');
};
```

Loaders/actions are an alternative to TanStack Query — pick one per project. For most projects with TanStack Query, skip loaders; use `useQuery` inside the route component.

### Lazy-loaded routes

```tsx
import { lazy } from 'react';

const UsersList = lazy(() => import('./pages/UsersList'));

// In route config
{
  path: 'users',
  element: (
    <Suspense fallback={<Spinner />}>
      <UsersList />
    </Suspense>
  ),
}
```

For file-based code splitting, route config can use lazy loader:

```ts
{ path: 'users', lazy: () => import('./routes/users') }
```

The imported module exports `{ Component, loader, action }`.

### Protected routes (auth guards)

```tsx
// src/routes/RequireAuth.tsx
import { Navigate, Outlet, useLocation } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';

export function RequireAuth() {
  const { user } = useAuth();
  const location = useLocation();
  if (!user) return <Navigate to="/login" state={{ from: location }} replace />;
  return <Outlet />;
}
```

Wrap protected routes:

```ts
{
  element: <RequireAuth />,
  children: [
    { path: 'dashboard', element: <Dashboard /> },
    { path: 'settings', element: <Settings /> },
  ],
}
```

### Type-safe params with Zod

```tsx
import { useParams } from 'react-router-dom';
import { z } from 'zod';

const ParamsSchema = z.object({ id: z.string().uuid() });

function UserDetail() {
  const params = useParams();
  const parsed = ParamsSchema.safeParse(params);
  if (!parsed.success) throw new Error('Invalid params');
  const { id } = parsed.data; // string (UUID)
  // ...
}
```

For library-level type safety, see TanStack Router below.

## TanStack Router

Typed, modern. Code-based or file-based routing. Built-in search-param parsing and validation.

### File-based setup

```ts
// src/routeTree.gen.ts (generated by @tanstack/router-plugin)

// src/routes/__root.tsx
import { createRootRoute, Outlet } from '@tanstack/react-router';

export const Route = createRootRoute({
  component: () => (
    <div>
      <Header />
      <Outlet />
    </div>
  ),
});

// src/routes/users.tsx
import { createFileRoute } from '@tanstack/react-router';

export const Route = createFileRoute('/users')({
  component: UsersPage,
  loader: () => fetchUsers(),
});

function UsersPage() {
  const users = Route.useLoaderData();
  return <ul>{users.map((u) => <li key={u.id}>{u.name}</li>)}</ul>;
}

// src/routes/users.$id.tsx — dynamic segment
export const Route = createFileRoute('/users/$id')({
  parseParams: (params) => ({ id: z.string().uuid().parse(params.id) }),
  component: UserDetail,
});
```

`Route.useParams()` returns the parsed (typed) params — no runtime check needed at the consumer.

### Search params validation

```ts
export const Route = createFileRoute('/users')({
  validateSearch: z.object({
    filter: z.enum(['all', 'active', 'archived']).default('all'),
    page: z.number().int().min(1).default(1),
  }),
  component: UsersPage,
});

// In component
const { filter, page } = Route.useSearch();
```

Type-safe, validated search params at the route level.

### Navigation

```tsx
import { Link, useNavigate } from '@tanstack/react-router';

<Link to="/users" search={{ filter: 'active' }}>Active users</Link>;

const navigate = useNavigate();
navigate({ to: '/users/$id', params: { id: '123' }, search: { tab: 'overview' } });
```

Navigation is fully type-checked — wrong path or missing param is a compile error.

## wouter

Minimal alternative (`pnpm add wouter`). ~3 KB. Pattern-based.

```tsx
import { Route, Switch, Link, useLocation } from 'wouter';

function App() {
  return (
    <Switch>
      <Route path="/"><Home /></Route>
      <Route path="/users"><UsersList /></Route>
      <Route path="/users/:id">{(params) => <UserDetail id={params.id} />}</Route>
      <Route><NotFound /></Route>
    </Switch>
  );
}

const [location, setLocation] = useLocation();
setLocation('/users');
```

Good for very small apps. Misses nested routes with shared layouts (build them via composition).

## Code splitting strategy

Routes are the natural boundary. Don't over-split:

- Each top-level route → split.
- Heavy modal/wizard inside a route → split.
- Small page → don't bother.

For React Router:

```ts
{ path: 'users', lazy: () => import('./routes/users') }
```

For TanStack Router with file-based routes — splitting is built into the plugin.

## Layout patterns

Layouts compose via parent routes:

```ts
// React Router
{
  element: <DashboardLayout />,
  path: '/dashboard',
  children: [
    { index: true, element: <DashboardHome /> },
    { path: 'analytics', element: <Analytics /> },
    { path: 'settings', element: <Settings /> },
  ],
}
```

`<DashboardLayout />` renders `<Outlet />` for children. Persists across navigation within the layout.

## Anti-patterns

- ❌ Mixing `<a href="/internal">` with `<Link>` — full page reload defeats SPA benefits.
- ❌ Storing data already in URL params in component state too — keep ONE source of truth.
- ❌ Reading `window.location.search` directly — use `useSearchParams` or framework hook.
- ❌ Programmatic navigation deep in business logic — pass a callback or use a hook at the page level.
- ❌ Loaders that fetch data already cached by TanStack Query — pick one strategy per project.
- ❌ Forgetting to wrap lazy-loaded routes in `<Suspense>` — error boundary catches the thrown promise oddly.
- ❌ `useNavigate` inside a `useEffect` for redirects — use loaders or `<Navigate>` instead, or run on event handlers.
- ❌ Long route trees in one file — split by feature.
