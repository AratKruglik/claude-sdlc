---
name: nest-conventions
description: |
  NestJS module structure, dependency injection, lifecycle, configuration, exception handling, and logging conventions. Apply when implementing or modifying NestJS backend code.

  Use this skill to:
  - Structure feature modules (one feature = one module).
  - Wire DI correctly (constructor injection, scopes, custom tokens).
  - Set up ConfigModule, ValidationPipe, exception filters in main.ts.
  - Use lifecycle hooks for init and graceful shutdown.
  - Pick the right exception class for each error case.

  Do NOT use this skill for:
  - Decorator-specific patterns (see decorator-patterns).
  - ORM/data access (see nest-data-layer).
  - GraphQL/WebSockets/Microservices (see nest-advanced).
  - Testing (see nest-testing).
user-invocable: false
paths: ["src/**/*.ts"]
---

# NestJS Conventions

This skill encodes module-level idioms for NestJS backend code. Apply alongside `decorator-patterns` (decorator-specific syntax) and `js-foundation:typescript-patterns` (general TS strictness).

## Project layout

Standalone application:

```
project-root/
├── nest-cli.json
├── package.json
├── tsconfig.json
├── tsconfig.build.json
├── src/
│   ├── main.ts                    # bootstrap
│   ├── app.module.ts              # root module
│   ├── app.controller.ts          # optional, often just /healthz
│   ├── app.service.ts             # optional
│   ├── config/                    # config files (app.config.ts, db.config.ts)
│   ├── common/                    # shared (filters, interceptors, pipes, decorators)
│   │   ├── filters/
│   │   ├── interceptors/
│   │   ├── pipes/
│   │   └── decorators/
│   ├── users/                     # feature module
│   │   ├── users.module.ts
│   │   ├── users.controller.ts
│   │   ├── users.service.ts
│   │   ├── dto/
│   │   │   ├── create-user.dto.ts
│   │   │   └── update-user.dto.ts
│   │   ├── entities/
│   │   │   └── user.entity.ts
│   │   └── tests/                 # often co-located OR in /test
│   ├── auth/
│   └── ...
├── test/                          # e2e tests
│   └── *.e2e-spec.ts
└── dist/                          # build output, gitignored
```

Monorepo (Nx-flavored, `nest-cli.json` `"monorepo": true`):

```
project-root/
├── nest-cli.json
├── apps/
│   └── api/
│       └── src/
└── libs/
    ├── shared/
    └── users/
```

Mirror what exists. Don't introduce a new layout pattern for one feature.

## Module structure

One feature = one module:

```ts
// src/users/users.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';
import { User } from './entities/user.entity';

@Module({
  imports: [TypeOrmModule.forFeature([User])],
  controllers: [UsersController],
  providers: [UsersService],
  exports: [UsersService],            // export only what other modules need
})
export class UsersModule {}
```

Wire into root:

```ts
// src/app.module.ts
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    TypeOrmModule.forRootAsync({...}),
    UsersModule,
    AuthModule,
  ],
})
export class AppModule {}
```

### `@Global()` sparingly

```ts
@Global()
@Module({
  providers: [LoggerService],
  exports: [LoggerService],
})
export class LoggerModule {}
```

Use only for genuinely cross-cutting deps (logger, config, DB connection). For two unrelated features needing the same service — explicit import is clearer.

### Circular imports — refactor first

If `UsersModule` and `OrdersModule` import each other:

1. Extract shared types to a `shared/` lib.
2. Or merge them if conceptually one bounded context.
3. Last resort: `forwardRef(() => OtherModule)` with a comment explaining the dependency cycle.

```ts
imports: [forwardRef(() => OrdersModule)]
// circular: User has many Orders; Order belongs to User. Type-only import in service.
```

## Dependency injection

### Constructor injection

```ts
@Injectable()
export class UsersService {
  constructor(
    private readonly users: Repository<User>,
    private readonly mailer: MailerService,
    @Inject('AUDIT_LOG') private readonly audit: AuditLog,
  ) {}
}
```

- `private readonly` — DI props don't get reassigned.
- Type-based tokens for classes; string/symbol tokens for non-class values via `@Inject('TOKEN')`.

### Custom providers

```ts
@Module({
  providers: [
    UsersService,
    {
      provide: 'AUDIT_LOG',
      useClass: ProductionAuditLog,
    },
    {
      provide: 'CONFIG_OPTIONS',
      useFactory: (config: ConfigService) => ({
        retries: config.get<number>('RETRIES', 3),
      }),
      inject: [ConfigService],
    },
    {
      provide: APP_GUARD,
      useClass: JwtAuthGuard,
    },
  ],
})
```

- `useClass` — bind interface to implementation.
- `useValue` — static value (constants, configs).
- `useFactory` — runtime computation; declare `inject` for factory deps.
- `useExisting` — alias another provider.

### Scopes

```ts
@Injectable({ scope: Scope.DEFAULT })  // singleton (implicit default)
@Injectable({ scope: Scope.REQUEST })  // per-request — propagates UP the dep chain
@Injectable({ scope: Scope.TRANSIENT }) // new instance per inject
```

`Scope.REQUEST` is contagious — anything injecting a request-scoped provider becomes request-scoped too. Use only when you genuinely need per-request state (e.g., request-bound logger context). Costly otherwise.

