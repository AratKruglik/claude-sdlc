---
name: react-state-management
description: |
  State management decision tree for React SPAs: useState/useReducer, Context API, Zustand, Jotai, Redux Toolkit, TanStack Query, SWR. Detect what's installed and apply matching patterns.

  Use this skill to:
  - Pick the right state tool for the data shape (local / shared UI / server / form).
  - Use Context correctly (and know when to switch to Zustand/Jotai).
  - Implement a Zustand or Jotai store.
  - Set up TanStack Query for server state with caching, pagination, mutations.
  - Avoid common mistakes (overusing Redux, prop drilling, forgetting query invalidation).

  Do NOT use this skill for:
  - General hook conventions (see react-conventions).
  - Form state specifically (see react-forms).
  - Routing state (see react-routing).
  - Testing stores/queries (see react-testing).
user-invocable: false
paths: ["src/**/*.tsx", "src/**/*.ts"]
---

# React State Management Patterns

There is no one-size-fits-all state tool. This skill covers the most common choices and when each fits.

## Decision tree

| Data | Tool |
|---|---|
| Local component state (count, isOpen, hover) | `useState`, `useReducer` |
| Shared between siblings / parent-child | Lift to common parent + props |
| App-wide UI state (theme, locale, sidebar open) | Context, Zustand, Jotai |
| Complex domain state with many actions | Redux Toolkit (or Zustand for simpler cases) |
| Server data with caching, pagination, refetch | TanStack Query, SWR |
| Form state | react-hook-form (see `react-forms` skill) |
| URL-synced state | URL params via `useSearchParams` |

Detect what the project uses and follow its pattern. Don't introduce a new state lib without BA approval.

## `useState` and `useReducer`

```tsx
const [count, setCount] = useState(0);

// Function form for updates depending on previous state
setCount((c) => c + 1);

// Reducer for complex state with discriminated actions
const [state, dispatch] = useReducer(reducer, initialState);
```

When state has more than ~3 fields and updates are coordinated, prefer `useReducer`:

```tsx
type State = { items: Item[]; loading: boolean; error: string | null };
type Action =
  | { type: 'fetch_start' }
  | { type: 'fetch_success'; items: Item[] }
  | { type: 'fetch_error'; error: string };

function reducer(state: State, action: Action): State {
  switch (action.type) {
    case 'fetch_start': return { ...state, loading: true, error: null };
    case 'fetch_success': return { ...state, loading: false, items: action.items };
    case 'fetch_error': return { ...state, loading: false, error: action.error };
  }
}
```

## Context API

For values shared across many components without prop drilling. Best for relatively static or rarely-changing data (theme, locale, current user).

```tsx
import { createContext, useContext, useState } from 'react';

type Theme = 'light' | 'dark';
const ThemeContext = createContext<{ theme: Theme; setTheme: (t: Theme) => void } | null>(null);

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState<Theme>('light');
  return <ThemeContext.Provider value={{ theme, setTheme }}>{children}</ThemeContext.Provider>;
}

export function useTheme() {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error('useTheme must be used within ThemeProvider');
  return ctx;
}
```

### Context pitfall: rerender storms

Every consumer of a Context re-renders when the Context value changes. For frequently-updating state, this is expensive. Solutions:

