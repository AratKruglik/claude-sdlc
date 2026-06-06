---
name: csharp-conventions
description: |
  Modern C# idioms for any .NET project (C# 10+, .NET 6+): nullable reference types, records, readonly structs, primary constructors, pattern matching, async/await with CancellationToken, IDisposable/IAsyncDisposable, file-scoped namespaces, var usage, naming conventions (PascalCase members, _camelCase fields, I-prefixed interfaces), and class design rules. Apply whenever the project is a .NET 6+ project. Stack-agnostic — referenced by every .NET plugin in the marketplace.

  Use this skill to:
  - Write self-documenting immutable value types with records and readonly structs.
  - Handle nullable reference types explicitly to eliminate NullReferenceException at compile time.
  - Implement async/await correctly with CancellationToken propagation and ConfigureAwait(false) in libraries.
  - Dispose unmanaged resources correctly via IDisposable / IAsyncDisposable and using statements.
  - Apply C# pattern matching (switch expressions, property patterns, list patterns) for cleaner branching logic.

  Do NOT use this skill for:
  - Framework-specific idioms (ASP.NET Core controllers, minimal APIs, EF Core — those live in aspnet-core-plugin skills).
  - Build tooling (dotnet CLI, NuGet, csproj) — see csharp-foundation:dotnet-tooling.
  - Testing patterns — see csharp-foundation:dotnet-testing.
---

# C# Conventions (stack-agnostic, C# 10+ / .NET 6+)

This skill encodes idioms that reduce bugs and improve readability in any C# codebase. Apply alongside the active framework plugin's conventions skill (e.g., `aspnet-core-plugin:aspnet-conventions`).

## Detection

Project is C# 10+ / .NET 6+ when:
- `.csproj` has `<TargetFramework>net6.0</TargetFramework>` or higher (`net7.0`, `net8.0`, `net9.0`, `net10.0`).
- `global.json` pins `sdk.version` to 6.0.x or higher.

Read the `.csproj` `<TargetFramework>` before making any version-specific decisions.

## Nullable reference types — eliminate null surprises

Enable in every project. New projects get it by default from `dotnet new`; older projects need a one-time migration.

```xml
<!-- .csproj: enable project-wide -->
<PropertyGroup>
  <Nullable>enable</Nullable>
</PropertyGroup>
```

```csharp
// Non-nullable: compiler guarantees non-null, no null check needed
public string Name { get; }

// Nullable: caller must check before dereferencing
public string? MiddleName { get; }

// Null-forgiving operator — use only when you have proven non-null
var definitelySet = _cache[key]!;

// Null-conditional + null-coalescing
string display = user?.FullName ?? "Guest";
```

**Never silence nullable warnings with `!` without a comment explaining why the value is guaranteed non-null.** Prefer redesigning the API to avoid the need.

## Records — prefer for value objects and DTOs

Use `record` (class) for immutable reference-type value objects; `readonly record struct` for small value types.

```csharp
// Immutable DTO — all positional parameters become init-only properties
public record Money(decimal Amount, string Currency)
{
    // Compact validation in the record body
    public Money
    {
        if (Amount < 0) throw new ArgumentOutOfRangeException(nameof(Amount), "Amount must be non-negative.");
        ArgumentException.ThrowIfNullOrWhiteSpace(Currency);
    }

    public Money Add(Money other)
    {
        if (Currency != other.Currency) throw new InvalidOperationException("Currency mismatch.");
        return this with { Amount = Amount + other.Amount };
    }
}

// Small stack-allocated value type
public readonly record struct Point(double X, double Y);
```

`with` expressions create modified copies — preserve immutability instead of mutating.

## Pattern matching — eliminate casting and chains

```csharp
// Switch expression (C# 8+)
string Describe(object obj) => obj switch
{
    int n when n > 0  => $"positive int: {n}",
    int n             => $"non-positive int: {n}",
    string s          => $"string of length {s.Length}",
    null              => "null",
    _                 => obj.GetType().Name,
};

// Property patterns (C# 8+)
string Category(Order order) => order switch
{
    { Total: > 1000, IsPriority: true } => "VIP",
    { Total: > 500 }                    => "Large",
    _                                   => "Standard",
};

// List patterns (C# 11+)
bool StartsWithOne(int[] nums) => nums is [1, ..];
```

Never cast (`(T)obj`) without a prior `is` check. Use type patterns (`obj is T t`) to combine the check and the cast.

## Async/await — correct propagation

