---
name: nextjs-data-fetching
description: |
  Data fetching, caching, and revalidation patterns in Next.js App Router. Covers native fetch caching, ISR/SSG/SSR per-route choice, generateStaticParams, 'use cache' / unstable_cache, revalidatePath/updateTag/revalidateTag, Route Handlers, dynamic vs static rendering.

  Use this skill to:
  - Pick the right rendering mode (SSG / ISR / SSR / streaming) per route.
  - Use native fetch caching options correctly.
  - Build Route Handlers that match REST conventions.
  - Invalidate cached data after mutations.
  - Use generateStaticParams for dynamic SSG.

  Do NOT use this skill for:
  - RSC vs Client boundaries (see server-component-patterns).
  - Routing primitives (see nextjs-routing).
  - General conventions (see nextjs-conventions).
user-invocable: false
paths: ["app/**", "pages/**", "src/**"]
---

# Next.js Data Fetching Patterns

Next.js extends `fetch()` with caching/revalidation primitives, and offers the `'use cache'` directive (`unstable_cache` on ≤15) for non-fetch async work. Plus `revalidatePath` / `updateTag` / `revalidateTag` to invalidate after mutations. Get this layer right and pages become fast and consistent.

## Rendering modes

Per-route, the decision tree:

| Need | Mode | Setup |
|---|---|---|
| Data unchanged after build (marketing, docs) | **SSG** (Static) | `fetch(url, { cache: 'force-cache' })` — fetch is not cached by default (15+; ≤14 cached by default). |
| Data changes occasionally (hourly/daily) | **ISR** (revalidate) | `fetch(url, { next: { revalidate: 3600 } })` |
| Data per-request (dashboards, account pages) | **SSR** (Dynamic) | `fetch(url, { cache: 'no-store' })` or `export const dynamic = 'force-dynamic'` |
| Data dynamic but tag-invalidatable | **Tagged ISR** | `fetch(url, { next: { tags: ['users'] } })` + `updateTag('users')` in Server Actions, `revalidateTag('users', 'max')` elsewhere (16+; ≤15: `revalidateTag('users')`) |
| Streaming / progressive | **RSC + Suspense** | wrap async children in `<Suspense fallback={...}>` |

By default, Next.js prerenders pages at build time (SSG). Adding `cache: 'no-store'` or reading dynamic APIs (`cookies()`, `headers()`, `searchParams`) opts the page into SSR.

## Native `fetch` extensions

```ts
// Not cached by default (15+; ≤14 cached by default). Opt in:
const res = await fetch('https://api.example.com/data', { cache: 'force-cache' });

// Static + revalidate every 60s (ISR)
const res = await fetch('https://api.example.com/data', { next: { revalidate: 60 } });

// Always fresh (SSR)
const res = await fetch('https://api.example.com/data', { cache: 'no-store' });

// Tag-based: invalidate manually via updateTag / revalidateTag
const res = await fetch('https://api.example.com/data', { next: { tags: ['users'] } });
```

`fetch()` deduplication: identical fetches within a single render are deduped automatically — call freely from multiple components without worry.

## `unstable_cache` for non-fetch async work

Wrap any async function with `unstable_cache`:

```ts
import { unstable_cache } from 'next/cache';
import { db } from '@/lib/db';

export const getUsers = unstable_cache(
  async () => db.users.findMany(),
  ['users'],                        // cache key parts (must be a stable array)
  { revalidate: 60, tags: ['users'] }
);
```

Use for ORM calls, computed data, anything you'd otherwise duplicate logic to make cacheable.

The cache key parts must be stable strings. To cache PER ARGUMENT, include arguments:

```ts
export const getUserById = (id: string) =>
  unstable_cache(
    async () => db.users.findUnique({ where: { id } }),
    ['user', id],
    { revalidate: 60, tags: [`user:${id}`] }
  )();
```

In Next 16 `unstable_cache` is replaced by the `'use cache'` directive with `cacheTag` / `cacheLife` from `next/cache` (needs `cacheComponents: true` in `next.config`). Use `unstable_cache` only where the project already does — read the installed `next` version from package.json.

## `generateStaticParams`

For dynamic routes that should be statically generated at build:

```tsx
// app/blog/[slug]/page.tsx
export async function generateStaticParams() {
  const posts = await db.post.findMany({ select: { slug: true } });
  return posts.map((p) => ({ slug: p.slug }));
}

// dynamicParams (default true) — allow on-demand generation for slugs not pre-built
export const dynamicParams = true;

export default async function PostPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const post = await db.post.findUnique({ where: { slug } });
  if (!post) notFound();
  return <article>{post.content}</article>;
}
```

Pair with `revalidate` for ISR — pages are built initially, then refreshed per the schedule.

## Route segment config

