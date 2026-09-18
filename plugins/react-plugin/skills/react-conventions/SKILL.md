---
name: react-conventions
description: |
  React component structure, hooks rules, file naming, project layout, composition patterns, performance idioms, and effects discipline. Apply when implementing or modifying React SPA code.

  Use this skill to:
  - Structure a new component or feature folder.
  - Apply hooks correctly (rules, naming, dependency arrays).
  - Compose components via children, render props, or compound patterns.
  - Write effects only when needed (and avoid common misuses).
  - Pick performance escape hatches (memo, useMemo, useCallback) when justified.

  Do NOT use this skill for:
  - State management lib choice (see react-state-management).
  - Routing primitives (see react-routing).
  - Form patterns (see react-forms).
  - Testing (see react-testing).
user-invocable: false
paths: ["src/**/*.tsx", "src/**/*.jsx", "src/**/*.ts", "src/**/*.js"]
---

# React Conventions

This skill consolidates idioms that hold across React SPA projects. Apply alongside `js-foundation:typescript-patterns` (general TS strictness).

## Project layout

Two common structures:

### Feature-based (preferred for medium+ apps)

```
src/
├── main.tsx                       # entry — ReactDOM.createRoot
├── App.tsx                         # root component
├── routes.tsx                      # route definitions (or routes/ folder)
├── features/
│   ├── users/
│   │   ├── UserList.tsx
│   │   ├── UserDetail.tsx
│   │   ├── UserForm.tsx
│   │   ├── api/
│   │   │   └── users.ts            # fetcher / TanStack Query hooks
│   │   ├── hooks/
│   │   │   └── useUsers.ts
│   │   └── types.ts
│   └── orders/
│       └── ...
├── components/
│   ├── ui/                         # primitives (Button, Input, Modal)
│   └── shared/                     # cross-feature shared components
├── lib/                            # framework-agnostic utilities
│   ├── http.ts
│   └── format.ts
├── hooks/                          # cross-feature hooks (useDebounce, useMediaQuery)
├── styles/                         # global CSS, design tokens
└── types/                          # global types
```

### Type-based (acceptable for small apps)

```
src/
├── components/
├── hooks/
├── pages/                          # route components
├── lib/
└── styles/
```

Mirror what exists. Don't refactor structure as part of feature work.

## File naming

| What | Convention |
|---|---|
| Component file | `PascalCase.tsx` (`UserCard.tsx`) |
| Hook file | `useCamelCase.ts` (`useDebounce.ts`) |
| Utility module | `kebab-case.ts` or `camelCase.ts` (match project) |
| Test file | `*.test.tsx` colocated, OR mirror in `tests/` |
| Story file | `*.stories.tsx` colocated (Storybook) |
| Type file | `types.ts` per feature, OR `*.types.ts` |

## Hooks rules

```tsx
// ✅ Top-level only
function MyComponent() {
  const [count, setCount] = useState(0);
  const ref = useRef(null);
  useEffect(() => { /* ... */ }, []);
  return <div />;
}

// ❌ Conditional hook
function Bad() {
  if (someCondition) {
    const [x, setX] = useState(0); // breaks Rules of Hooks
  }
}

// ❌ Hook in loop
function AlsoBad() {
  for (let i = 0; i < 5; i++) {
    useState(0); // breaks
  }
}
```

Custom hooks always start with `use*`:

```ts
// src/hooks/useDebounce.ts
import { useEffect, useState } from 'react';

export function useDebounce<T>(value: T, delay = 300): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const id = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(id);
  }, [value, delay]);
  return debounced;
}
```

The `use*` prefix is what enables the linter and React itself to recognize it as a hook.

### Dependency arrays

Trust the `eslint-plugin-react-hooks` `exhaustive-deps` rule. If it flags, fix the dep array — don't disable the rule.

If a function is recreated each render but its identity matters (used in effect dep array, or as prop to memoized child):

```tsx
// Stabilize the function reference
const handleClick = useCallback((id: string) => {
  doSomething(id);
}, []); // deps: anything closed over from outer scope
```

Same for objects:

```tsx
const config = useMemo(() => ({ retries: 3, timeout: 5000 }), []);
```

But: don't pre-emptively wrap everything in `useCallback`/`useMemo`. Only when the deps array failure or memoization break is real.

## Component patterns

### Plain functional component

```tsx
type Props = {
  title: string;
  onClose: () => void;
  children: React.ReactNode;
};

export function Modal({ title, onClose, children }: Props) {
  return (
    <div role="dialog" aria-labelledby="modal-title">
      <h2 id="modal-title">{title}</h2>
      {children}
      <button onClick={onClose}>Close</button>
    </div>
  );
}
```

### Compound components (shared context)

```tsx
// Tabs.tsx
import { createContext, useContext, useState } from 'react';

type TabsContext = { active: string; setActive: (s: string) => void };
const Ctx = createContext<TabsContext | null>(null);

export function Tabs({ defaultTab, children }: { defaultTab: string; children: React.ReactNode }) {
  const [active, setActive] = useState(defaultTab);
  return <Ctx.Provider value={{ active, setActive }}>{children}</Ctx.Provider>;
}

export function Tab({ name, children }: { name: string; children: React.ReactNode }) {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error('Tab must be inside Tabs');
  return (
    <button onClick={() => ctx.setActive(name)} aria-selected={ctx.active === name}>
      {children}
    </button>
  );
}

export function TabPanel({ name, children }: { name: string; children: React.ReactNode }) {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error('TabPanel must be inside Tabs');
  return ctx.active === name ? <div role="tabpanel">{children}</div> : null;
}
```

