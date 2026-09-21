---
name: decorator-patterns
description: |
  NestJS decorator usage: built-in route/param/class decorators, custom decorators via `createParamDecorator` and `SetMetadata`, metadata reflection via `Reflector`. Apply when designing controllers, guards, interceptors, or custom decorators.

  Use this skill to:
  - Pick the right built-in decorator for routes, params, and DI.
  - Compose decorators (`@UseGuards(A, B) @UseInterceptors(C)`).
  - Build custom param decorators (e.g., `@CurrentUser()`).
  - Use metadata for role-based logic (Reflector + SetMetadata).
  - Avoid common decorator mistakes.

  Do NOT use this skill for:
  - General module/DI patterns (see nest-conventions).
  - GraphQL-specific decorators (see nest-advanced).
  - ORM entity decorators (see nest-data-layer).
user-invocable: false
paths: ["src/**/*.ts"]
---

# NestJS Decorator Patterns

NestJS is decorator-driven. Knowing which decorator does what — and how they compose — prevents most "weird DI / weird routing" bugs.

## Required tsconfig

```json
{
  "compilerOptions": {
    "experimentalDecorators": true,
    "emitDecoratorMetadata": true
  }
}
```

`emitDecoratorMetadata` is what makes runtime introspection (and class-validator/class-transformer) work. Never disable.

`reflect-metadata` polyfill must be imported once at the top of `main.ts`:

```ts
import 'reflect-metadata';
```

(NestJS does this implicitly via `@nestjs/core`, but if you write a script that uses decorators outside the Nest app, import it manually.)

## Class-level decorators

### `@Controller(prefix)`

```ts
@Controller('users')                            // routes prefixed /users
@Controller({ path: 'users', version: '1' })    // versioned: /v1/users (with VersioningType.URI)
export class UsersController {}
```

### `@Injectable(options?)`

```ts
@Injectable()                                   // singleton (default)
@Injectable({ scope: Scope.REQUEST })           // per-request
export class MyService {}
```

### `@Module(...)`

```ts
@Module({ imports, controllers, providers, exports })
export class UsersModule {}
```

### `@Global()`

```ts
@Global()
@Module({ providers: [...], exports: [...] })
export class LoggerModule {}
```

Use sparingly — see nest-conventions.

## Method-level: HTTP routing

```ts
@Get()                          // GET /users
@Get(':id')                     // GET /users/:id
@Post()
@Put(':id')
@Patch(':id')
@Delete(':id')
@All('debug')                   // any method
@Head()
@Options()
```

### Route options

```ts
@HttpCode(204)                  // override default status (200/201)
@Header('Cache-Control', 'no-store')
@Redirect('https://example.com', 301)
@Render('user-profile')         // for view engines (rare in API-only)
```

### Versioning

```ts
@Controller({ path: 'users', version: ['1', '2'] })
@Version('2')                   // override at method level
@Get()
findV2() {}
```

## Param decorators

```ts
@Get(':id')
async findOne(
  @Param('id') id: string,                          // route param
  @Query('include') include: string,                // ?include=...
  @Headers('authorization') authHeader: string,     // single header
  @Headers() allHeaders: Record<string, string>,    // all headers
  @Body() dto: UpdateUserDto,                       // request body (validated by ValidationPipe)
  @Body('email') email: string,                     // single field (no DTO validation — avoid)
  @Req() req: Request,                              // raw request (escape hatch)
  @Res() res: Response,                             // raw response (rare; breaks NestJS lifecycle)
  @Ip() ip: string,
  @HostParam() hosts: Record<string, string>,
  @Session() session: Record<string, unknown>,      // requires session middleware
) {}
```

### `@Res()` warning

When you inject `@Res()` and call `res.send()` directly, NestJS skips its response-handling pipeline (interceptors, exception filters that produce a response). Either:

- Don't inject `@Res()` — return data and let Nest handle the response.
- Or inject `@Res({ passthrough: true })` and still return data.

```ts
@Get()
async getStream(@Res({ passthrough: true }) res: Response): Promise<StreamableFile> {
  res.set({ 'Content-Type': 'application/octet-stream' });
  return new StreamableFile(buffer);
}
```

## Pipe binding

