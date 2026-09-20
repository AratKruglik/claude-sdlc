---
name: nest-testing
description: |
  NestJS testing patterns: Test.createTestingModule for unit/integration, mocking providers, e2e tests with INestApplication + supertest, ORM mocking (TypeORM/Prisma/Mongoose), test fixtures.

  Use this skill to:
  - Write unit tests for services with mocked dependencies.
  - Write integration tests with real DI but mocked external services.
  - Write e2e tests for HTTP endpoints via supertest.
  - Mock repositories/Prisma client correctly.
  - Cover services and controllers to ≥80%.

  Do NOT use this skill for:
  - Test framework setup (Jest/Vitest config — usually already in place).
  - Frontend tests.
  - Load testing (out of QA scope).
user-invocable: false
paths: ["**/*.spec.ts", "test/**"]
---

# NestJS Testing

NestJS has a first-class testing module. The pattern: build a synthetic IoC container with the providers you want, override what you need, and exercise the system.

## Test framework

Default in Nest CLI is Jest. If the project uses Vitest, the patterns translate 1:1 — the imports change (`@nestjs/testing` works with both).

Test scripts in `package.json`:

```json
{
  "scripts": {
    "test": "jest",
    "test:watch": "jest --watch",
    "test:cov": "jest --coverage",
    "test:e2e": "jest --config ./test/jest-e2e.json"
  }
}
```

E2E tests live in `test/` (or `apps/<app>/test/` in monorepo) and use a separate Jest config that picks up `*.e2e-spec.ts`.

## Unit test — service with mocked deps

```ts
// src/users/users.service.spec.ts
import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { UsersService } from './users.service';
import { User } from './entities/user.entity';

describe('UsersService', () => {
  let service: UsersService;
  let repo: jest.Mocked<Repository<User>>;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        UsersService,
        {
          provide: getRepositoryToken(User),
          useValue: {
            findOne: jest.fn(),
            find: jest.fn(),
            save: jest.fn(),
            create: jest.fn(),
            delete: jest.fn(),
          },
        },
      ],
    }).compile();

    service = module.get(UsersService);
    repo = module.get(getRepositoryToken(User));
  });

  it('finds a user by email', async () => {
    const user = { id: '1', email: 'a@b.c' } as User;
    repo.findOne.mockResolvedValue(user);
    expect(await service.findByEmail('a@b.c')).toBe(user);
    expect(repo.findOne).toHaveBeenCalledWith({ where: { email: 'a@b.c' } });
  });

  it('returns null when not found', async () => {
    repo.findOne.mockResolvedValue(null);
    expect(await service.findByEmail('missing@b.c')).toBeNull();
  });
});
```

Key points:
- Use `getRepositoryToken(Entity)` as the provider token — TypeORM's `@InjectRepository` resolves to this.
- Type the mock as `jest.Mocked<Repository<User>>` for autocomplete and type safety on `mockResolvedValue` / `mockRejectedValue`.

## Mocking Prisma

```ts
import { mockDeep, DeepMockProxy } from 'jest-mock-extended';
import { PrismaClient } from '@prisma/client';

let prisma: DeepMockProxy<PrismaClient>;

beforeEach(async () => {
  prisma = mockDeep<PrismaClient>();
  const module = await Test.createTestingModule({
    providers: [
      UsersService,
      { provide: PrismaService, useValue: prisma },
    ],
  }).compile();
  service = module.get(UsersService);
});

it('creates a user', async () => {
  const created = { id: '1', email: 'a@b.c' };
  prisma.user.create.mockResolvedValue(created as any);
  const result = await service.create({ email: 'a@b.c', password: 'secret' });
  expect(result).toEqual(created);
});
```

`jest-mock-extended` (`pnpm add -D jest-mock-extended`) provides typed deep mocks — Prisma's nested API (`prisma.user.create`, `prisma.user.findMany`) gets full type info.

## Mocking Mongoose

```ts
import { getModelToken } from '@nestjs/mongoose';

const userModelMock = {
  findOne: jest.fn().mockReturnValue({ exec: jest.fn() }),
  create: jest.fn(),
  // ...
};

beforeEach(async () => {
  const module = await Test.createTestingModule({
    providers: [
      UsersService,
      { provide: getModelToken(User.name), useValue: userModelMock },
    ],
  }).compile();
});
```

Mongoose's chained API (`.findOne().exec()`) makes mocks fiddly — return `{ exec: jest.fn() }` from each query method.

