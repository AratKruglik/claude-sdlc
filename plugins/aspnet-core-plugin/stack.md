---
stack: aspnet-core
aspects: [backend, database]
priority: 100
detect:
  any:
    - file_exists: "**/appsettings.json"
    - file_exists: "**/appsettings.Development.json"
---

# ASP.NET Core Stack Profile (backend + database)

Registers ASP.NET Core projects with the SDLC pipeline. Auto-detected by the presence of `appsettings.json` or `appsettings.Development.json` — the canonical configuration file for ASP.NET Core applications.

This plugin owns the **backend** and **database** aspects. The `aspnet-core-architect` handles Minimal API endpoints or MVC controllers, the DI container, validation, authentication / authorization, and the API contract for SPA frontend plugins:

- Minimal API / MVC controllers → handled by `aspnet-core-architect` (backend aspect)
- EF Core migrations, DbContext finalization → handled by `efcore-specialist` (database aspect, extra phase)
- Vue / React SPA → a frontend-aspect plugin (`vue-plugin`, `react-plugin`) wins the frontend aspect; `aspnet-core-architect` provides the API contract it consumes

## Agents per phase

```yaml
business_analysis: business-analyst         # core agent (aspect-agnostic)
development:
  backend: aspnet-core-architect            # owned by this plugin
database: efcore-specialist                 # extra phase, aspect=database
qa: qa-engineer                             # core agent (aspect-agnostic in v1)
security: security-analyst                  # core agent
documentation: document-writer             # core agent
```

Note: this plugin does NOT declare `development.frontend`. That slot is filled by whichever frontend-aspect plugin is active in the project (for SPA frontends). Razor Pages and server-side Blazor are handled by `aspnet-core-architect` under the backend aspect.

## Convention skills to apply

- csharp-foundation:csharp-conventions
- csharp-foundation:dotnet-tooling
- csharp-foundation:dotnet-testing
- aspnet-core-plugin:aspnet-conventions
- aspnet-core-plugin:efcore-patterns

## Extra phases

- name: database
  after: development
  agent: efcore-specialist
  aspect: database
  description: |
    Finalize EF Core entity configurations (Fluent API, indexes, constraints, relations),
    generate the migration via dotnet ef migrations add, review the generated SQL,
    run dotnet ef database update and verify the schema. Skip if the development phase
    made no entity or DbContext changes.

## Phase prompts injection

