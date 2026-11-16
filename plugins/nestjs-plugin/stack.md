---
stack: nestjs
priority: 200
aspects: [backend, database]
detect:
  all:
    - file_exists: package.json
    - file_contains:
        path: package.json
        pattern: '"@nestjs/core"'
---

# NestJS Stack Profile

Opinionated backend stack provider. Triggers when `package.json` contains `@nestjs/core`. Wins over `nodejs-plugin` (priority 100) via aspect resolution.

Claims both `backend` and `database` aspects — NestJS typically owns ORM (TypeORM/Prisma/Mongoose) and entity/migration patterns alongside controllers/services. If `laravel-plugin` is also installed, NestJS still wins both aspects via priority.

## Agents per phase

- business_analysis: business-analyst        # core agent
- development: nest-architect                # ⚡ NestJS-specific
- qa: qa-engineer                            # core agent
- security: security-analyst                 # core agent
- documentation: document-writer             # core agent

## Convention skills to apply

- nestjs-plugin:nest-conventions
- nestjs-plugin:decorator-patterns
- nestjs-plugin:nest-data-layer
- nestjs-plugin:nest-advanced
- nestjs-plugin:nest-testing
- js-foundation:typescript-patterns
- js-foundation:npm-patterns

## Extra phases

(none)

## Phase prompts injection

For development phase, inject:
  "NestJS opinionated framework. Module-based architecture: one feature = one module. Read nest-cli.json for monorepo vs standalone layout.
   Use constructor injection for all dependencies — never `new MyService()` outside test files. Apply scopes (DEFAULT/REQUEST/TRANSIENT) only when justified.
   DTOs use class-validator + class-transformer; always pair with global ValidationPipe ({ whitelist: true, forbidNonWhitelisted: true, transform: true }).
   Guards/Interceptors/Pipes/Filters: apply via decorators (@UseGuards, @UseInterceptors) or globally in main.ts via app.useGlobalGuards().
   Configuration: ConfigModule.forRoot({ isGlobal: true }) + ConfigService — never read process.env directly outside config setup.
   Detect ORM from dependencies: TypeORM (@nestjs/typeorm + typeorm), Prisma (@prisma/client + prisma), Mongoose (@nestjs/mongoose + mongoose). Use the matching nest-data-layer patterns.
   Detect advanced surfaces: @nestjs/graphql → GraphQL resolvers; @nestjs/websockets → Gateways; @nestjs/microservices → transport patterns. Apply nest-advanced skill only when relevant package is present.
   Always run `npm run build` (or pnpm/yarn equivalent) AND `npx tsc --noEmit` before completion — NestJS DI errors often surface only at compile or boot time.
   Apply skills: nestjs-plugin:nest-conventions, nestjs-plugin:decorator-patterns, nestjs-plugin:nest-data-layer (when ORM present), nestjs-plugin:nest-advanced (when GraphQL/WS/Microservices present), js-foundation:typescript-patterns, js-foundation:npm-patterns.
   If superpowers is available, invoke superpowers:verification-before-completion before returning."

For qa phase, inject:
  "NestJS testing uses Test.createTestingModule({ imports, providers, controllers }).compile() to build an isolated test container.
   Mock providers via .overrideProvider(Token).useValue({...}) or .useFactory(() => ...). For TypeORM repositories, use getRepositoryToken(Entity) as the override token. For Prisma, mockDeep<PrismaClient>() from jest-mock-extended.
   E2E tests: build INestApplication via testing module, app.init(), then supertest(app.getHttpServer()). Place under test/*.e2e-spec.ts (Nest convention). Run with `npm run test:e2e` if defined in scripts.
   Coverage target ≥80% for services and controllers. Modules and decorator definitions are configuration — exclude from coverage requirements.
   Apply skill: nestjs-plugin:nest-testing."

For security phase, inject:
  "NestJS-specific security checks:
   - Auth guards: passport strategies (JwtStrategy, LocalStrategy) or custom @UseGuards. Verify guards on every protected route; no public-by-default endpoints in authenticated zones.
   - ValidationPipe MUST be global with whitelist: true, forbidNonWhitelisted: true. Without these, extra payload fields silently pass through.
   - Helmet middleware in main.ts (`app.use(helmet())`) for security headers.
   - Rate limiting via @nestjs/throttler — apply globally, override per-route only when justified.
   - CORS: app.enableCors() with explicit origin allowlist. Never `origin: true` in production.
   - SQL injection: TypeORM use parameterized query builder (.where('x = :v', {v})), never string concat. Prisma: never raw $queryRawUnsafe with user input.
   - Secrets: ConfigService.get('SECRET_KEY'), never process.env.SECRET_KEY scattered across modules.
   - File uploads: validate MIME type AND extension; size limits; never save to filesystem with user-controlled name."

## Pre-phase commands

(none)

## Post-pipeline checks

The plugin auto-detects the package manager from the lockfile (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, otherwise npm) and runs the equivalent commands. Override per-project via `.claude/sdlc.local.yaml` `post_pipeline_checks` for monorepo runners (Nx, Turborepo, Lerna).

- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm test; elif [ -f yarn.lock ]; then yarn test; else npm test; fi'
- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm run lint 2>/dev/null || true; elif [ -f yarn.lock ]; then yarn run lint 2>/dev/null || true; else npm run lint --if-present; fi'
- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm run build 2>/dev/null || true; elif [ -f yarn.lock ]; then yarn run build 2>/dev/null || true; else npm run build --if-present; fi'
- npx --no-install tsc --noEmit