## Integration test — real container, mocked external services

For controllers with services, often you want real DI through the controller-service-repository chain but mock the database:

```ts
const module = await Test.createTestingModule({
  controllers: [UsersController],
  providers: [
    UsersService,
    { provide: getRepositoryToken(User), useValue: repoMock },
    { provide: MailerService, useValue: { send: jest.fn().mockResolvedValue(undefined) } },
  ],
})
  .overrideGuard(JwtAuthGuard)
  .useValue({ canActivate: () => true })
  .compile();
```

`.overrideGuard(...).useValue(...)` is the cleanest way to bypass auth in tests.

## E2E test

```ts
// test/users.e2e-spec.ts
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';

describe('UsersController (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const module: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    })
      .overrideProvider(MailerService).useValue({ send: jest.fn() })
      .compile();

    app = module.createNestApplication();
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }));
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  it('POST /users → 201', async () => {
    const res = await request(app.getHttpServer())
      .post('/users')
      .send({ email: 'new@user.com', password: 'longenough' })
      .expect(201);
    expect(res.body).toMatchObject({ email: 'new@user.com' });
    expect(res.body).not.toHaveProperty('passwordHash');
  });

  it('POST /users with extra field → 400', async () => {
    await request(app.getHttpServer())
      .post('/users')
      .send({ email: 'a@b.c', password: 'longenough', isAdmin: true })
      .expect(400);                         // forbidNonWhitelisted catches this
  });
});
```

Use `app.getHttpServer()` (not `app.listen()`) — supertest binds to a random port itself.

For database, prefer:
- A test container (Postgres/Mongo via Testcontainers) per suite.
- Or a separate test database with migrations applied in `beforeAll`.
- Or in-memory (sqlite-memory for TypeORM, mongo-memory-server) for speed — caveat: subtle differences from real DB.

## E2E test database setup pattern

```ts
beforeAll(async () => {
  const module = await Test.createTestingModule({
    imports: [AppModule],
  })
    .overrideProvider(getDataSourceToken())
    .useFactory({
      factory: async () => {
        const ds = new DataSource({
          type: 'sqlite',
          database: ':memory:',
          entities: [User, Order],
          synchronize: true,                 // OK in tests
        });
        await ds.initialize();
        return ds;
      },
    })
    .compile();
  // ...
});
```

## Test fixtures

For repeated entities, factory functions:

```ts
// test/factories/user.factory.ts
import { faker } from '@faker-js/faker';
import { User } from '../../src/users/entities/user.entity';

export const userFactory = (overrides: Partial<User> = {}): User => ({
  id: faker.string.uuid(),
  email: faker.internet.email(),
  passwordHash: '$argon2id$...',
  metadata: {},
  createdAt: new Date(),
  updatedAt: new Date(),
  ...overrides,
} as User);
```

Use `userFactory({ email: 'specific@x.com' })` in tests to override what matters and get reasonable defaults for the rest.

## Coverage discipline

Target ≥80% for **services** and **controllers**. These hold business logic.

Don't measure coverage on:
- Modules (`*.module.ts`) — pure configuration.
- Decorator definitions — DSL, not logic.
- DTOs/entities — schemas, not logic.
- `main.ts` — bootstrap.

Configure Jest to exclude:

```jsonc
// package.json
{
  "jest": {
    "collectCoverageFrom": [
      "src/**/*.{ts,js}",
      "!src/**/*.module.ts",
      "!src/**/*.dto.ts",
      "!src/**/*.entity.ts",
      "!src/main.ts"
    ]
  }
}
```

## Iteration cap (from QA agent)

The qa-engineer agent has a hard 3-attempt cap on fixing failing tests. If a test is fundamentally fragile after 3 attempts, mark it `it.skip(...)` with a comment explaining why and report in the QA summary. Don't iterate past the cap.

## Anti-patterns

- ❌ Sharing mock state between tests without `beforeEach` reset.
- ❌ Real database calls in unit tests (slow, flaky).
- ❌ E2E tests against `localhost:3000` — use `app.getHttpServer()` so each test creates its own port.
- ❌ Asserting on `body.passwordHash` not being there as the only protection — also test that the endpoint excludes it via DTO/serializer.
- ❌ `expect(spy).toHaveBeenCalled()` without `.toHaveBeenCalledWith(...)` — half a test.
- ❌ Long e2e tests that exercise dozens of routes — split per resource.
- ❌ Mocking the SUT (test the real thing; mock its deps).