For development phase (backend aspect), inject:
> You are working on the **backend** aspect of an **ASP.NET Core** project. Your scope:
> - Minimal API endpoints or MVC controllers, DTOs, services, validators, authorization (policies / resource-based), entity model stubs (EF Core navigation properties, basic column attributes — efcore-specialist finalizes indexes and generates migrations), background services (IHostedService / BackgroundService), and Program.cs DI registrations.
> - For SPA frontends (Vue/React) the frontend-aspect agent runs separately and handles UI — you design and document the API contract (endpoint shape + DTO) it consumes. For Razor Pages / server-side Blazor projects, you render the views yourself.
>
> Apply `aspnet-core-plugin:aspnet-conventions`:
> - **Program.cs composition:** register services in the correct DI lifetime (Scoped for per-request, Singleton for shared, Transient for lightweight stateless). Use the Options pattern (`services.Configure<MyOptions>(config.GetSection("MySection"))`) — never pass raw `IConfiguration` into services.
> - **Minimal API vs MVC:** prefer Minimal API for new, simple endpoints; use MVC controllers when the project already uses them or when cross-cutting concerns (filters, model binders) are needed.
> - **Validation:** use FluentValidation or DataAnnotations + `app.UseRequestValidation()`. Never validate inline in handlers/actions.
> - **Authentication / Authorization:** wire `AddAuthentication` + `AddAuthorization` in Program.cs. Use policy-based or resource-based authorization (`IAuthorizationService`). Never inline `user.IsInRole("Admin")` checks.
> - **Error handling:** use `ProblemDetails` (RFC 9457) via `app.UseExceptionHandler` / `Results.Problem()`. Never return raw exception messages.
> - **Secrets:** read all credentials from `IConfiguration` (environment variables, User Secrets in dev, Azure Key Vault / AWS Secrets Manager in prod). Never hardcode secrets or connection strings.
> - **Middleware ordering:** `UseHttpsRedirection` → `UseStaticFiles` → `UseRouting` → `UseAuthentication` → `UseAuthorization` → `MapControllers` / `MapMinimalApi`.
>
> Apply `csharp-foundation:csharp-conventions` (nullable reference types, records for DTOs, async/await + CancellationToken) and `csharp-foundation:dotnet-tooling` (read global.json and .csproj for the .NET version).
>
> After writing code:
> - `dotnet build` — fix any compiler errors.
> - `dotnet format` (auto-formats; do not iterate on style manually).
> - `dotnet test` (if tests exist; advisory — don't fail on expected red tests for the qa-engineer to fill in).

For qa phase, inject:
> Apply `csharp-foundation:dotnet-testing` plus ASP.NET Core-specific test types:
> - `WebApplicationFactory<TProgram>` for HTTP integration tests — boots the real pipeline in-memory, uses `HttpClient` for requests.
> - `IClassFixture<WebApplicationFactory<TProgram>>` for shared factory across multiple tests.
> - xUnit `[Fact]` / `[Theory]` for unit tests; FluentAssertions for all assertions.
> - Use Moq or NSubstitute to stub repository/service interfaces at the unit level; let the real implementation run in integration tests.
> - EF Core integration tests: use `UseInMemoryDatabase` for fast isolation, or Testcontainers + SQL Server/PostgreSQL for fidelity.
>
> ```csharp
> public class UsersEndpointTests : IClassFixture<WebApplicationFactory<Program>>
> {
>     private readonly HttpClient _client;
>
>     public UsersEndpointTests(WebApplicationFactory<Program> factory)
>         => _client = factory.CreateClient();
>
>     [Fact]
>     public async Task GetUser_ValidId_ReturnsOk()
>     {
>         var response = await _client.GetAsync("/users/1");
>         response.Should().HaveStatusCode(HttpStatusCode.OK);
>         var user = await response.Content.ReadFromJsonAsync<UserDto>();
>         user!.Email.Should().NotBeNullOrWhiteSpace();
>     }
> }
> ```
>
> Run: `dotnet test`

For security phase, inject:
> Check ASP.NET Core-specific issues in addition to OWASP Top 10:
> - **Authorization:** every protected endpoint is guarded by `[Authorize]`, a named policy (`RequireAuthorization("PolicyName")`), or `IAuthorizationService.AuthorizeAsync`. No endpoint is accidentally left open. No inline `User.IsInRole("Admin")` checks outside of Razor views.
> - **Anti-forgery (CSRF):** browser-facing form POST/PUT/DELETE endpoints have `[ValidateAntiForgeryToken]` or the Minimal API `IAntiforgery` equivalent. Stateless token/JWT APIs are exempt — verify the exemption is intentional.
> - **HTTPS / HSTS:** `UseHttpsRedirection()` and `UseHsts()` are in the pipeline. HSTS is not applied in development (`app.Environment.IsDevelopment()` guard). `Strict-Transport-Security` max-age is ≥ 1 year in production.
> - **EF Core / SQL injection:** `FromSqlRaw` and `ExecuteSqlRaw` with string interpolation are flagged. Use `FromSql` with FormattableString or `FromSqlRaw` with SqlParameter. Prefer LINQ queries — they are parameterized by default.
> - **Secrets:** no credentials, connection strings, or API keys in `appsettings.json` or source. All from environment variables, User Secrets (`dotnet user-secrets`), or a secrets manager (Azure Key Vault, AWS Secrets Manager, HashiCorp Vault).
> - **CORS:** `AllowAnyOrigin` combined with `AllowCredentials` is forbidden (blocked by browsers and a security misconfiguration). Specify explicit allowed origins for credentialed requests.
> - **Data Protection:** cookie authentication and anti-forgery tokens use ASP.NET Core Data Protection. Configure `AddDataProtection()` with persistent key storage (Azure Blob, file system) in production — in-memory keys do not survive restarts.
> - **Over-posting / mass assignment:** endpoints bind DTOs, not entity classes directly. Separate Create vs Update DTOs where field sets differ.
> - **Content Security Policy:** for server-rendered pages, add a CSP header middleware or response header. Verify no `unsafe-inline` / `unsafe-eval` for scripts.

## Post-pipeline checks

- `dotnet build --no-restore`
- `dotnet test --no-build`
- `dotnet format --verify-no-changes`
- `dotnet ef database update` (if EF Core migrations exist)

These run after the documentation phase. They are advisory — failures are reported but do not retry.

## MCP integration

ASP.NET Core has no standard MCP server equivalent to Laravel Boost. Agents use `dotnet` CLI via Bash (or `docker compose exec -T app dotnet …` in Dockerized setups) for code generation, migration management, and schema introspection. The pipeline runs fully without any MCP server.
