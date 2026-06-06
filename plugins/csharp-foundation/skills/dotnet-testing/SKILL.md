---
name: dotnet-testing
description: |
  xUnit, Moq/NSubstitute, FluentAssertions, and coverlet patterns for any .NET project. Covers test structure ([Fact]/[Theory]/[InlineData]), mocking discipline, fluent assertions, integration test setup with WebApplicationFactory, and coverage measurement. Stack-agnostic — referenced by every .NET plugin in the marketplace.

  Use this skill to:
  - Write clear, maintainable unit tests with xUnit [Fact] and [Theory].
  - Mock dependencies with Moq or NSubstitute without overusing mocks.
  - Write expressive assertions with FluentAssertions.
  - Measure coverage with coverlet and enforce a minimum threshold.

  Do NOT use this skill for:
  - ASP.NET Core-specific integration tests (WebApplicationFactory, HttpClient — those are in aspnet-core-plugin:aspnet-conventions).
  - EF Core in-memory or SQL Server LocalDB test patterns (aspnet-core-plugin:efcore-patterns).
  - C# language idioms — see csharp-foundation:csharp-conventions.
---

# .NET Testing Patterns (stack-agnostic)

## Test framework: xUnit

xUnit is the primary test framework for .NET. Use NUnit or MSTest only when the project already uses them — do not introduce xUnit into a project that uses another framework.

### NuGet packages for a test project

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="xunit" Version="2.9.2" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2">
      <PrivateAssets>all</PrivateAssets>
    </PackageReference>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.11.1" />
    <PackageReference Include="Moq" Version="4.20.72" />
    <PackageReference Include="FluentAssertions" Version="6.12.1" />
    <PackageReference Include="coverlet.collector" Version="6.0.2">
      <PrivateAssets>all</PrivateAssets>
    </PackageReference>
  </ItemGroup>
</Project>
```

## xUnit fundamentals

```csharp
using FluentAssertions;
using Moq;
using Xunit;

public class UserServiceTests
{
    private readonly Mock<IUserRepository> _repoMock;
    private readonly UserService _sut;

    public UserServiceTests()
    {
        _repoMock = new Mock<IUserRepository>(MockBehavior.Strict);
        _sut = new UserService(_repoMock.Object);
    }

    [Fact]
    public async Task RegisterAsync_WithValidData_ReturnsActiveUser()
    {
        // Arrange
        var command = new RegisterUserCommand("alice@example.com", "Secret1!");
        _repoMock.Setup(r => r.ExistsByEmailAsync("alice@example.com", default))
                 .ReturnsAsync(false);
        _repoMock.Setup(r => r.SaveAsync(It.IsAny<User>(), default))
                 .ReturnsAsync((User u, CancellationToken _) => u);

        // Act
        var user = await _sut.RegisterAsync(command);

        // Assert
        user.Email.Should().Be("alice@example.com");
        user.IsActive.Should().BeTrue();
        _repoMock.VerifyAll();
    }

    [Fact]
    public async Task RegisterAsync_WithDuplicateEmail_ThrowsDomainException()
    {
        _repoMock.Setup(r => r.ExistsByEmailAsync(It.IsAny<string>(), default))
                 .ReturnsAsync(true);

        await _sut.Invoking(s => s.RegisterAsync(new RegisterUserCommand("dup@example.com", "pass")))
                  .Should().ThrowAsync<DomainException>()
                  .WithMessage("*already registered*");
    }
}
```

**Test method naming:** `MethodName_Condition_ExpectedOutcome` — readable without additional comments.

**xUnit constructor vs `[Theory]` setup:** Use the constructor for shared setup of the system under test; use `[ClassFixture<T>]` for expensive shared resources (DB connections, servers) that are reused across tests in the class.

## Parameterised tests — [Theory]

```csharp
[Theory]
[InlineData("")]
[InlineData("  ")]
[InlineData(null)]
public void IsValidEmail_BlankInput_ReturnsFalse(string? input)
{
    EmailValidator.IsValid(input).Should().BeFalse();
}

[Theory]
[InlineData("alice@example.com", true)]
[InlineData("not-an-email", false)]
[InlineData("@nodomain", false)]
public void IsValidEmail_VariousInputs_MatchesExpected(string email, bool expected)
{
    EmailValidator.IsValid(email).Should().Be(expected);
}

// MemberData for complex objects
[Theory]
[MemberData(nameof(InvalidCommands))]
public async Task RegisterAsync_InvalidCommand_ThrowsValidationException(RegisterUserCommand command)
{
    await _sut.Invoking(s => s.RegisterAsync(command))
              .Should().ThrowAsync<ValidationException>();
}

public static IEnumerable<object[]> InvalidCommands =>
[
    [new RegisterUserCommand(null!, "pass")],
    [new RegisterUserCommand("", "pass")],
    [new RegisterUserCommand("user@example.com", "")],
];
```

## FluentAssertions — expressive assertions

Prefer FluentAssertions over xUnit's `Assert.*` — it gives richer failure messages and fluent chaining.

```csharp
// Collections
result.Items.Should().HaveCount(3)
    .And.ContainSingle(i => i.Name == "Alice");

// Strings
response.ContentType.Should().StartWith("application/json");

// Exceptions (sync and async)
Action act = () => service.Compute(-1);
act.Should().Throw<ArgumentOutOfRangeException>()
   .WithParameterName("value");

await service.Awaiting(s => s.GetAsync(-1))
    .Should().ThrowAsync<KeyNotFoundException>();

