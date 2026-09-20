---
name: nextjs-conventions
description: |
  Next.js project structure, App Router conventions, file-based routing primitives, layouts, error boundaries, metadata, image and font optimization, configuration. Apply when implementing or modifying Next.js features.

  Use this skill to:
  - Pick the correct file convention (page/layout/loading/error/not-found/route/template/default).
  - Structure a feature within the App Router tree.
  - Set up metadata for SEO and OpenGraph.
  - Configure next.config.js for headers, redirects, image domains.
  - Use built-in fonts and images correctly.

  Do NOT use this skill for:
  - Server vs Client component boundaries (see server-component-patterns).
  - Data fetching patterns (see nextjs-data-fetching).
  - Complex routing (parallel/intercepting routes — see nextjs-routing).
  - Testing (see nextjs-testing).
user-invocable: false
paths: ["app/**", "pages/**", "src/**", "next.config.*"]
---

# Next.js Conventions

This skill consolidates structural and configuration idioms for Next.js App Router projects. Apply alongside `server-component-patterns` (the RSC/Client model) and `js-foundation:typescript-patterns` (TS strictness).

## Project layout

```
project-root/
├── package.json
├── tsconfig.json
├── next.config.{js,mjs,ts}
├── middleware.ts                # optional, runs on every matched request
├── app/                          # App Router root (modern)
│   ├── layout.tsx                # ROOT layout (required) — defines <html><body>
│   ├── page.tsx                  # / route
│   ├── loading.tsx               # default loading UI
│   ├── error.tsx                 # default error boundary (Client Component)
│   ├── not-found.tsx             # 404 UI
│   ├── globals.css               # imported once in root layout
│   ├── (marketing)/              # route group (parens hide from URL)
│   │   ├── about/page.tsx        # /about
│   │   └── pricing/page.tsx      # /pricing
│   ├── (app)/                    # another group, possibly with own layout
│   │   ├── layout.tsx
│   │   ├── dashboard/page.tsx
│   │   └── settings/
│   │       ├── layout.tsx
│   │       ├── page.tsx          # /settings
│   │       └── account/page.tsx  # /settings/account
│   ├── api/                      # API routes (Route Handlers)
│   │   └── users/route.ts        # GET /api/users
│   └── _components/              # private folder (excluded from routing)
├── components/                   # shared UI components
│   ├── ui/                       # primitives (Button, Input, etc.)
│   └── features/                 # feature-specific
├── lib/                          # framework-agnostic utilities
│   ├── db.ts                     # ORM client
│   ├── auth.ts                   # auth setup
│   └── utils.ts
├── public/                       # static assets — served at /
├── styles/                       # if not using app/globals.css
└── tests/                        # or co-located *.test.tsx
```

For Pages Router projects, `pages/` mirrors the older flat structure. Migrate to App Router only when the BA spec asks.

## Special files (App Router)

### `layout.tsx` (required at app root, optional below)

```tsx
// app/layout.tsx — root layout
import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'My App',
  description: '...',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
```

Nested layouts compose:
- `app/(app)/layout.tsx` wraps everything under `(app)/`.
- They preserve state across navigation within the same layout.

### `page.tsx`

The route's UI. Default-exported. Receives:

```tsx
type Props = {
  params: { id: string };          // dynamic segments
  searchParams: { [key: string]: string | string[] | undefined };
};

export default async function Page({ params, searchParams }: Props) {
  const data = await getData(params.id);
  return <div>...</div>;
}
```

In Next.js 15+, `params` and `searchParams` are PROMISES — `await params` to get values.

### `loading.tsx`

Auto-wraps the segment in a `<Suspense>` boundary. No props — it's just a fallback.

```tsx
// app/dashboard/loading.tsx
export default function Loading() {
  return <div>Loading dashboard...</div>;
}
```

For more granular control, use `<Suspense fallback={...}>` directly inside the page.

### `error.tsx`

Error boundary. MUST be a Client Component:

```tsx
// app/dashboard/error.tsx
'use client';

export default function Error({ error, reset }: { error: Error; reset: () => void }) {
  return (
    <div>
      <p>Error: {error.message}</p>
      <button onClick={reset}>Try again</button>
    </div>
  );
}
```

Catches errors thrown in the segment's page or its layouts/children. For root-level errors, use `app/global-error.tsx` (also Client).

### `not-found.tsx`

Triggered by `notFound()` calls in Server Components or Route Handlers.

```ts
// in a page
import { notFound } from 'next/navigation';
const user = await db.users.findUnique({ where: { id: params.id } });
if (!user) notFound();
```

### `route.ts` (Route Handlers)

Backend endpoints. Export verbs:

```ts
// app/api/users/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import { db } from '@/lib/db';

export async function GET() {
  const users = await db.users.findMany();
  return NextResponse.json(users);
}

const CreateUserSchema = z.object({ email: z.string().email(), name: z.string().min(1) });

export async function POST(req: NextRequest) {
  const body = await req.json();
  const parsed = CreateUserSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const user = await db.users.create({ data: parsed.data });
  return NextResponse.json(user, { status: 201 });
}
```