Per-route configuration via exported constants:

```ts
// app/some/page.tsx
export const dynamic = 'auto' | 'force-dynamic' | 'error' | 'force-static';
export const dynamicParams = true | false;
export const revalidate = false | 0 | number;
export const fetchCache = 'auto' | 'default-cache' | 'only-cache' | 'force-cache' | 'force-no-store' | 'default-no-store' | 'only-no-store';
export const runtime = 'nodejs' | 'edge';
export const preferredRegion = 'auto' | 'global' | 'home' | string | string[];
export const maxDuration = number;
```

Common patterns:
- Marketing page → defaults (SSG).
- User dashboard → `export const dynamic = 'force-dynamic'`.
- API route that hits DB → `export const runtime = 'nodejs'` (DB clients usually don't run on edge).

## Route Handlers (API endpoints)

`app/api/<resource>/route.ts`:

```ts
import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import { db } from '@/lib/db';
import { auth } from '@/lib/auth';

// GET /api/users
export async function GET() {
  const users = await db.users.findMany();
  return NextResponse.json(users);
}

// POST /api/users
const CreateUserSchema = z.object({ email: z.string().email(), name: z.string().min(1) });

export async function POST(req: NextRequest) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });

  const body = await req.json();
  const parsed = CreateUserSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const user = await db.users.create({ data: parsed.data });
  return NextResponse.json(user, { status: 201 });
}
```

### Dynamic Route Handlers

```ts
// app/api/users/[id]/route.ts
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const user = await db.users.findUnique({ where: { id } });
  if (!user) return NextResponse.json({ error: 'not found' }, { status: 404 });
  return NextResponse.json(user);
}

export async function DELETE(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  await db.users.delete({ where: { id } });
  return new Response(null, { status: 204 });
}
```

`params` is async since 15; sync access was removed in 16 (≤14: plain object — read the installed `next` version from package.json).

### Route Handler caching

Route Handlers are dynamic by default in modern Next.js. To cache GETs:

```ts
export const dynamic = 'force-static'; // cache the GET response
export const revalidate = 60;
```

For most API endpoints, leave dynamic.

## Revalidation after mutations

```ts
// in a Server Action
import { revalidatePath, updateTag } from 'next/cache';

export async function deleteUser(id: string) {
  'use server';
  await db.users.delete({ where: { id } });
  revalidatePath('/users');                 // path-based — invalidates that route's cache
  updateTag('users');                       // tag-based — invalidates anything fetched with this tag
}
```

`revalidatePath` is the simpler tool. Tags are more granular when one resource is fetched in many places: `updateTag('users')` in Server Actions, `revalidateTag('users', 'max')` elsewhere (16+). On ≤15 use single-arg `revalidateTag('users')`.

## Streaming with Suspense

```tsx
// app/dashboard/page.tsx
import { Suspense } from 'react';

export default function DashboardPage() {
  return (
    <>
      <h1>Dashboard</h1>
      <Suspense fallback={<div>Loading recent activity...</div>}>
        <RecentActivity />     {/* async RSC */}
      </Suspense>
      <Suspense fallback={<div>Loading metrics...</div>}>
        <Metrics />            {/* async RSC */}
      </Suspense>
    </>
  );
}

async function RecentActivity() {
  const items = await getActivityFromSlowAPI();
  return <ul>{items.map(...)}</ul>;
}
```

The shell renders immediately; each Suspense boundary streams in independently. Combine with `loading.tsx` for the whole-segment fallback.

## Edge vs Node runtime

```ts
export const runtime = 'nodejs'; // default; 'edge' is legacy
```

Edge (legacy — prefer the Node.js runtime; keep `'edge'` only where the project already uses it):
- Lower cold-start, geographically distributed.
- Limited Node APIs — no `fs`, no native modules.
- DB clients usually don't work on edge (use HTTP-based clients like Neon serverless, Planetscale's HTTP client).

Default to `nodejs`; do not introduce `runtime = 'edge'` in new code.

## Anti-patterns

- ❌ Fetching the same data multiple times across components without leveraging fetch dedup or `'use cache'` / `unstable_cache`.
- ❌ Using `cache: 'no-store'` everywhere — defeats Next's caching, makes every request hit origin.
- ❌ Forgetting `revalidatePath` after a mutation — users see stale data.
- ❌ `cookies()` / `headers()` reads in a function intended to be cached — they make the route dynamic.
- ❌ DB client on `runtime: 'edge'` without verifying it's edge-compatible.
- ❌ `generateStaticParams` returning all DB rows at build for a million-row table — use ISR with a small initial set.
- ❌ Reading `searchParams` in a Server Component and assuming the page can be static — searchParams force dynamic rendering.
- ❌ Returning `NextResponse.json(undefined)` — pass `null` or omit the body.