## Configuration

### ConfigModule setup

```ts
import { ConfigModule } from '@nestjs/config';
import * as Joi from 'joi';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      validationSchema: Joi.object({
        NODE_ENV: Joi.string().valid('development', 'test', 'production').required(),
        PORT: Joi.number().port().default(3000),
        DATABASE_URL: Joi.string().uri().required(),
      }),
      validationOptions: { abortEarly: false },
    }),
  ],
})
```

If `validationSchema` fails on boot, the app crashes loud — exactly what you want.

### Inject ConfigService

```ts
@Injectable()
export class DatabaseService {
  constructor(private readonly config: ConfigService) {
    const url = this.config.get<string>('DATABASE_URL', { infer: true });
  }
}
```

- `infer: true` — TypeScript infers return type from schema if you typed it.
- Provide default as 2nd arg only when truly optional: `config.get('CACHE_TTL', 60)`.
- Never `process.env.X` outside `config/` setup files.

### Per-feature config

```ts
// src/config/database.config.ts
import { registerAs } from '@nestjs/config';

export default registerAs('database', () => ({
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT ?? '5432', 10),
  url: process.env.DATABASE_URL,
}));

// inject in feature
@Injectable()
class DbModuleOptions {
  constructor(@Inject(databaseConfig.KEY) private cfg: ConfigType<typeof databaseConfig>) {}
}
```

## Validation pipe (global)

```ts
// src/main.ts
import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.useGlobalPipes(new ValidationPipe({
    whitelist: true,                  // strip unknown fields
    forbidNonWhitelisted: true,       // reject requests with unknown fields
    transform: true,                  // class-transformer auto-cast
    transformOptions: { enableImplicitConversion: true },
  }));

  await app.listen(3000);
}
bootstrap();
```

Without `whitelist + forbidNonWhitelisted`, extra payload fields silently pass through — that's a real source of mass-assignment bugs.

## Exception handling

### Built-in HTTP exceptions

```ts
throw new BadRequestException('email already in use');
throw new UnauthorizedException();                       // 401
throw new ForbiddenException('insufficient role');       // 403
throw new NotFoundException(`user ${id} not found`);     // 404
throw new ConflictException('version mismatch');         // 409
throw new UnprocessableEntityException(...);             // 422
throw new InternalServerErrorException();                // 500 (last resort)
```

For non-HTTP layers (microservice handlers, WebSocket gateways), throw plain `Error` subclasses; map at the boundary via filters or transports' built-in error handling.

### Custom exception filter

```ts
@Catch(MyDomainException)
export class MyDomainExceptionFilter implements ExceptionFilter {
  catch(exception: MyDomainException, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    response.status(exception.statusCode).json({
      error: exception.code,
      message: exception.message,
    });
  }
}
```

Apply via `@UseFilters(MyDomainExceptionFilter)` per controller/route, or globally:

```ts
app.useGlobalFilters(new MyDomainExceptionFilter());
```

### Catch-all filter for logging

```ts
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name);
  catch(exception: unknown, host: ArgumentsHost) {
    this.logger.error('unhandled', exception);
    // re-throw or format default response
  }
}
```

Add LAST in `useGlobalFilters` order (innermost catch-all).

## Lifecycle hooks

```ts
@Injectable()
export class WarmupService implements OnModuleInit, OnApplicationShutdown {
  async onModuleInit() {
    // run after this module's providers instantiated
    await this.warmCache();
  }
  async onApplicationShutdown(signal?: string) {
    // close DB pool, drain queues
    this.logger.log(`shutting down: ${signal}`);
    await this.cleanup();
  }
}
```

Enable shutdown hooks in main:

```ts
const app = await NestFactory.create(AppModule);
app.enableShutdownHooks();
```

Order:
- `OnModuleInit` — after module's deps ready, before app boots.
- `OnApplicationBootstrap` — after ALL modules ready.
- `OnModuleDestroy` / `OnApplicationShutdown` — graceful shutdown on SIGTERM/SIGINT.

## Logging

Built-in Logger:

```ts
@Injectable()
export class UsersService {
  private readonly logger = new Logger(UsersService.name);

  async create(dto: CreateUserDto) {
    this.logger.log(`creating user ${dto.email}`);
    try {
      // ...
    } catch (err) {
      this.logger.error('create failed', err);
      throw err;
    }
  }
}
```

For structured production logs, swap globally:

```ts
// option A: nestjs-pino
const app = await NestFactory.create(AppModule, { bufferLogs: true });
app.useLogger(app.get(Logger));

// option B: custom logger implementing LoggerService
app.useLogger(new MyStructuredLogger());
```

## Anti-patterns

- ❌ `new MyService()` outside test files — always inject.
- ❌ `process.env.X` in business code — use ConfigService.
- ❌ Global ValidationPipe disabled "for performance" — measure first.
- ❌ Catch-all `try/catch` swallowing errors silently.
- ❌ Mutating injected services (`this.someInjectedService.field = newValue`).
- ❌ Logic in controllers (anything beyond binding params and calling service).
- ❌ Importing controllers from other modules.
- ❌ `@Global()` on every shared module — defeats explicit-imports clarity.
- ❌ Using `forwardRef` to "fix" a real coupling problem.
- ❌ Module-level mutable state (no static class fields with non-readonly types).