// Numeric / date
price.Should().BeGreaterThan(0).And.BeLessThan(1000);
createdAt.Should().BeCloseTo(DateTimeOffset.UtcNow, precision: TimeSpan.FromSeconds(5));

// Equivalence (structural equality, ignores property order)
result.Should().BeEquivalentTo(expected, opt => opt.Excluding(x => x.Id));
```

**Never use `Assert.True(a.Equals(b))`** — the failure message shows only "expected true". Use `a.Should().Be(b)`.

## Moq — mocking discipline

```csharp
// Constructor injection — preferred (no reflection, no [Inject])
var repo = new Mock<IUserRepository>(MockBehavior.Strict);
var sut = new UserService(repo.Object);

// Stubbing — be specific with arguments
repo.Setup(r => r.FindAsync(42, default)).ReturnsAsync(testUser);

// Argument matchers when exact value doesn't matter
repo.Setup(r => r.ExistsByEmailAsync(It.IsAny<string>(), default))
    .ReturnsAsync(false);

// Capture arguments for detailed assertions
repo.Setup(r => r.SaveAsync(It.IsAny<User>(), default))
    .Callback<User, CancellationToken>((u, _) => savedUser = u)
    .ReturnsAsync((User u, CancellationToken _) => u);

// Verification
repo.Verify(r => r.SaveAsync(It.IsAny<User>(), default), Times.Once);
repo.Verify(r => r.DeleteAsync(It.IsAny<int>(), default), Times.Never);
repo.VerifyAll();   // MockBehavior.Strict enforces no unexpected calls
```

**Use `MockBehavior.Strict`** for new tests — it forces you to set up all calls explicitly, making unexpected dependencies visible.

**Do not mock value objects, records, or simple DTOs.** Only mock boundaries: repositories, HTTP clients, external services, the clock (`IDateTimeProvider`).

## NSubstitute — alternative to Moq

Some projects prefer NSubstitute for its concise syntax:

```csharp
var repo = Substitute.For<IUserRepository>();
repo.FindAsync(42, default).Returns(testUser);
repo.ExistsByEmailAsync(Arg.Any<string>(), default).Returns(false);

// Verification
await repo.Received(1).SaveAsync(Arg.Any<User>(), default);
await repo.DidNotReceive().DeleteAsync(Arg.Any<int>(), default);
```

Match the mocking framework that is already used in the project. Do not mix Moq and NSubstitute in the same test project.

## Coverage — coverlet + threshold

Measure coverage when running tests:

```bash
# Run tests with coverage
dotnet test --collect:"XPlat Code Coverage"

# Generate HTML report (requires reportgenerator global tool)
dotnet tool install --global dotnet-reportgenerator-globaltool
reportgenerator -reports:**/coverage.cobertura.xml -targetdir:coverage -reporttypes:Html

# Open report
open coverage/index.html     # macOS
start coverage/index.html    # Windows
```

Enforce a minimum coverage threshold in CI:

```xml
<!-- .csproj — dotnet test fails if line coverage < 80% -->
<PropertyGroup>
  <CollectCoverage>true</CollectCoverage>
  <CoverletOutputFormat>cobertura</CoverletOutputFormat>
  <Threshold>80</Threshold>
  <ThresholdType>line</ThresholdType>
</PropertyGroup>
```

**Target ≥ 80% line coverage on business logic** (services, domain objects, validators). Exclude framework glue code (Program.cs, Startup, configuration classes, migrations) using `[ExcludeFromCodeCoverage]` or coverlet filters.

## Test organisation conventions

```
MyApp.sln
├── src/
│   └── MyApp/
│       ├── Users/
│       │   ├── User.cs
│       │   ├── IUserRepository.cs
│       │   └── UserService.cs
│       └── ...
└── tests/
    ├── MyApp.UnitTests/            # Unit tests — no external dependencies
    │   └── Users/
    │       └── UserServiceTests.cs
    └── MyApp.IntegrationTests/     # Integration tests — real DB, HTTP
        └── Users/
            └── UserEndpointsTests.cs
```

**Naming:** Unit test classes: `{Subject}Tests`. Integration test classes: `{Subject}IntegrationTests` or `{Subject}Tests` in the `.IntegrationTests` project.

Mirror the main project's namespace structure: `MyApp.Users.UserServiceTests` tests `MyApp.Users.UserService`.

## IClassFixture — reuse expensive resources

```csharp
// Shared fixture — created once per test class, disposed after all tests
public class DatabaseFixture : IDisposable
{
    public AppDbContext Db { get; }

    public DatabaseFixture()
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(databaseName: Guid.NewGuid().ToString())
            .Options;
        Db = new AppDbContext(options);
    }

    public void Dispose() => Db.Dispose();
}

public class UserRepositoryTests : IClassFixture<DatabaseFixture>
{
    private readonly AppDbContext _db;

    public UserRepositoryTests(DatabaseFixture fixture) => _db = fixture.Db;

    [Fact]
    public async Task SaveAndFind_RoundTrip()
    {
        var repo = new UserRepository(_db);
        var user = new User { Email = "alice@example.com" };

        await repo.SaveAsync(user, default);
        var found = await repo.FindAsync(user.Id, default);

        found.Should().NotBeNull();
        found!.Email.Should().Be("alice@example.com");
    }
}
```

For ASP.NET Core HTTP integration tests using `WebApplicationFactory<TProgram>`, see `aspnet-core-plugin:aspnet-conventions`.
