---
name: server-component-patterns
description: |
  React Server Components vs Client Components in Next.js: the boundary discipline, "use client" / "use server" directives, Server Actions, what serializes across the boundary, common pitfalls.

  Use this skill to:
  - Decide whether a component should be RSC or Client.
  - Push the "use client" boundary as deep as possible.
  - Implement Server Actions correctly (auth, validation, revalidation).
  - Compose RSC and Client components without breaking the model.
  - Pass data across the boundary safely.

  Do NOT use this skill for:
  - General Next.js conventions (see nextjs-conventions).
  - Specific data-fetching APIs and caching (see nextjs-data-fetching).
  - Routing (see nextjs-routing).
user-invocable: false
paths: ["app/**", "src/app/**"]
---

# RSC + Server Actions Patterns

The single most important skill for working in App Router. Get the boundary wrong and you'll get build errors, runtime errors, or silent serialization failures.

## Mental model

- **Server Component (RSC)** — rendered on the server. Has access to: `async/await`, server-only modules (DB clients, fs, filesystem), env vars (including secrets). Does NOT have: `useState`, `useEffect`, `useRef`, browser APIs (`window`, `document`), event handlers.
- **Client Component** — rendered on the client (after initial HTML hydration). Has access to: hooks, browser APIs, event handlers. Does NOT have: server-only modules, secrets, async/await directly in the component body (the function itself isn't async; data flows in via props or hooks).
- **Server Actions** — async functions marked `"use server"`. Callable from Client Components but execute on the server. Form-friendly via `<form action={action}>`.

**Default = RSC.** A file is RSC unless its first non-import line is `"use client"`.

## When to add `"use client"`

A file MUST be Client when it uses any of:

- React hooks: `useState`, `useReducer`, `useEffect`, `useLayoutEffect`, `useRef`, `useContext`, `useMemo`, `useCallback`, custom hooks that use the above.
- Event handlers: `onClick`, `onChange`, `onSubmit`, `onKeyDown`, etc.
- Browser APIs: `window`, `document`, `localStorage`, `navigator`, `IntersectionObserver`, etc.
- Class components (legacy).

A file MAY be Client when:
- It's a leaf in the tree that just needs interactivity. Push the directive AS DEEP as possible.

A file SHOULD be RSC when:
- It just renders data. No state, no effects, no events.
- It needs to fetch from DB or call server-only APIs.
- It uses async/await for data fetching.

## Boundary discipline (push deep)

**Anti-pattern:**

```tsx
// ❌ Whole page is Client just because the filter is interactive
'use client';
import { useState } from 'react';
import { db } from '@/lib/db';   // BREAKS — server-only

export default function UsersPage() {
  const [filter, setFilter] = useState('');
  const users = await db.users.findMany(); // BREAKS — async + server only
  return <div>...</div>;
}
```

**Correct:**

```tsx
// app/users/page.tsx — RSC
import { db } from '@/lib/db';
import { UserFilter } from './_components/UserFilter';
import { UserList } from './_components/UserList';

export default async function UsersPage() {
  const users = await db.users.findMany();
  return (
    <div>
      <UserFilter />        {/* Client — interactive */}
      <UserList users={users} />  {/* RSC — just renders data */}
    </div>
  );
}

// app/users/_components/UserFilter.tsx — Client (only the filter)
'use client';
import { useState } from 'react';

export function UserFilter() {
  const [q, setQ] = useState('');
  return <input value={q} onChange={(e) => setQ(e.target.value)} />;
}

// app/users/_components/UserList.tsx — RSC (no state, no events)
import type { User } from '@/types';
export function UserList({ users }: { users: User[] }) {
  return <ul>{users.map((u) => <li key={u.id}>{u.name}</li>)}</ul>;
}
```

The page stays RSC, fetches data on the server, and only the interactive `UserFilter` is Client.

## Composition rules

### A Client Component can render Server Components VIA `children`

```tsx
// app/(app)/layout.tsx — RSC
import { ClientShell } from './_components/ClientShell';
import { ServerSideNav } from './_components/ServerSideNav';

export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <ClientShell>
      <ServerSideNav />     {/* Server, passed as part of children */}
      {children}            {/* Server, passed through */}
    </ClientShell>
  );
}

// _components/ClientShell.tsx — Client
'use client';
import { useState } from 'react';
export function ClientShell({ children }: { children: React.ReactNode }) {
  const [sidebar, setSidebar] = useState(false);
  return <div>{sidebar && <aside />}{children}</div>;
}
```

The Client Component receives the Server Component as part of `children`. It cannot directly `import` a Server Component.

### Anti-pattern: Importing RSC from a Client Component

```tsx
// ❌ This breaks — Client Component cannot import RSC
'use client';
import { ServerOnlyThing } from './ServerOnlyThing'; // Will fail at build
```

If `ServerOnlyThing` does NOT use server-only modules and is just rendering data, it can be made client-compatible (no `"use client"` needed — leave as RSC, but only pass via `children`/props from a Server parent).

## Data passing across the boundary

When a Server Component renders a Client Component, props are SERIALIZED:

- **Allowed**: primitives (string, number, boolean, null), arrays, plain objects (POJOs), `Date`, `Map`, `Set`, `BigInt`.
- **NOT allowed**: functions (except Server Actions — they have a special RPC layer), class instances (e.g., a `Decimal` from Prisma — convert to string/number), Symbols.

```tsx
// ❌ Class instance — won't serialize
const user = await prisma.user.findFirst();
return <ClientComponent balance={user.balance} />; // balance is Decimal — fails

// ✅ Convert at the boundary
return <ClientComponent balance={user.balance.toNumber()} />;
```

For Prisma Decimal, BigInt, etc., serialize before passing.

## Server Actions (`"use server"`)

A function callable from anywhere (Client OR Server) but executes on the server.

### File-level

```ts
// app/users/actions.ts
'use server';
import { z } from 'zod';
import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { db } from '@/lib/db';
import { auth } from '@/lib/auth';

const CreateUserSchema = z.object({ email: z.string().email(), name: z.string().min(1) });

export async function createUser(formData: FormData) {
  const session = await auth();
  if (!session?.user) throw new Error('unauthorized');

  const parsed = CreateUserSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) {
    return { ok: false as const, error: parsed.error.flatten() };
  }

  await db.users.create({ data: parsed.data });
  revalidatePath('/users');
  redirect('/users');
}
```

### Inline (in RSC)

```tsx
// app/users/page.tsx
export default async function UsersPage() {
  async function deleteUser(id: string) {
    'use server';
    const session = await auth();
    if (!session?.user) throw new Error('unauthorized');
    await db.users.delete({ where: { id } });
    revalidatePath('/users');
  }
  return <UserList onDelete={deleteUser} />;
}
```

### Calling from Client

```tsx
// _components/CreateUserForm.tsx
'use client';
import { createUser } from '../actions';
import { useFormState } from 'react-dom';

export function CreateUserForm() {
  const [state, formAction] = useFormState(createUser, null);
  return (
    <form action={formAction}>
      <input name="email" />
      <input name="name" />
      <button>Create</button>
      {state?.ok === false && <p>{JSON.stringify(state.error)}</p>}
    </form>
  );
}
```

Or directly from event handlers:

```tsx
'use client';
import { deleteUser } from '../actions';

export function DeleteButton({ id }: { id: string }) {
  return <button onClick={() => deleteUser(id)}>Delete</button>;
}
```

### Server Action security rules (NON-NEGOTIABLE)

1. **Authorize at the top of every Server Action.** They are public RPC endpoints.
2. **Validate input.** FormData and arguments come from the network — treat as untrusted.
3. **Don't return secrets.** Return values are sent to the client.
4. **Use `revalidatePath` / `revalidateTag` after mutations** — otherwise the client sees stale data.
5. **Configure `serverActions.allowedOrigins` in `next.config.js`** for production CORS-like protection.

## `useFormStatus` and `useFormState`

```tsx
'use client';
import { useFormStatus } from 'react-dom';

function SubmitButton() {
  const { pending } = useFormStatus();
  return <button disabled={pending}>{pending ? 'Saving...' : 'Save'}</button>;
}
```

`useFormStatus` MUST be inside a `<form action={...}>`. Pairs with `useFormState` for return-value propagation.

## Suspense and streaming

RSC + `<Suspense>` enables streaming:

```tsx
import { Suspense } from 'react';

export default function Page() {
  return (
    <>
      <h1>Dashboard</h1>
      <Suspense fallback={<div>Loading users...</div>}>
        <UsersList />        {/* async RSC */}
      </Suspense>
      <Suspense fallback={<div>Loading orders...</div>}>
        <OrdersList />       {/* async RSC */}
      </Suspense>
    </>
  );
}
```

The shell (`<h1>`) renders immediately; users and orders stream in independently as their data arrives. Pair with `loading.tsx` for the segment-level fallback.

## Cookies, headers, and auth in RSC

```ts
import { cookies, headers } from 'next/headers';

export default async function Page() {
  const cookieStore = cookies();
  const token = cookieStore.get('session')?.value;
  // ...
}
```

In Next.js 15+, `cookies()` and `headers()` return Promises — `await` them.

## Anti-patterns

- ❌ `"use client"` at the top of every file by reflex. Default is RSC.
- ❌ Passing functions (other than Server Actions) from Server to Client.
- ❌ Passing class instances (Prisma Decimal, Date subclasses) without serialization.
- ❌ Server Actions without auth checks.
- ❌ Server Actions that don't call `revalidatePath` after mutations — UI shows stale data.
- ❌ Importing server-only modules (`fs`, ORM clients) in files that ARE OR MIGHT BECOME Client. Use `import 'server-only'` at the top of files that must remain server-only — it'll error if accidentally imported into client.
- ❌ Using `<Suspense>` without an async child — there's nothing to suspend on.
- ❌ Using `useEffect` to fetch data in a Client Component when the parent could fetch it as RSC and pass it down.