```csharp
// Propagate CancellationToken everywhere
public async Task<User> GetUserAsync(int id, CancellationToken ct = default)
{
    var user = await _repository.FindAsync(id, ct);
    return user ?? throw new KeyNotFoundException($"User {id} not found.");
}

// ConfigureAwait(false) in library code (not in application code / controllers)
var data = await _client.GetStringAsync(url, ct).ConfigureAwait(false);

// Avoid async void — use async Task instead
// BAD:  public async void OnSomeEvent(...)
// GOOD: public async Task HandleAsync(...)

// Fire-and-forget requires explicit error handling
_ = Task.Run(async () =>
{
    try { await DoBackgroundWorkAsync(); }
    catch (Exception ex) { _logger.LogError(ex, "Background work failed"); }
});
```

**Never use `.Result` or `.Wait()` on a Task** — it risks deadlocks on synchronisation-context–bound runtimes (ASP.NET Core, WinForms).

## IDisposable / IAsyncDisposable — resource cleanup

```csharp
// Implement IDisposable when owning unmanaged resources or disposable children
public sealed class DatabaseConnection : IDisposable
{
    private readonly SqlConnection _connection;
    private bool _disposed;

    public DatabaseConnection(string connectionString)
        => _connection = new SqlConnection(connectionString);

    public void Dispose()
    {
        if (_disposed) return;
        _connection.Dispose();
        _disposed = true;
    }
}

// Prefer IAsyncDisposable for async cleanup (e.g., flushing async streams)
public sealed class FileWriter : IAsyncDisposable
{
    private readonly StreamWriter _writer;

    public async ValueTask DisposeAsync() => await _writer.DisposeAsync();
}

// Always use using declarations / using statements
await using var writer = new FileWriter(path);
using var conn = new DatabaseConnection(connStr);
```

**Seal classes that implement `IDisposable` unless they are designed for inheritance.** Add a `protected virtual void Dispose(bool disposing)` pattern only when the class is unsealed.

## Naming conventions

| Symbol | Convention | Example |
|---|---|---|
| Types, methods, properties, events | `PascalCase` | `OrderService`, `GetUserAsync` |
| Private / protected fields | `_camelCase` | `_repository`, `_logger` |
| Local variables, parameters | `camelCase` | `userId`, `cancellationToken` |
| Constants, static readonly fields | `PascalCase` | `MaxRetries`, `DefaultTimeout` |
| Interfaces | `I` prefix + `PascalCase` | `IOrderRepository` |
| Generic type parameters | `T` or descriptive `T`-prefix | `T`, `TKey`, `TValue` |
| Async methods | `Async` suffix | `GetOrderAsync`, `SaveAsync` |

```csharp
public interface IUserRepository
{
    Task<User?> FindAsync(int id, CancellationToken ct = default);
    Task<IReadOnlyList<User>> ListActiveAsync(CancellationToken ct = default);
}

public sealed class UserRepository : IUserRepository
{
    private readonly AppDbContext _db;

    public UserRepository(AppDbContext db) => _db = db;

    public async Task<User?> FindAsync(int id, CancellationToken ct = default)
        => await _db.Users.FindAsync(new object[] { id }, ct);

    public async Task<IReadOnlyList<User>> ListActiveAsync(CancellationToken ct = default)
        => await _db.Users.Where(u => u.IsActive).ToListAsync(ct);
}
```

## File-scoped namespaces (C# 10+)

Prefer file-scoped namespaces to reduce indentation:

```csharp
// Preferred (C# 10+)
namespace MyApp.Users;

public record User(int Id, string Email);

// Avoid for new code (block-scoped adds one level of indentation)
namespace MyApp.Users
{
    public record User(int Id, string Email);
}
```

## var — local type inference

```csharp
// Good — type is clear from the right-hand side
var users = new List<User>();
var order = await _orderRepo.FindAsync(id, ct);
var (first, rest) = GetParts();

// Avoid — type is not obvious
var result = Process(data);   // What type is result?
```

`var` is for local variables only. Never use for fields, parameters, or return types.

## Class design rules

- **Prefer composition over inheritance** for behaviour reuse; reserve inheritance for genuine is-a relationships.
- **Seal concrete classes** that are not designed for extension (`sealed class`).
- **Keep constructors lean** — no business logic; use factory methods or initialisation helpers for complex setup.
- **Minimise public API surface** — `internal` by default, `public` only when the type/member is part of the contract.
- **No static mutable state** — static fields holding mutable objects are a concurrency and testability hazard.

```csharp
// Prefer static factory when construction can fail
public sealed class Email
{
    private readonly string _value;
    private Email(string value) => _value = value;

    public static Email Parse(string raw)
    {
        if (!raw.Contains('@')) throw new FormatException($"'{raw}' is not a valid email.");
        return new Email(raw.Trim().ToLowerInvariant());
    }

    public override string ToString() => _value;
}
```
