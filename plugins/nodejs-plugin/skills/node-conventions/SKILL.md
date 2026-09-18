---
name: node-conventions
description: |
  Node.js backend conventions: project layout, configuration, logging, routing, and error handling patterns. Apply when implementing or modifying Node.js backend code in projects matching the nodejs stack profile.

  Use this skill to:
  - Pick conventional file/folder structure for a new module.
  - Wire configuration through env vars correctly.
  - Use the project's existing logger style.
  - Implement error handling that matches the framework (Express/Fastify/Koa).
  - Follow async/await patterns consistently.

  Do NOT use this skill for:
  - Frontend code (React/Vue/RN have their own conventions).
  - NestJS-specific patterns (decorators, DI, modules) — nest-plugin owns those.
  - Database schema design (call out as a sub-task; npm-patterns covers package management, not DB).
user-invocable: false
paths: ["**/*.js", "**/*.mjs", "**/*.ts", "package.json"]
---

# Node.js Backend Conventions

This skill consolidates idioms that hold across most Node.js backend projects (Express, Fastify, Koa, plain Node). Follow them when adding code; if a project's `CLAUDE.md` contradicts a convention here, the project wins.

## Project layout

Typical layout:

```
project-root/
├── package.json
├── tsconfig.json              # if TypeScript
├── src/
│   ├── index.js               # entry point — start server, wire app
│   ├── app.js                 # framework instance (express(), fastify())
│   ├── config.js              # env-var reader (single source)
│   ├── routes/                # route definitions, one file per resource
│   ├── controllers/           # request handlers (or merged into routes)
│   ├── services/              # business logic, framework-agnostic
│   ├── middleware/
│   ├── lib/                   # shared utilities
│   └── db/                    # data access layer
├── test/  OR  __tests__/
└── dist/                      # build output (TS), gitignored
```

Mirror what exists. If the project uses a flat layout, do not introduce nested layout for one new file.

## Configuration

Single config module reading from `process.env`:

```js
// src/config.js
const requiredEnv = ['DATABASE_URL', 'PORT'];
for (const key of requiredEnv) {
  if (!process.env[key]) throw new Error(`Missing env var: ${key}`);
}

module.exports = {
  port: Number(process.env.PORT),
  databaseUrl: process.env.DATABASE_URL,
  logLevel: process.env.LOG_LEVEL || 'info',
};
```

Never read `process.env` from business logic. Always go through config.

## Logging

Use the project's existing logger. Detection priority:

1. `pino` in deps → `const logger = require('pino')()`
2. `winston` in deps → use the configured instance
3. `bunyan` in deps → use the configured instance
4. Otherwise → `console.log`/`console.error` is acceptable

Never introduce a new logger as part of feature work without justification in DECISIONS.

Log levels: `debug` (verbose dev), `info` (normal flow), `warn` (recoverable), `error` (something failed).

## Routing patterns

### Express

```js
// src/routes/health.js
const router = require('express').Router();
const { getHealth } = require('../controllers/health');

router.get('/healthz', getHealth);

module.exports = router;
```

Mount in `src/app.js`:

```js
app.use(require('./routes/health'));
```

### Fastify

```js
// src/routes/health.js
async function healthRoutes(fastify) {
  fastify.get('/healthz', async () => ({ status: 'ok' }));
}
module.exports = healthRoutes;
```

Register in `src/app.js`:

```js
fastify.register(require('./routes/health'));
```

## Error handling

### Async route handlers — never let rejections escape

Express requires explicit `next(err)`. Two patterns:

**Pattern A — wrapper**:

```js
const asyncHandler = (fn) => (req, res, next) =>
  Promise.resolve(fn(req, res, next)).catch(next);

router.get('/x', asyncHandler(async (req, res) => {
  const data = await mayThrow();
  res.json(data);
}));
```

**Pattern B — express@5+ native** (auto-forwards rejections to next).

Use whatever the project already uses. Don't introduce a wrapper if the project uses express@5.

### Centralized error middleware

```js
// src/middleware/error.js
module.exports = (err, req, res, next) => {
  logger.error({ err }, 'request failed');
  const status = err.status || 500;
  res.status(status).json({ error: err.message });
};
```

Always last in the middleware chain.

### Fastify: `setErrorHandler`

```js
fastify.setErrorHandler((err, req, reply) => {
  logger.error({ err }, 'request failed');
  reply.status(err.statusCode || 500).send({ error: err.message });
});
```

## Validation

At the request boundary, not in business logic. Use what's installed:

- `zod` → schema.parse(req.body) inside try/catch.
- `joi` → schema.validate(req.body, { abortEarly: false }).
- `ajv` → compiled validator instance.
- Express → `express-validator` middleware on the route.

If nothing is installed and BA spec requires validation: add `zod` (smallest, TS-friendly) and document in DECISIONS.

## Async patterns

- Prefer `async/await` over `.then().catch()`.
- Don't mix CJS `require` and ESM `import` in one file. Detect from `package.json` `"type"` field.
- Don't use top-level `await` unless `"type": "module"` is set.
- For parallel work, `Promise.all([a, b, c])`. For settled-on-all, `Promise.allSettled`.

## Graceful shutdown

For HTTP servers, handle `SIGTERM` and `SIGINT`:

```js
const server = app.listen(port);

const shutdown = async () => {
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 10_000).unref();
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
```

Drain in-flight requests, close DB pool, then exit.

## Anti-patterns

- ❌ `app.use((req, res) => res.status(500).send(err.stack))` — never expose stack traces in production responses.
- ❌ Reading `process.env.X` deep inside business logic.
- ❌ Mixing `require` and `import` in one file.
- ❌ Swallowing errors silently (`catch(() => {})`).
- ❌ Hardcoded ports / URLs / credentials.
- ❌ Module-level mutable state (use dependency injection or factory functions).
- ❌ `eval`, `Function()` constructor on user input.