Receives `req: NextRequest` and (for dynamic routes) `{ params }`. Returns `NextResponse` or anything `Response`-compatible.

## Route groups

Folder name in parens — DOESN'T affect URL but groups files:

- `app/(marketing)/about/page.tsx` → `/about`
- `app/(marketing)/layout.tsx` — applied only to marketing group routes

Use to apply different layouts to logical sections of the app.

## Private folders

Folders prefixed with `_` are excluded from routing:

- `app/_components/` — shared components colocated with the route they belong to but not routable.

## Metadata

Static:

```tsx
export const metadata: Metadata = {
  title: 'Dashboard',
  description: '...',
  openGraph: {
    title: 'Dashboard',
    images: ['/og-image.png'],
  },
  robots: { index: true, follow: true },
};
```

Dynamic:

```tsx
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const user = await getUser(params.id);
  if (!user) return { title: 'Not found' };
  return {
    title: `${user.name} | Dashboard`,
    description: user.bio,
  };
}
```

For absolute URLs (OG images, canonical), set `metadataBase` in root layout:

```tsx
export const metadata: Metadata = {
  metadataBase: new URL('https://example.com'),
};
```

## Image optimization

```tsx
import Image from 'next/image';

<Image
  src="/profile.png"
  alt="User profile"
  width={200}
  height={200}
  priority   // for above-the-fold
/>;

// Remote images
<Image src="https://cdn.example.com/photo.jpg" alt="..." width={800} height={600} />;
```

Configure remote domains in `next.config.js`:

```js
module.exports = {
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: 'cdn.example.com' },
      { protocol: 'https', hostname: '*.amazonaws.com' },
    ],
  },
};
```

NEVER `images.domains: ['*']` — that allows any host as image proxy, a security risk.

## Font optimization

```tsx
// app/layout.tsx
import { Inter } from 'next/font/google';

const inter = Inter({ subsets: ['latin'], display: 'swap' });

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={inter.className}>
      <body>{children}</body>
    </html>
  );
}
```

Self-hosted fonts via `next/font/local`. Either way, fonts are inlined and self-hosted automatically — no external requests.

## `next.config.js`

Common patterns:

```js
/** @type {import('next').NextConfig} */
module.exports = {
  reactStrictMode: true,
  images: {
    remotePatterns: [...],
  },
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          { key: 'X-Frame-Options', value: 'DENY' },
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
          { key: 'Strict-Transport-Security', value: 'max-age=63072000; includeSubDomains; preload' },
        ],
      },
    ];
  },
  async redirects() {
    return [{ source: '/old', destination: '/new', permanent: true }];
  },
  async rewrites() {
    return [{ source: '/api/legacy/:path*', destination: 'https://legacy.example.com/:path*' }];
  },
};
```

For Next.js 15+ TypeScript config, use `next.config.ts`:

```ts
import type { NextConfig } from 'next';

const config: NextConfig = { /* ... */ };
export default config;
```

## Environment variables

| Var pattern | Available in |
|---|---|
| `NEXT_PUBLIC_*` | Client AND server (bundled into JS) |
| Anything else | Server only (Server Components, Route Handlers, Server Actions, middleware) |

```ts
// Server-only
const dbUrl = process.env.DATABASE_URL;        // OK on server, undefined on client

// Client-safe
const apiUrl = process.env.NEXT_PUBLIC_API_URL; // OK everywhere
```

NEVER prefix a secret with `NEXT_PUBLIC_`. NEVER read `process.env.X` from a Client Component if `X` is a secret.

For type safety, declare in `next-env.d.ts` or a custom env validator (e.g., `@t3-oss/env-nextjs`):

```ts
// env.ts (project-root)
import { createEnv } from '@t3-oss/env-nextjs';
import { z } from 'zod';

export const env = createEnv({
  server: {
    DATABASE_URL: z.string().url(),
    NEXTAUTH_SECRET: z.string().min(32),
  },
  client: {
    NEXT_PUBLIC_API_URL: z.string().url(),
  },
  experimental__runtimeEnv: process.env,
});
```

## Anti-patterns

- ❌ Putting `"use client"` at the top of a file as a quick fix when `useState` errors appear — analyze the actual need.
- ❌ Reading `process.env.SECRET_KEY` in a Client Component (it's `undefined` AND a security smell).
- ❌ `images.domains: ['*']` or omitting `remotePatterns` for remote images.
- ❌ Putting heavy dependencies in `middleware.ts` — it runs on every request.
- ❌ Using `pages/api/` if the project is App Router (mix routes only when migrating; pick one).
- ❌ Skipping `loading.tsx` for slow data — users get blank pages while async work runs.
- ❌ Using `<a href>` for internal navigation — use `<Link>` from `next/link` for client-side routing.
- ❌ Disabling `reactStrictMode` to "fix" double-render issues — those are usually real bugs in effects.
