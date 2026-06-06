---
name: aspnet-conventions
description: |
  ASP.NET Core web framework conventions: Minimal API vs MVC controllers, Program.cs composition, DI lifetimes (Scoped/Singleton/Transient), Options pattern with IOptions<T>, middleware ordering (HTTPS redirect → routing → authentication → authorization), model binding and validation (FluentValidation / DataAnnotations), ProblemDetails error handling, structured logging with ILogger<T>, configuration layering (appsettings.json + environment variables + User Secrets), and health checks. Works alongside csharp-foundation:csharp-conventions and aspnet-core-plugin:efcore-patterns.

  Use this skill to:
  - Compose Program.cs correctly — register services, configure middleware in the right order, map endpoints.
  - Apply the Options pattern to avoid passing raw IConfiguration into services.
  - Write Minimal API endpoint groups with typed results and authorization.
  - Handle cross-cutting errors uniformly with ProblemDetails.
  - Configure structured logging and health checks for production readiness.

  Do NOT use this skill for:
  - EF Core entity configuration and migrations — see aspnet-core-plugin:efcore-patterns.
  - C# language idioms — see csharp-foundation:csharp-conventions.
  - Testing — see csharp-foundation:dotnet-testing.
---

# ASP.NET Core Conventions

## Program.cs — canonical composition order

```csharp
var builder = WebApplication.CreateBuilder(args);

// 1. Configuration (auto-loaded: appsettings.json → appsettings.{Env}.json → env vars → User Secrets in dev)
// Override or extend:
builder.Configuration.AddEnvironmentVariables(prefix: "MYAPP_");

// 2. Services
builder.Services.AddControllers();            // MVC controllers
// OR for Minimal API: no AddControllers needed

// Options pattern — never inject IConfiguration directly into services
builder.Services.Configure<JwtOptions>(builder.Configuration.GetSection("Jwt"));
builder.Services.Configure<SmtpOptions>(builder.Configuration.GetSection("Smtp"));

// DI registrations
builder.Services.AddScoped<IUserRepository, UserRepository>();      // per-request state
builder.Services.AddSingleton<IEmailTemplateCache, EmailTemplateCache>(); // shared, thread-safe
builder.Services.AddTransient<IPasswordHasher, Argon2PasswordHasher>();   // stateless

// Authentication + Authorization
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o => builder.Configuration.Bind("Jwt", o));
builder.Services.AddAuthorization(o =>
{
    o.AddPolicy("ProfileOwner", p => p.AddRequirements(new ProfileOwnerRequirement()));
});
builder.Services.AddSingleton<IAuthorizationHandler, ProfileOwnerHandler>();

// Validation (FluentValidation)
builder.Services.AddValidatorsFromAssembly(typeof(Program).Assembly);

// EF Core
builder.Services.AddDbContext<AppDbContext>(o =>
    o.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")
                ?? throw new InvalidOperationException("Connection string not configured.")));

// Data Protection
builder.Services.AddDataProtection()
    .SetApplicationName("MyApp")
    .PersistKeysToFileSystem(new DirectoryInfo("/var/keys"))  // prod: use Azure Blob / Redis
    .ProtectKeysWithCertificate(/* ... */);

// Health checks
builder.Services.AddHealthChecks()
    .AddDbContextCheck<AppDbContext>();

// API doc (optional)
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// 3. Middleware pipeline — ORDER MATTERS
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
    app.UseDeveloperExceptionPage();
}
else
{
    app.UseExceptionHandler("/error");   // maps to a ProblemDetails endpoint
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();

app.UseRouting();

app.UseAuthentication();
app.UseAuthorization();

// 4. Endpoints
app.MapControllers();                    // MVC
app.MapUserEndpoints();                  // Minimal API extension method
app.MapHealthChecks("/health");

app.Run();
```

**Never** call `UseAuthentication()` / `UseAuthorization()` before `UseRouting()` — authentication middleware needs the routing context to resolve endpoint metadata.