1. Split contexts: one for state, one for setters (setters are stable references).
2. Memoize the value: `const value = useMemo(() => ({ theme, setTheme }), [theme])`.
3. Switch to Zustand or Jotai (they use direct subscriptions, not React's Context).

For app-wide state that updates frequently, prefer Zustand/Jotai over Context.

## Zustand

Lightweight (`pnpm add zustand`). Simple API, no Provider needed.

```ts
// stores/userStore.ts
import { create } from 'zustand';

type User = { id: string; name: string };
type UserStore = {
  user: User | null;
  setUser: (user: User | null) => void;
  logout: () => void;
};

export const useUserStore = create<UserStore>((set) => ({
  user: null,
  setUser: (user) => set({ user }),
  logout: () => set({ user: null }),
}));
```

Usage:

```tsx
const user = useUserStore((s) => s.user);
const setUser = useUserStore((s) => s.setUser);
```

Selectors (`(s) => s.user`) prevent unrelated re-renders. Without a selector, the component re-renders on every store change.

### Persistence and middleware

```ts
import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';

export const useUserStore = create(
  persist(
    (set) => ({ user: null, setUser: (user) => set({ user }) }),
    { name: 'user-storage', storage: createJSONStorage(() => sessionStorage) }
  )
);
```

NEVER persist auth tokens to localStorage / sessionStorage — XSS risk.

## Jotai

Atomic state — each piece is an `atom`. Best for fine-grained state where many components subscribe to small slices.

```ts
import { atom, useAtom } from 'jotai';

export const userAtom = atom<User | null>(null);
export const themeAtom = atom<'light' | 'dark'>('light');

// Derived atom
export const isAuthenticatedAtom = atom((get) => get(userAtom) !== null);
```

Usage:

```tsx
const [user, setUser] = useAtom(userAtom);
const isAuth = useAtomValue(isAuthenticatedAtom);
```

Jotai is great for forms with many independent fields, atomic updates, or React Suspense integration. Less idiomatic for big domain stores.

## Redux Toolkit (RTK)

For complex domain state with many actions, time-travel debugging, or large team conventions.

```ts
// features/users/usersSlice.ts
import { createSlice, createAsyncThunk, PayloadAction } from '@reduxjs/toolkit';

export const fetchUsers = createAsyncThunk('users/fetch', async () => {
  const res = await fetch('/api/users');
  return res.json() as Promise<User[]>;
});

const slice = createSlice({
  name: 'users',
  initialState: { items: [] as User[], loading: false, error: null as string | null },
  reducers: {
    add: (state, action: PayloadAction<User>) => {
      state.items.push(action.payload);
    },
  },
  extraReducers: (builder) => {
    builder
      .addCase(fetchUsers.pending, (state) => { state.loading = true; })
      .addCase(fetchUsers.fulfilled, (state, action) => { state.loading = false; state.items = action.payload; })
      .addCase(fetchUsers.rejected, (state, action) => { state.loading = false; state.error = action.error.message ?? 'failed'; });
  },
});

export const { add } = slice.actions;
export default slice.reducer;
```

```ts
// store.ts
import { configureStore } from '@reduxjs/toolkit';
import users from './features/users/usersSlice';
export const store = configureStore({ reducer: { users } });
export type RootState = ReturnType<typeof store.getState>;
export type AppDispatch = typeof store.dispatch;
```

```ts
// hooks.ts
import { useDispatch, useSelector } from 'react-redux';
import type { RootState, AppDispatch } from './store';
export const useAppDispatch = useDispatch.withTypes<AppDispatch>();
export const useAppSelector = useSelector.withTypes<RootState>();
```

For most apps in 2024+, RTK is overkill — Zustand or Jotai is lighter. Pick RTK when:
- Time-travel debugging matters.
- Strong team familiarity with Redux conventions.
- RTK Query is already used for server state.

## TanStack Query (server state)

For data that lives on the server. Handles caching, deduplication, refetching, pagination, mutation-then-invalidation.

```ts
// features/users/api.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';

export function useUsers() {
  return useQuery({
    queryKey: ['users'],
    queryFn: async () => {
      const res = await fetch('/api/users');
      if (!res.ok) throw new Error('Failed to fetch');
      return res.json() as Promise<User[]>;
    },
  });
}

export function useUser(id: string) {
  return useQuery({
    queryKey: ['users', id],
    queryFn: () => fetch(`/api/users/${id}`).then((r) => r.json() as Promise<User>),
    enabled: !!id,
  });
}

export function useCreateUser() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: CreateUserInput) =>
      fetch('/api/users', { method: 'POST', body: JSON.stringify(input) }).then((r) => r.json()),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['users'] });
    },
  });
}
```

Usage:

```tsx
function UsersList() {
  const { data, isLoading, error } = useUsers();
  if (isLoading) return <Spinner />;
  if (error) return <Error error={error} />;
  return <ul>{data?.map((u) => <li key={u.id}>{u.name}</li>)}</ul>;
}
```

### Query key conventions

Use array keys with hierarchical structure:

```ts
['users']                       // list
['users', id]                   // single
['users', { filter: 'active' }] // filtered list
['users', id, 'orders']         // sub-resource
```

`invalidateQueries({ queryKey: ['users'] })` invalidates ALL keys starting with `['users']` — handy for "users changed somewhere, refresh everything."

### Mutations

```tsx
const { mutate, isPending } = useCreateUser();
mutate({ email: 'a@b.c', name: 'Alice' }, {
  onSuccess: (user) => router.push(`/users/${user.id}`),
  onError: (err) => toast.error(err.message),
});
```

Always invalidate or update queries after mutation success. Otherwise UI shows stale data.

### Optimistic updates

```ts
useMutation({
  mutationFn: deleteUser,
  onMutate: async (id) => {
    await qc.cancelQueries({ queryKey: ['users'] });
    const previous = qc.getQueryData<User[]>(['users']);
    qc.setQueryData<User[]>(['users'], (old) => old?.filter((u) => u.id !== id) ?? []);
    return { previous };
  },
  onError: (_err, _id, context) => {
    qc.setQueryData(['users'], context?.previous);
  },
  onSettled: () => qc.invalidateQueries({ queryKey: ['users'] }),
});
```

## SWR (alternative to TanStack Query)

```tsx
import useSWR from 'swr';

const fetcher = (url: string) => fetch(url).then((r) => r.json());

function Users() {
  const { data, error, isLoading } = useSWR<User[]>('/api/users', fetcher);
  if (isLoading) return <Spinner />;
  if (error) return <Error />;
  return <ul>{data?.map((u) => <li key={u.id}>{u.name}</li>)}</ul>;
}
```

Simpler API than TanStack Query, slightly less feature-rich. Match the project.

## URL state (`useSearchParams`)

For state that should be shareable / bookmarkable / browser-back-compatible:

```tsx
import { useSearchParams } from 'react-router-dom';

function FilteredList() {
  const [params, setParams] = useSearchParams();
  const filter = params.get('filter') ?? 'all';

  return (
    <>
      <select value={filter} onChange={(e) => setParams({ filter: e.target.value })}>
        <option value="all">All</option>
        <option value="active">Active</option>
      </select>
    </>
  );
}
```

Use for filters, pagination, sort order, search queries — anything users want to return to.

## Anti-patterns

- ❌ Reaching for Redux when `useState` + a Context would do.
- ❌ Using Context for fast-changing state (causes re-render storm).
- ❌ Forgetting `invalidateQueries` after mutations — stale UI.
- ❌ Storing server data in `useState` and manually refetching — that's what TanStack Query/SWR are for.
- ❌ Persisting auth tokens to localStorage (XSS-readable).
- ❌ Multiple `useState` calls for clearly-coordinated state — use `useReducer`.
- ❌ Lifting state to root just because two distant components both need it — use Context or a store.
- ❌ Mutating state in place (`state.items.push(x)` followed by `setState(state)`) — React shallow-compares; same reference = no re-render.
- ❌ `dispatch(action())` outside a Redux Toolkit slice — actions ARE creators in RTK, just call `dispatch(slice.actions.add(payload))`.
