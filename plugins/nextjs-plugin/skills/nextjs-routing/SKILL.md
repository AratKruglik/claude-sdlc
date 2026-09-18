---
name: nextjs-routing
description: |
  Next.js App Router routing primitives: file-based routes, dynamic and catch-all segments, route groups, parallel routes, intercepting routes, middleware, programmatic navigation, link patterns.

  Use this skill to:
  - Pick the correct dynamic segment syntax for the route shape.
  - Use route groups to organize without affecting URLs.
  - Implement parallel/intercepting routes for modal-style navigation.
  - Build effective middleware for auth, redirects, A/B tests.
  - Use Link and useRouter correctly.

  Do NOT use this skill for:
  - Data fetching per route (see nextjs-data-fetching).
  - General file conventions (see nextjs-conventions).
  - RSC vs Client (see server-component-patterns).
user-invocable: false
paths: ["app/**", "pages/**", "src/**"]
---

# Next.js Routing Patterns

App Router is file-based: folders are routes, `page.tsx` is the page UI. This skill covers the routing primitives beyond plain pages.

## Dynamic segments

```
app/users/[id]/page.tsx                → /users/:id          → params.id: string
app/posts/[slug]/page.tsx              → /posts/:slug        → params.slug: string
app/docs/[...path]/page.tsx            → /docs/a/b/c          → params.path: string[]
app/optional/[[...path]]/page.tsx      → /optional AND /optional/a/b → params.path: string[] | undefined
```

In Next.js 15+, `params` is a Promise:

```tsx
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  // ...
}
```

In Next.js 14 and earlier, `params` is a plain object — no `await` needed.

## Route groups (organizational)

Folders in parens — DON'T appear in URL but allow:
- Different layouts for different sections.
- Logical organization without nested URLs.

```
app/(marketing)/about/page.tsx         → /about
app/(marketing)/pricing/page.tsx       → /pricing
app/(marketing)/layout.tsx             → applies to /about and /pricing

app/(app)/dashboard/page.tsx           → /dashboard
app/(app)/settings/page.tsx            → /settings
app/(app)/layout.tsx                   → applies to /dashboard and /settings
```

`/about` doesn't get the `/(app)/` layout, even though they share `app/`'s root layout.

## Parallel routes

Render two segments simultaneously in one layout — for dashboards, modal overlays, side panels.

```
app/dashboard/layout.tsx
app/dashboard/@analytics/page.tsx       → renders into {analytics} slot
app/dashboard/@team/page.tsx            → renders into {team} slot
app/dashboard/page.tsx                  → renders into {children} slot
```

The layout receives all slots:

```tsx
// app/dashboard/layout.tsx
export default function Layout({
  children,
  analytics,
  team,
}: {
  children: React.ReactNode;
  analytics: React.ReactNode;
  team: React.ReactNode;
}) {
  return (
    <div>
      <main>{children}</main>
      <aside>{analytics}</aside>
      <aside>{team}</aside>
    </div>
  );
}
```

If a slot has no matching route for a navigation, provide `default.tsx` in the slot folder for fallback.

## Intercepting routes (modals)

Render a different component for the SAME URL based on the navigation source. Common pattern: clicking a link from a list opens a modal; visiting the URL directly shows the full page.

```
app/photos/page.tsx                          → /photos (gallery)
app/photos/[id]/page.tsx                     → /photos/:id (full view, direct visits)
app/photos/(.)photos/[id]/page.tsx           → intercepts /photos/:id from /photos
app/photos/(..)settings/page.tsx             → intercepts from one level up
app/photos/(..)(..)about/page.tsx            → intercepts from two levels up
app/photos/(...)about/page.tsx               → intercepts from app root
```

Combine with parallel routes (`@modal` slot) for the modal pattern:

```
app/layout.tsx
app/page.tsx                                  → / (gallery)
app/@modal/(.)photos/[id]/page.tsx            → modal version
app/@modal/default.tsx                        → no-modal fallback
app/photos/[id]/page.tsx                      → direct visit URL
```

The layout slots `{children}` and `{modal}` — layout renders both, modal overlays.

## Programmatic navigation

### From Client Components

```tsx
'use client';
import { useRouter, usePathname, useSearchParams } from 'next/navigation';

export function NavButton() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  return (
    <button onClick={() => router.push('/dashboard')}>
      Go to dashboard
    </button>
  );
}
```