```ts
@Get(':id')
findOne(
  @Param('id', ParseIntPipe) id: number,                    // built-in pipe
  @Query('limit', new DefaultValuePipe(20), ParseIntPipe) limit: number,
  @Body(new ValidationPipe({ whitelist: true })) dto: CreateUserDto,
) {}
```

Pipes run in order, left-to-right. Combine for type-safe + validated input.

## Guard / Interceptor / Filter binding

```ts
@UseGuards(JwtAuthGuard, RolesGuard)
@UseInterceptors(LoggingInterceptor, CacheInterceptor)
@UseFilters(AllExceptionsFilter)
@UsePipes(new ValidationPipe({ transform: true }))
@Controller('users')
export class UsersController {}
```

Apply at route level OR globally:

```ts
// global guard via DI (preferred — can inject deps)
@Module({
  providers: [
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_INTERCEPTOR, useClass: LoggingInterceptor },
    { provide: APP_FILTER, useClass: AllExceptionsFilter },
    { provide: APP_PIPE, useClass: ValidationPipe },
  ],
})

// or in main.ts (cannot inject DI)
app.useGlobalGuards(new JwtAuthGuard());
```

`APP_GUARD` etc. are imported from `@nestjs/core` constants.

## Metadata via `SetMetadata` + `Reflector`

For role-based or feature-flag logic, attach metadata to a route, then read in a guard.

### Define a metadata decorator

```ts
// src/auth/roles.decorator.ts
import { SetMetadata } from '@nestjs/common';

export const ROLES_KEY = 'roles';
export const Roles = (...roles: string[]) => SetMetadata(ROLES_KEY, roles);
```

### Apply on route

```ts
@Controller('admin')
@UseGuards(JwtAuthGuard, RolesGuard)
export class AdminController {
  @Get('users')
  @Roles('admin', 'super-admin')
  listUsers() { ... }
}
```

### Read in guard

```ts
@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const required = this.reflector.getAllAndOverride<string[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!required) return true;
    const { user } = context.switchToHttp().getRequest();
    return required.some(r => user.roles?.includes(r));
  }
}
```

`getAllAndOverride` walks handler → class metadata; method-level wins. `getAllAndMerge` combines both.

## Custom param decorator

```ts
// src/auth/current-user.decorator.ts
import { createParamDecorator, ExecutionContext } from '@nestjs/common';

export const CurrentUser = createParamDecorator(
  (data: keyof User | undefined, ctx: ExecutionContext) => {
    const request = ctx.switchToHttp().getRequest();
    const user = request.user as User;
    return data ? user?.[data] : user;
  },
);
```

Usage:

```ts
@Get('me')
me(@CurrentUser() user: User) {}

@Get('email')
myEmail(@CurrentUser('email') email: string) {}
```

Works in HTTP, GraphQL, WebSocket contexts via `switchToHttp` / `switchToWs` / GraphQL execution context wrapper.

## Composing decorators

For a frequently-used combo, build a meta-decorator with `applyDecorators`:

```ts
// src/auth/auth.decorator.ts
import { applyDecorators, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiUnauthorizedResponse } from '@nestjs/swagger';

export function Auth(...roles: string[]) {
  return applyDecorators(
    UseGuards(JwtAuthGuard, RolesGuard),
    Roles(...roles),
    ApiBearerAuth(),
    ApiUnauthorizedResponse({ description: 'unauthorized' }),
  );
}
```

Usage:

```ts
@Auth('admin')
@Get('users')
listUsers() { ... }
```

Reduces decorator stack noise when 4+ decorators repeat.

## Anti-patterns

- ❌ Using `Reflect.getMetadata(...)` directly — use `Reflector.get()` (NestJS API). It handles inheritance correctly.
- ❌ `@Body('field')` instead of a typed DTO — bypasses class-validator, no type safety.
- ❌ Injecting `@Res()` then forgetting `passthrough: true` — breaks interceptors.
- ❌ Multiple class-level `@UseGuards(A) @UseGuards(B)` — last one wins; combine into one: `@UseGuards(A, B)`.
- ❌ Custom decorator without preserving type info — declare return type explicitly.
- ❌ `SetMetadata('key', val)` inline at the route — make a named decorator (`Roles(...)`) so it's discoverable.
- ❌ `@Controller('/users/')` — no leading or trailing slash; Nest adds them.