Usage:

```tsx
<Tabs defaultTab="overview">
  <Tab name="overview">Overview</Tab>
  <Tab name="settings">Settings</Tab>
  <TabPanel name="overview"><OverviewContent /></TabPanel>
  <TabPanel name="settings"><SettingsContent /></TabPanel>
</Tabs>
```

### Render props (when children + context don't fit)

```tsx
type Props<T> = {
  data: T[];
  render: (item: T, index: number) => React.ReactNode;
};

export function List<T>({ data, render }: Props<T>) {
  return <ul>{data.map((item, i) => <li key={i}>{render(item, i)}</li>)}</ul>;
}
```

### `forwardRef` (React ≤18) / ref-as-prop (React 19+)

```tsx
// React 19+ — ref is a regular prop
type ButtonProps = React.ButtonHTMLAttributes<HTMLButtonElement> & { ref?: React.Ref<HTMLButtonElement> };
export function Button({ ref, ...rest }: ButtonProps) {
  return <button ref={ref} {...rest} />;
}

// React ≤18 — forwardRef
import { forwardRef } from 'react';
export const Button = forwardRef<HTMLButtonElement, React.ButtonHTMLAttributes<HTMLButtonElement>>(
  function Button(props, ref) {
    return <button ref={ref} {...props} />;
  }
);
```

Match the React major version's idiom.

## Effects: when (and when not)

`useEffect` is for synchronizing with external systems. NOT for:

```tsx
// ❌ Don't use effect to derive state
function Bad({ users }: { users: User[] }) {
  const [count, setCount] = useState(0);
  useEffect(() => setCount(users.length), [users]);
  return <div>{count}</div>;
}

// ✅ Compute during render
function Good({ users }: { users: User[] }) {
  return <div>{users.length}</div>;
}
```

```tsx
// ❌ Don't use effect for event-driven logic
function Bad() {
  const [clicked, setClicked] = useState(false);
  useEffect(() => {
    if (clicked) reportAnalytics();
  }, [clicked]);
  return <button onClick={() => setClicked(true)}>Click</button>;
}

// ✅ Handle the event directly
function Good() {
  return <button onClick={() => reportAnalytics()}>Click</button>;
}
```

Effect IS correct for:
- Subscribing to external sources (WebSocket, EventEmitter, BroadcastChannel).
- DOM measurement / focus / scroll restoration.
- Browser API observers (IntersectionObserver, ResizeObserver, MutationObserver) — with cleanup.
- Manual data fetching when not using TanStack Query / SWR (most projects use those).

Always return a cleanup function for subscriptions:

```tsx
useEffect(() => {
  const handler = () => doSomething();
  window.addEventListener('resize', handler);
  return () => window.removeEventListener('resize', handler);
}, []);
```

## Performance escape hatches (use sparingly)

### `React.memo`

```tsx
export const ExpensiveChild = React.memo(function ExpensiveChild({ data }: Props) {
  // ...
});
```

Wraps a component in shallow-prop comparison. Don't apply by reflex — measure first. Many components don't need it; some have unstable props that defeat memoization anyway.

### `useMemo` / `useCallback`

```tsx
const sorted = useMemo(() => expensiveSort(items), [items]);
const onClick = useCallback((id: string) => { /* ... */ }, [dep]);
```

Only when:
- The computation is genuinely expensive (profile first).
- Reference stability matters for downstream `memo` or effect deps.

### List virtualization

For lists > 100 items, use `react-window` or `@tanstack/react-virtual`. Renders only visible rows.

## Code splitting

```tsx
import { lazy, Suspense } from 'react';

const HeavyChart = lazy(() => import('./HeavyChart'));

export function Dashboard() {
  return (
    <div>
      <h1>Dashboard</h1>
      <Suspense fallback={<div>Loading chart...</div>}>
        <HeavyChart />
      </Suspense>
    </div>
  );
}
```

Routes are the natural split boundary.

## Accessibility (table stakes)

- Use semantic HTML: `<button>` for clickable, `<a>` for navigation. Don't rebuild buttons from `<div onClick>`.
- Form inputs paired with `<label>` (visible or via `aria-label`).
- Modal / dialog: `role="dialog"`, focus trap, ESC to close, focus return on close.
- Image: `alt` attribute (empty if decorative).
- Lists: real `<ul>`/`<ol>`/`<li>` for screen reader semantics.

## Anti-patterns

- ❌ `useEffect(() => { setState(...) }, [otherState])` to derive state — compute in render.
- ❌ Index as `key` for reorderable lists.
- ❌ `dangerouslySetInnerHTML` without sanitization.
- ❌ `<div onClick={...}>` for clickable — use `<button>`.
- ❌ Stuffing logic into `useEffect` instead of event handlers.
- ❌ `useCallback` / `useMemo` everywhere "for performance" without profiling.
- ❌ Storing derived data in state that could be computed.
- ❌ Disabling `react-hooks/exhaustive-deps` ESLint rule per-line — fix the deps.
- ❌ Mounting/unmounting an effect just to invoke it once (use `useEffect(() => fn(), [])` deliberately).
- ❌ Reading `process.env.X` for secrets in components — env vars are public in client bundles.