`router.push(href)`, `router.replace(href)`, `router.back()`, `router.forward()`, `router.refresh()`, `router.prefetch(href)`.

### From Server Components / Server Actions

```ts
import { redirect, permanentRedirect } from 'next/navigation';

// In a Server Component
if (!user) redirect('/login');

// In a Server Action
export async function deleteAccount() {
  'use server';
  await db.users.delete({ where: { id: session.user.id } });
  redirect('/');
}
```

`redirect()` throws an internal exception (NEXT_REDIRECT) — don't catch it; let it propagate.

## `<Link>`

Always use `<Link>` from `next/link` for internal navigation. Client-side routing, prefetching, faster perceived nav.

```tsx
import Link from 'next/link';

<Link href="/dashboard">Dashboard</Link>;
<Link href={{ pathname: '/users', query: { filter: 'active' } }}>Active users</Link>;
<Link href="/external" replace prefetch={false}>...</Link>;
```

`prefetch` is `true` by default for visible Links — Next.js prefetches the route for instant navigation. Disable for rarely-visited or expensive routes.

For external URLs: plain `<a href="https://...">` is fine.

## Middleware

`middleware.ts` at the project root. Runs BEFORE every matched request — keep it lean.

```ts
import { NextResponse, type NextRequest } from 'next/server';

export function middleware(req: NextRequest) {
  // Auth check
  const token = req.cookies.get('session')?.value;
  if (!token && req.nextUrl.pathname.startsWith('/admin')) {
    return NextResponse.redirect(new URL('/login', req.url));
  }

  // Header rewrite
  const res = NextResponse.next();
  res.headers.set('X-Request-Id', crypto.randomUUID());
  return res;
}

export const config = {
  matcher: [
    // Skip static files and Next.js internals
    '/((?!_next/static|_next/image|favicon.ico|.*\\..*).*)',
  ],
};
```

### Middleware capabilities

- **Read**: cookies, headers, geolocation (`req.geo`), URL.
- **Write**: rewrite URL (`NextResponse.rewrite`), redirect, modify response headers, set cookies.
- **Cannot**: read request body (it's not consumed yet), import server-only Node APIs (it runs on edge).

### Common patterns

- **Auth gate**: redirect to /login if no session cookie.
- **A/B testing**: rewrite to a variant based on cookie/geo/random.
- **Internationalization**: rewrite to /en, /uk, /es based on Accept-Language.
- **Bot detection**: redirect known bots to a static cached page.

## `redirects` and `rewrites` in `next.config.js`

For static URL transformations that don't need request inspection:

```js
module.exports = {
  async redirects() {
    return [
      { source: '/old-blog/:slug', destination: '/blog/:slug', permanent: true },
      { source: '/admin', destination: '/dashboard', permanent: false },
    ];
  },
  async rewrites() {
    return [
      // Proxy to a different backend
      { source: '/api/legacy/:path*', destination: 'https://legacy.example.com/:path*' },
    ];
  },
};
```

Redirects = HTTP 301/302 visible to client. Rewrites = invisible URL transformation.

## Status codes from Route Handlers and pages

```ts
// In a Route Handler
return new NextResponse(null, { status: 204 });
return NextResponse.json({ error: 'not found' }, { status: 404 });

// In a page (RSC)
import { notFound } from 'next/navigation';
if (!data) notFound();   // throws, renders not-found.tsx, sets 404 status
```

For redirects with custom status:

```ts
NextResponse.redirect(url, 301);
```

## Anti-patterns

- ❌ Using `<a href="/internal">` for internal links — no client-side routing, full reload.
- ❌ `useRouter` from `next/router` (Pages Router) in App Router — use `next/navigation` instead.
- ❌ Heavy logic in `middleware.ts` (it runs on every request and on edge).
- ❌ `redirect()` inside try/catch — catches the internal NEXT_REDIRECT and breaks navigation.
- ❌ Long-running computation in middleware — request stalls.
- ❌ Reading request body in middleware — it's not consumed yet; use Route Handler instead.
- ❌ `<Link>` to external URLs — Next.js will treat it as internal and may handle weirdly.
- ❌ `prefetch={true}` on dozens of Links visible at once — wastes bandwidth.
- ❌ Hard-coding URLs throughout the app — define route helpers in `lib/routes.ts` for type safety.
