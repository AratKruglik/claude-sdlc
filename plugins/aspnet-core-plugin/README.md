# aspnet-core-plugin

ASP.NET Core backend + database stack provider. Auto-detects ASP.NET Core projects (presence of `appsettings.json` or `appsettings.Development.json`) and substitutes ASP.NET Core-specific agents into the pipeline. Designs the API contract for SPA frontends (pair with `vue-plugin` or `react-plugin`).

> Requires [`sdlc`](../sdlc/README.md) and [`csharp-foundation`](../csharp-foundation/README.md) — installed automatically as dependencies.

## What this plugin adds

| Component | Purpose |
|---|---|
| `stack.md` | Registers ASP.NET Core as a stack provider with `priority: 100`. |
| `agents/aspnet-core-architect.md` | Replaces vanilla `developer` for the **backend aspect**. Minimal API / MVC controllers, DTOs, FluentValidation, DI, Options pattern, authorization policies, EF Core entity stubs, Program.cs composition, and the API contract. (Sonnet) |
| `agents/efcore-specialist.md` | Runs in the extra `database` phase after development. Finalizes EF Core entity configurations (Fluent API, column types, indexes, unique constraints, cascade rules), generates + reviews migrations, runs `dotnet ef database update`. (Sonnet) |
| `skills/aspnet-conventions/SKILL.md` | Program.cs composition, Minimal API endpoint groups, DI lifetimes, Options pattern, FluentValidation, ProblemDetails error handling, structured logging, JWT authentication, HTTPS/HSTS, configuration layering, health checks. |
| `skills/efcore-patterns/SKILL.md` | DbContext design, ApplyConfigurationsFromAssembly, Fluent API (column types, relations, indexes), AsNoTracking projections, avoiding N+1 (Include / AsSplitQuery), transactions, parameterized raw SQL (FromSql). |
| `security-patterns.yaml` | ASP.NET Core security regex rules for `security-guidance` (via `/sdlc:security-init`). |
| `hooks/hooks.json` | Stop hook that runs `dotnet format` formatting after each session. |

Shared C# conventions (nullable reference types, records, async/await, naming, dotnet CLI, NuGet, xUnit/Moq/FluentAssertions) come from `csharp-foundation`.

## Pipeline shape on an ASP.NET Core project

```
business_analysis      → core's business-analyst       (Opus)
development (backend)  → aspnet-core-architect         (Sonnet)
development (frontend) → vue-architect / react-architect (Sonnet, if a SPA frontend plugin is installed)
database               → efcore-specialist             (Sonnet)  ← extra phase
qa                     → core's qa-engineer            (Sonnet)
security               → core's security-analyst       (Opus)    ← with ASP.NET Core-specific injection
documentation          → core's document-writer        (Haiku)

Post-pipeline:
  dotnet build --no-restore
  dotnet test --no-build
  dotnet format --verify-no-changes
  dotnet ef database update (if EF Core migrations exist)
```

## Prerequisites

- ASP.NET Core project targeting .NET 6.0 or later with an `appsettings.json` file.
- For the `dotnet format` Stop hook: .NET SDK installed locally or a Docker service named `app`.
- For the database phase: `Microsoft.EntityFrameworkCore.Tools` as a dev dependency (`dotnet add package Microsoft.EntityFrameworkCore.Tools`).
- For SPA frontend: install `vue-plugin` or `react-plugin` (wins the frontend aspect; aspnet-core-architect provides the API contract). Razor Pages / Blazor Server projects need no frontend plugin.
- There is no ASP.NET Core MCP server — agents use `dotnet` CLI via Bash (Docker-aware).

## Installation

```bash
/plugin marketplace add AratKruglik/claude-sdlc
/plugin install aspnet-core-plugin@sdlc-marketplace
# sdlc and csharp-foundation install as dependencies
```

## Verifying

```bash
cd /path/to/your/aspnet/project
/sdlc:list-stacks
# Expected output:
#   🎯 vanilla      priority=0   (always matches)
#   🎯 aspnet-core  priority=100 (matches: appsettings.json found)
```

If you see only `vanilla`, your project doesn't have an `appsettings.json` in any subdirectory (or it is a plain console / class-library project without ASP.NET Core).

## Running

```bash
/sdlc:start "Add user profile management"
```

Auto-detects ASP.NET Core, substitutes `aspnet-core-architect` for development, inserts the `database` phase after development, injects ASP.NET Core-specific guidance into security review, runs dotnet build/test/format checks at the end.

## Override stack manually

```bash
/sdlc:start --stack=vanilla "Quick prototype"
# Bypasses ASP.NET Core-specific agents and runs the vanilla pipeline.
```

## What this plugin does NOT include (yet)

- Blazor Server / WebAssembly agent (V2)
- gRPC / SignalR-specific agent (V2 — sub-stack plugin)
- API versioning (works via conventions, but no dedicated agent — V2)
- Frontend SPA pages — use `vue-plugin` (Vue) or `react-plugin` (React)
- Pure E2E browser tests (Playwright agent — V2 capability plugin)

If you need any of these, file an issue or submit a sub-stack plugin via PR.

## License

MIT — see [`../../LICENSE`](../../LICENSE).