## Minimal API — endpoint groups

Organize endpoints in extension methods per feature:

```csharp
public static class UserEndpoints
{
    public static IEndpointRouteBuilder MapUserEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/users")
            .WithTags("Users")
            .RequireAuthorization();           // all endpoints in this group require auth

        group.MapGet("/{id:int}", GetUserAsync)
             .WithName("GetUser")
             .Produces<UserDto>()
             .ProducesProblem(404);

        group.MapPost("/", CreateUserAsync)
             .AllowAnonymous()                 // explicit exception for registration
             .Accepts<CreateUserCommand>("application/json")
             .Produces<UserDto>(201)
             .ProducesValidationProblem();

        group.MapPut("/{id:int}", UpdateUserAsync)
             .RequireAuthorization("ProfileOwner");

        group.MapDelete("/{id:int}", DeleteUserAsync)
             .RequireAuthorization("Admin");

        return app;
    }

    private static async Task<Results<Ok<UserDto>, NotFound>> GetUserAsync(
        int id, IUserService service, CancellationToken ct)
    {
        var user = await service.GetAsync(id, ct);
        return user is null ? TypedResults.NotFound() : TypedResults.Ok(user);
    }

    private static async Task<Results<Created<UserDto>, ValidationProblem>> CreateUserAsync(
        CreateUserCommand cmd, IValidator<CreateUserCommand> validator,
        IUserService service, CancellationToken ct)
    {
        var result = await validator.ValidateAsync(cmd, ct);
        if (!result.IsValid) return TypedResults.ValidationProblem(result.ToDictionary());

        var user = await service.CreateAsync(cmd, ct);
        return TypedResults.Created($"/users/{user.Id}", user);
    }
}
```

**Use `TypedResults.*`** (not `Results.*`) for strongly typed return types — it enables better Swagger documentation and compile-time safety.

## Options pattern — never inject IConfiguration directly

```csharp
// appsettings.json:
// {
//   "Jwt": {
//     "Issuer": "https://auth.example.com",
//     "Audience": "https://api.example.com",
//     "Secret": ""   ← read from env var JWT__SECRET, not here
//   }
// }

public sealed class JwtOptions
{
    public required string Issuer { get; init; }
    public required string Audience { get; init; }
    public required string Secret { get; init; }
}

// Service — inject IOptions<JwtOptions>, not IConfiguration
public sealed class JwtTokenService(IOptions<JwtOptions> options)
{
    private readonly JwtOptions _opts = options.Value;

    public string GenerateToken(User user)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_opts.Secret));
        // ...
    }
}
```

Use `IOptionsSnapshot<T>` (scoped, reloads per request) for options that change at runtime. Use `IOptionsMonitor<T>` for singleton services that need live reloads.

## Validation — FluentValidation

```csharp
public sealed class CreateUserCommandValidator : AbstractValidator<CreateUserCommand>
{
    public CreateUserCommandValidator()
    {
        RuleFor(x => x.Email)
            .NotEmpty()
            .EmailAddress()
            .MaximumLength(256);

        RuleFor(x => x.Password)
            .NotEmpty()
            .MinimumLength(8)
            .Matches(@"[A-Z]").WithMessage("Password must contain at least one uppercase letter.")
            .Matches(@"[0-9]").WithMessage("Password must contain at least one digit.");

        RuleFor(x => x.DisplayName)
            .NotEmpty()
            .MaximumLength(100);
    }
}
```

Register all validators via `services.AddValidatorsFromAssembly(typeof(Program).Assembly)`. Call `await validator.ValidateAsync(cmd, ct)` explicitly in Minimal API handlers; MVC controllers with `[ApiController]` call `ModelState` validation automatically when using DataAnnotations.

## Error handling — ProblemDetails (RFC 9457)

