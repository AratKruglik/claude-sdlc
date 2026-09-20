---
name: typescript-patterns
description: |
  TypeScript discipline for any JavaScript/TypeScript project (frontend + backend): strict mode, type design, generics, narrowing, error types, module resolution, tsconfig hygiene. Apply when the project has `tsconfig.json` and `typescript` in devDependencies. Stack-agnostic — referenced by every JS/TS framework plugin in the marketplace.

  Use this skill to:
  - Write types that catch bugs at compile time, not runtime.
  - Use generics, conditional types, and discriminated unions correctly.
  - Avoid `any`, `unknown`, and unsafe casts.
  - Match the project's tsconfig strictness level.
  - Type third-party libraries (with @types/* or declaration files).

  Do NOT use this skill for:
  - Plain JavaScript projects (no tsconfig.json).
  - Framework-specific type idioms (React component props, Vue defineProps, Angular signals — those live in framework plugins' own conventions skills).
  - tRPC/Zod runtime-validation specifics — handled by validation libs at the boundary.
user-invocable: false
paths: ["**/*.ts", "**/*.tsx", "tsconfig*.json"]
---

# TypeScript Patterns (stack-agnostic)

This skill encodes idioms that catch real bugs in any TypeScript codebase — backend or frontend, Node.js or browser. Apply alongside the active framework plugin's conventions skill (e.g., `react-conventions`, `nest-conventions`) and `npm-patterns`.

## Detection

Project is TypeScript when **all** hold:

- `tsconfig.json` exists in project root.
- `typescript` is in `devDependencies` (or `dependencies` — rare but valid).

Read `tsconfig.json` first to learn the strictness level. The agent's behavior depends on it.

## Tsconfig hygiene

A modern TypeScript project should have these flags. If the project's tsconfig is laxer, **do not silently tighten it** — match project conventions, but flag in DECISIONS that strictness could be improved.

```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "exactOptionalPropertyTypes": true,
    "noFallthroughCasesInSwitch": true,
    "moduleResolution": "node16",
    "module": "node16",
    "target": "es2022",
    "esModuleInterop": true,
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "forceConsistentCasingInFileNames": true,
    "outDir": "dist",
    "rootDir": "src"
  }
}
```

Frontend projects (Vite/Next.js/Angular) often use `"module": "ESNext"` + `"moduleResolution": "bundler"` instead — match the bundler's expectations.

Key flags and what they catch:

| Flag | Catches |
|---|---|
| `strict: true` | Master switch — enables noImplicitAny, strictNullChecks, strictFunctionTypes, strictBindCallApply, strictPropertyInitialization, alwaysStrict. |
| `noUncheckedIndexedAccess` | `arr[i]` is `T \| undefined`, not `T`. Forces explicit handling of out-of-bounds. |
| `exactOptionalPropertyTypes` | Distinguishes `{ x?: number }` (key may be absent) from `{ x: number \| undefined }` (key present, may be undefined). |
| `isolatedModules` | Each file must be independently transpilable — required for SWC/esbuild/Babel/Vite. |

If you must add a new tsconfig flag for the feature, justify in DECISIONS and isolate it in a new tsconfig (`tsconfig.feature.json` extends base).

## Strictness rules

### Never use `any`

`any` opts out of type-checking entirely. If you genuinely don't know the type:

- **External input** (HTTP body, DB row, URL params): type as `unknown`, then narrow via runtime validator (`zod.parse`, `z.infer<T>`).
- **Library without types**: declare in `src/types/<lib>.d.ts` with the minimal shape you use.
- **Generic constraint**: use `unknown extends T ? ... : ...` patterns, not `any`.

If you must use `any` (real-world example: working with `eval`-like dynamic dispatch), `// eslint-disable-next-line @typescript-eslint/no-explicit-any` with a one-line reason comment.

### Prefer `unknown` over `any`

`unknown` is the safe top type. Forces explicit narrowing before use:

```ts
function parseJson(raw: string): unknown {
  return JSON.parse(raw);
}

const data = parseJson(input);
if (typeof data === 'object' && data !== null && 'id' in data) {
  // narrow further or validate
}
```

In production, prefer a runtime validator over hand-rolled narrowing.

### Type assertions are last resort

`x as Foo` is a lie to the compiler. Use only when:

- You know more than the compiler (e.g., after `instanceof` check that TS can't trace).
- You're bridging to typed code from `unknown` after explicit validation.

Never use `as any as Foo` to shut up the compiler. Find the real type.

### Non-null assertion `x!` — almost never

`x!` says "I promise this isn't null." TS can't verify. Use real narrowing:

```ts
// ❌ Don't
const user = users.find(u => u.id === id)!;

// ✅ Do
const user = users.find(u => u.id === id);
if (!user) throw new NotFoundError(`user ${id}`);
```

## Type design

### Discriminated unions for state

Don't use optional fields for state machines:

```ts
// ❌ Easy to misuse — what does { loading: true, data: foo } mean?
type Result = { loading?: boolean; data?: T; error?: Error };

// ✅ Discriminated — exhaustively checkable
type Result<T> =
  | { status: 'loading' }
  | { status: 'success'; data: T }
  | { status: 'error'; error: Error };
```

Use `switch (r.status)` and exhaustiveness check via `never`:

```ts
function handle<T>(r: Result<T>) {
  switch (r.status) {
    case 'loading': return spinner();
    case 'success': return render(r.data);
    case 'error': return showError(r.error);
    default: {
      const _exhaustive: never = r;
      throw new Error(`unhandled: ${_exhaustive}`);
    }
  }
}
```

### Branded types for IDs

Plain `string` IDs are interchangeable — UserId and OrderId mix. Brand them:

```ts
type Brand<T, B> = T & { __brand: B };
type UserId = Brand<string, 'UserId'>;
type OrderId = Brand<string, 'OrderId'>;

const asUserId = (s: string): UserId => s as UserId;  // controlled cast at boundary
```

Use for primary keys, tokens, secrets — anything that's a string but shouldn't mix with other strings.

### Readonly by default

Mutability is opt-in:

```ts
function summarize(items: ReadonlyArray<Item>): Summary { ... }
type Config = Readonly<{ port: number; host: string }>;
```

Mutable signatures are a permission slip — use them only when the function genuinely needs to mutate.

### Avoid enums; use `as const` unions

```ts
// ❌ Old-school — generates runtime code, weird semantics
enum Role { Admin = 'admin', User = 'user' }

// ✅ String literal union — zero runtime cost, standard behavior
const ROLES = ['admin', 'user'] as const;
type Role = typeof ROLES[number];
```

Exception: `const enum` for hot paths where inlining matters (rare).

## Generics

### Constrain, don't widen

```ts
// ❌ T can be anything — defeats the point
function first<T>(xs: T[]): T | undefined { return xs[0]; }

// ✅ T extends a sensible shape
function getId<T extends { id: string }>(item: T): string {
  return item.id;
}
```

### Infer return types from inputs

```ts
function pick<T, K extends keyof T>(obj: T, keys: readonly K[]): Pick<T, K> {
  // ...
}
```

The caller gets a precisely typed result without explicit annotation.

### Conditional types — sparingly

Conditional types (`T extends U ? A : B`) are powerful but hard to read. Use for:

- Library API ergonomics (e.g., `ReturnType<F>`).
- Removing `null` from a generic: `NonNullable<T>`.

Avoid 3+ nested conditionals. If you reach for it, consider whether a simpler API works.

## Error handling

### Type errors as objects, not strings

```ts
class ValidationError extends Error {
  constructor(public readonly field: string, message: string) {
    super(message);
    this.name = 'ValidationError';
  }
}

class NotFoundError extends Error {
  constructor(public readonly resource: string) {
    super(`${resource} not found`);
    this.name = 'NotFoundError';
  }
}
```

Catch with `instanceof`:

```ts
try {
  await something();
} catch (err) {
  if (err instanceof ValidationError) return res.status(400).json({ field: err.field });
  if (err instanceof NotFoundError) return res.status(404).end();
  throw err;
}
```

### `catch (err: unknown)`

In strict mode, caught errors are `unknown`. Narrow before access:

```ts
catch (err: unknown) {
  if (err instanceof Error) logger.error({ err: err.message, stack: err.stack });
  else logger.error({ err: String(err) });
}
```

## Module resolution

### ESM in modern projects

If `package.json` has `"type": "module"` (Node) or the project uses a bundler (Vite/Webpack/esbuild/Rollup):

- File extensions in imports per project convention:
  - Node ESM: required (`import { x } from './util.js'` — `.js` even from a `.ts` source).
  - Bundler-driven (Vite/Webpack/Next): no extension needed, bundler resolves.
- Use `module: "node16"` / `"nodenext"` / `"ESNext"` in tsconfig per environment.
- For Node ESM: `__dirname` / `__filename` don't exist; use `import.meta.url` + `fileURLToPath`.

### CJS on older Node or by choice

- Imports without extension: `import { x } from './util'`.
- Use `module: "commonjs"`.
- `__dirname` available natively.

### Path aliases — match the project

If tsconfig has `paths`, use them via the configured prefix (`@/util` etc.). Note: TS path aliases don't transpile away — if the project bundles, ensure the bundler resolves them; if it doesn't, use a runtime resolver (`tsconfig-paths`) or stick to relative imports.

## Validation at the boundary

Type the input as `unknown`, validate with a runtime schema, derive the type from the schema:

```ts
import { z } from 'zod';

const CreateUserSchema = z.object({
  email: z.string().email(),
  age: z.number().int().min(0),
});
type CreateUserInput = z.infer<typeof CreateUserSchema>;

// In a route handler / Server Action / form submit / event handler
const parsed = CreateUserSchema.safeParse(rawInput);
if (!parsed.success) return { errors: parsed.error.issues };
const input: CreateUserInput = parsed.data;  // fully typed and validated
```

Use whichever validator is in the project (`zod`, `joi`, `yup`, `valibot`, `ajv` + JSON Schema, `class-validator`). Don't introduce a new one without justification.

## Verification before commit

After implementing, ALWAYS run:

```sh
npx tsc --noEmit
```

For Vue projects: `npx vue-tsc --noEmit` (understands `.vue` SFC types).
For Angular projects: rely on `ng build` (Angular Compiler validates templates that plain `tsc` cannot).

If it errors, fix or report — never commit code that doesn't type-check. If the project has `npm run typecheck` or equivalent, prefer that.

For tests + types together:

```sh
npm test && npx tsc --noEmit
```

If `superpowers:verification-before-completion` is available, invoke it to systematically verify the change against the spec. Falls back to manual checklist (compile, run tests, re-read diff) if not.

## Anti-patterns

- ❌ `as any` to silence the compiler.
- ❌ `// @ts-ignore` / `// @ts-expect-error` without a comment explaining why.
- ❌ Disabling strict mode for one file (it lies to readers about safety guarantees).
- ❌ Casting `JSON.parse` result to a specific type without runtime validation.
- ❌ Using `Function` or `Object` types — too broad.
- ❌ Empty interface (`interface Foo {}`) — same as `{}`, matches almost anything.
- ❌ `Type | undefined` field on a `Class` without `?` (means "must assign undefined", not "may omit").
- ❌ Triple-slash directives in modern code (`/// <reference path="..." />`) — use imports.
