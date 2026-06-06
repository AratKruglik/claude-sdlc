---
name: efcore-patterns
description: |
  Entity Framework Core patterns for ASP.NET Core projects: DbContext design, code-first entity configuration (Fluent API via IEntityTypeConfiguration<T>), relations (HasOne/HasMany, cascade/restrict/set-null), indexes and unique constraints, projection to DTOs (Select + AsNoTracking), avoiding N+1 (Include, AsSplitQuery), transactions, parameterized raw SQL (FromSql with FormattableString), and connection string from IConfiguration. Works alongside aspnet-core-plugin:aspnet-conventions.

  Use this skill to:
  - Design a clean DbContext with ApplyConfigurationsFromAssembly for scalable entity registration.
  - Configure entity properties (column types, max length, precision, nullability) via Fluent API.
  - Avoid N+1 query problems with explicit Include / projection to DTOs.
  - Use transactions correctly for multi-entity operations.
  - Write parameterized raw SQL safely when LINQ is not expressive enough.

  Do NOT use this skill for:
  - Migration generation commands (that is efcore-specialist's job in the database extra phase).
  - ASP.NET Core middleware, DI, or validation — see aspnet-core-plugin:aspnet-conventions.
  - C# language idioms — see csharp-foundation:csharp-conventions.
---

# EF Core Patterns

## DbContext design

```csharp
public sealed class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<User> Users => Set<User>();
    public DbSet<Order> Orders => Set<Order>();
    public DbSet<OrderLine> OrderLines => Set<OrderLine>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // Discover all IEntityTypeConfiguration<T> in the assembly automatically
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
    }
}
```

**Use `ApplyConfigurationsFromAssembly`** — it discovers all `IEntityTypeConfiguration<T>` implementations automatically, avoiding the need to register each entity manually in `OnModelCreating`.

**Use `DbSet<T>` expression-bodied properties** (`=> Set<T>()`) to avoid null warnings and simplify the class.

## Entity configuration — Fluent API

```csharp
public sealed class OrderConfiguration : IEntityTypeConfiguration<Order>
{
    public void Configure(EntityTypeBuilder<Order> builder)
    {
        builder.ToTable("orders");
        builder.HasKey(o => o.Id);

        builder.Property(o => o.Status)
               .HasConversion<string>()   // store enum as string for readability
               .HasMaxLength(50)
               .IsRequired();

        builder.Property(o => o.Total)
               .HasPrecision(18, 2)
               .IsRequired();

        builder.Property(o => o.CreatedAt)
               .IsRequired();

        builder.Property(o => o.Notes)
               .HasMaxLength(1000)
               .IsRequired(false);

        builder.HasIndex(o => o.CustomerId);
        builder.HasIndex(o => new { o.Status, o.CreatedAt });

        builder.HasOne(o => o.Customer)
               .WithMany(c => c.Orders)
               .HasForeignKey(o => o.CustomerId)
               .OnDelete(DeleteBehavior.Restrict);   // don't cascade-delete orders with customer

        builder.HasMany(o => o.Lines)
               .WithOne(l => l.Order)
               .HasForeignKey(l => l.OrderId)
               .OnDelete(DeleteBehavior.Cascade);   // deleting an order removes its lines
    }
}
```

### `OnDelete` guidance

| Scenario | Behaviour |
|---|---|
| Child data is meaningless without parent (e.g., order lines) | `DeleteBehavior.Cascade` |
| Child data must remain (e.g., orders after customer deletion) | `DeleteBehavior.Restrict` |
| FK becomes null when parent is deleted (e.g., optional reference) | `DeleteBehavior.SetNull` |

**Default is `Cascade` for required relations.** Override explicitly to avoid surprises.

## Querying — AsNoTracking and projection

```csharp
// Read-only query — AsNoTracking skips the change tracker (faster, less memory)
public async Task<IReadOnlyList<OrderSummaryDto>> GetOrderSummariesAsync(
    int customerId, CancellationToken ct)
{
    return await _db.Orders
        .Where(o => o.CustomerId == customerId)
        .OrderByDescending(o => o.CreatedAt)
        .Select(o => new OrderSummaryDto(o.Id, o.Status, o.Total, o.CreatedAt))
        .AsNoTracking()
        .ToListAsync(ct);
}

// Tracked query — when you need to update the entity afterwards
public async Task<Order?> FindForUpdateAsync(int id, CancellationToken ct)
{
    return await _db.Orders.FindAsync(new object[] { id }, ct);
    // FindAsync always uses the change tracker
}
```

**Use `AsNoTracking()` for all read-only queries** — it reduces memory allocation and execution time by skipping the identity map.

**Project to DTOs with `Select()`** instead of loading full entities and then mapping — avoids fetching columns you don't need.

## Avoiding N+1 — Include and Split queries

```csharp
// Eager loading with Include — single JOIN query
var orders = await _db.Orders
    .Include(o => o.Lines)
        .ThenInclude(l => l.Product)
    .Where(o => o.CustomerId == customerId)
    .AsNoTracking()
    .ToListAsync(ct);

// Split query — avoids cartesian product explosion for multiple collections
var orders = await _db.Orders
    .Include(o => o.Lines)
    .Include(o => o.Tags)
    .AsSplitQuery()   // issues separate SQL queries per collection
    .AsNoTracking()
    .ToListAsync(ct);
```

**Prefer projection (`Select`) over `Include`** when you only need a subset of related data — it generates more efficient SQL.

**Use `AsSplitQuery()`** when loading multiple collection navigations to avoid a Cartesian explosion (rows = A × B × C).

**Never use lazy loading** in web applications — it is a hidden N+1 footgun. Disable it explicitly:

```csharp
// DbContextOptions — disable lazy loading proxies
options.UseSqlServer(connectionString)
       .UseLazyLoadingProxies(false);  // false is the default; explicit for clarity
```

## Repositories — thin wrapper pattern

```csharp
public interface IOrderRepository
{
    Task<Order?> FindAsync(int id, CancellationToken ct = default);
    Task<IReadOnlyList<OrderSummaryDto>> GetSummariesAsync(int customerId, CancellationToken ct = default);
    Task SaveAsync(Order order, CancellationToken ct = default);
    Task DeleteAsync(int id, CancellationToken ct = default);
}

public sealed class OrderRepository(AppDbContext db) : IOrderRepository
{
    public async Task<Order?> FindAsync(int id, CancellationToken ct)
        => await db.Orders
               .Include(o => o.Lines)
               .FirstOrDefaultAsync(o => o.Id == id, ct);

    public async Task<IReadOnlyList<OrderSummaryDto>> GetSummariesAsync(
        int customerId, CancellationToken ct)
        => await db.Orders
               .Where(o => o.CustomerId == customerId)
               .Select(o => new OrderSummaryDto(o.Id, o.Status, o.Total, o.CreatedAt))
               .AsNoTracking()
               .ToListAsync(ct);

    public async Task SaveAsync(Order order, CancellationToken ct)
    {
        db.Orders.Add(order);
        await db.SaveChangesAsync(ct);
    }

    public async Task DeleteAsync(int id, CancellationToken ct)
    {
        await db.Orders.Where(o => o.Id == id).ExecuteDeleteAsync(ct);  // EF Core 7+
    }
}
```

## Transactions

```csharp
// Explicit transaction for multi-aggregate writes
await using var tx = await _db.Database.BeginTransactionAsync(ct);
try
{
    var order = Order.Create(customerId, lines);
    _db.Orders.Add(order);
    await _db.SaveChangesAsync(ct);

    inventory.Deduct(lines);
    await _db.SaveChangesAsync(ct);

    await tx.CommitAsync(ct);
}
catch
{
    await tx.RollbackAsync(ct);
    throw;
}
```

Prefer designing aggregates to avoid cross-aggregate transactions. When a transaction is necessary, keep it as short as possible (no external HTTP calls inside a transaction).

## Parameterized raw SQL — when LINQ is not enough

```csharp
// Safe: FromSql with FormattableString — EF Core parameterizes automatically
var userId = 42;
var users = await _db.Users
    .FromSql($"SELECT * FROM users WHERE id = {userId} AND is_active = 1")
    .AsNoTracking()
    .ToListAsync(ct);

// Also safe: FromSqlRaw with explicit SqlParameter objects
var param = new SqlParameter("@userId", userId);
var users = await _db.Users
    .FromSqlRaw("SELECT * FROM users WHERE id = @userId", param)
    .AsNoTracking()
    .ToListAsync(ct);

// UNSAFE — string concatenation / interpolation into FromSqlRaw
// NEVER DO THIS:
var users = await _db.Users
    .FromSqlRaw($"SELECT * FROM users WHERE id = {userId}")  // SQL injection risk
    .ToListAsync(ct);
```

**Always prefer `FromSql(FormattableString)`** (C# interpolated string) over `FromSqlRaw` with manual parameters — it is safer and more readable. `FromSqlRaw` is only needed when the SQL is truly dynamic (e.g., built from an allowlisted column name for ORDER BY).

## Connection string from IConfiguration

```csharp
// Program.cs
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(                                           // or UseSqlServer
        builder.Configuration.GetConnectionString("DefaultConnection")
        ?? throw new InvalidOperationException(
            "Connection string 'DefaultConnection' not found in configuration.")));
```

```json
// appsettings.json — non-sensitive defaults only
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Database=myapp_dev;Username=dev;Password="
  }
}
```

Override `Password` and the full connection string via environment variables in CI/prod:

```bash
ConnectionStrings__DefaultConnection="Host=prod-db;Database=myapp;Username=app;Password=<secret>"
```

**Never commit the production connection string** — use environment variables or a secrets manager.