```csharp
// Global handler — returns ProblemDetails for all unhandled exceptions
app.UseExceptionHandler(errorApp =>
{
    errorApp.Run(async context =>
    {
        var exception = context.Features.Get<IExceptionHandlerFeature>()?.Error;
        var problem = exception switch
        {
            KeyNotFoundException e => new ProblemDetails
                { Status = 404, Title = "Not Found", Detail = e.Message },
            UnauthorizedAccessException e => new ProblemDetails
                { Status = 403, Title = "Forbidden", Detail = e.Message },
            _ => new ProblemDetails
                { Status = 500, Title = "Internal Server Error" }
        };
        context.Response.StatusCode = problem.Status ?? 500;
        await context.Response.WriteAsJsonAsync(problem);
    });
});

// In Minimal API handlers — return typed problem results
TypedResults.NotFound()                    // 404
TypedResults.Forbid()                      // 403
TypedResults.Problem(detail: "...", statusCode: 422)   // custom
TypedResults.ValidationProblem(errors)     // 400 with field errors
```

**Never** return raw exception messages — they leak implementation details. Use `ProblemDetails` with a sanitized `Detail` and a correlation ID in the `Extensions` dictionary.

## Structured logging

```csharp
public sealed class UserService(ILogger<UserService> logger, IUserRepository repo)
{
    public async Task<User> CreateAsync(CreateUserCommand cmd, CancellationToken ct)
    {
        logger.LogInformation("Creating user {Email}", cmd.Email);

        var user = User.Create(cmd.Email, cmd.Password);
        await repo.SaveAsync(user, ct);

        logger.LogInformation("User {UserId} created successfully", user.Id);
        return user;
    }
}
```

- **Never** `string.Format` / `$"..."` in log messages — use structured logging placeholders `{PropertyName}`.
- **Never** log sensitive data (passwords, tokens, PII).
- Prefer `LogInformation` / `LogWarning` / `LogError` over the generic `Log(LogLevel, ...)` overload.
- Use `Serilog` or `Microsoft.Extensions.Logging` — configure sinks in `appsettings.json`, not in code.

## Authentication — JWT Bearer

```csharp
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = builder.Configuration["Jwt:Issuer"],
            ValidAudience = builder.Configuration["Jwt:Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(builder.Configuration["Jwt:Secret"]
                    ?? throw new InvalidOperationException("Jwt:Secret not configured."))),
            ClockSkew = TimeSpan.FromMinutes(5),
        };
    });
```

- **Never** disable `ValidateLifetime` or `ValidateIssuerSigningKey` in production.
- Store the signing secret in environment variables (`JWT__SECRET`) or a secrets manager — never in `appsettings.json`.

## Configuration layering

ASP.NET Core reads configuration in this order (later sources override earlier ones):

1. `appsettings.json`
2. `appsettings.{Environment}.json` (e.g., `appsettings.Production.json`)
3. Environment variables (use `__` for nesting: `Jwt__Secret`)
4. User Secrets (development only — `dotnet user-secrets set "Jwt:Secret" "..."`)
5. Command-line arguments

**Never commit secrets** — `appsettings.Development.json` is for non-sensitive dev overrides only. Use User Secrets locally, environment variables in CI, and Key Vault / Secrets Manager in production.

## Health checks

```csharp
builder.Services.AddHealthChecks()
    .AddDbContextCheck<AppDbContext>("database")
    .AddUrlGroup(new Uri("https://api.external.com/health"), "external-api");

app.MapHealthChecks("/health", new HealthCheckOptions
{
    ResponseWriter = UIResponseWriter.WriteHealthCheckUIResponse  // aspnetcore-healthchecks-ui
});
app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready"),
});
app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = _ => false,  // liveness is just "app is running"
});
```

Expose `/health/live` (Kubernetes liveness probe) and `/health/ready` (readiness probe) as separate endpoints. Protect the full `/health` endpoint with authorization in production.
