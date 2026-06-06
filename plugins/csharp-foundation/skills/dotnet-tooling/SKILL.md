---
name: dotnet-tooling
description: |
  .NET SDK and NuGet tooling conventions: dotnet CLI commands (new/build/run/test/publish/restore/format), NuGet package management (PackageReference, Directory.Packages.props central package management, packages.lock.json), project file conventions (.csproj, .sln, global.json, Directory.Build.props), multi-targeting, and dotnet format. Stack-agnostic — referenced by every .NET plugin in the marketplace.

  Use this skill to:
  - Detect the .NET SDK version and run all commands via the dotnet CLI.
  - Manage NuGet dependencies safely (central package management, no floating versions).
  - Configure project files and solution-wide properties in Directory.Build.props.
  - Format code consistently with dotnet format.

  Do NOT use this skill for:
  - Framework-specific tooling (dotnet ef migrations, aspnet-codegenerator — those are in aspnet-core-plugin:aspnet-conventions).
  - Testing patterns — see csharp-foundation:dotnet-testing.
  - C# language idioms — see csharp-foundation:csharp-conventions.
---

# .NET Tooling (stack-agnostic)

## Project detection

Determine the project structure at the start of every task:

| Signal | Meaning |
|---|---|
| `*.sln` exists | Solution file — multiple projects; use `dotnet build <solution>.sln` |
| Single `*.csproj` in root | Single-project layout |
| `global.json` exists | SDK version is pinned — **read it first** |
| `Directory.Build.props` exists | Solution-wide MSBuild properties apply |
| `Directory.Packages.props` exists | Central Package Management is active — do not specify versions in individual `.csproj` files |

## dotnet CLI — core commands

Always run `dotnet` commands from the directory containing the `.sln` or `.csproj` (or pass the path explicitly).

```bash
# Restore NuGet packages
dotnet restore

# Build (all projects in the solution, or a single project)
dotnet build
dotnet build MyApp.sln
dotnet build src/MyApp/MyApp.csproj

# Run (application project)
dotnet run --project src/MyApp/MyApp.csproj

# Run tests
dotnet test
dotnet test --filter "Category=Unit"
dotnet test --logger "trx;LogFileName=results.trx"

# Publish (Release, self-contained optional)
dotnet publish -c Release -o ./publish
dotnet publish -c Release --runtime linux-x64 --self-contained

# Check outdated packages
dotnet list package --outdated

# Format code (respects .editorconfig)
dotnet format

# Verify formatting without writing changes (useful in CI)
dotnet format --verify-no-changes
```

## global.json — pin the SDK version

```json
{
  "sdk": {
    "version": "8.0.404",
    "rollForward": "latestPatch"
  }
}
```

**Always read `global.json` first** to learn which SDK version is in use. Do not recommend commands or features that require a higher SDK version than what is pinned.

`rollForward: "latestPatch"` allows minor patch upgrades automatically — safe for CI. Use `"disable"` for strict reproducibility.

## .csproj — project file conventions

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>   <!-- or net9.0, net10.0 -->
    <Nullable>enable</Nullable>                  <!-- always enable -->
    <ImplicitUsings>enable</ImplicitUsings>      <!-- reduces boilerplate using directives -->
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>  <!-- recommended for new projects -->
    <AnalysisLevel>latest</AnalysisLevel>        <!-- Roslyn analyzers at latest rules set -->
  </PropertyGroup>

  <ItemGroup>
    <!-- With Central Package Management: version goes in Directory.Packages.props -->
    <PackageReference Include="Microsoft.Extensions.Logging.Abstractions" />
    <PackageReference Include="Newtonsoft.Json" />

    <!-- Without CPM: pin versions explicitly — no floating ranges -->
    <!-- <PackageReference Include="Serilog" Version="4.1.0" /> -->
  </ItemGroup>

</Project>
```

**Never use floating version ranges** (`*`, `1.*`, `[1.0,)`) — they break reproducible builds. Pin exact or minimum patch versions.

## NuGet — PackageReference lifecycle

```bash
# Add a package
dotnet add package Serilog --version 4.1.0
dotnet add src/MyApp/MyApp.csproj package FluentValidation

# Remove a package
dotnet remove package Serilog

# Inspect the dependency graph
dotnet list package
dotnet list package --include-transitive
dotnet list package --outdated
```

### When to add a package

1. Check if the framework already provides the functionality (`Microsoft.Extensions.*` for DI, logging, configuration).
2. Prefer packages with active maintenance, wide adoption, and no critical CVEs.
3. Note the addition in DECISIONS — non-trivial additions change the project's supply-chain footprint.

## Central Package Management (Directory.Packages.props)

When `Directory.Packages.props` exists, **do not specify `Version=` attributes in individual `.csproj` files** — the central file owns all version pins.

```xml
<!-- Directory.Packages.props (at solution root) -->
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>

  <ItemGroup>
    <PackageVersion Include="Microsoft.EntityFrameworkCore" Version="8.0.11" />
    <PackageVersion Include="FluentValidation" Version="11.11.0" />
    <PackageVersion Include="xunit" Version="2.9.2" />
    <PackageVersion Include="xunit.runner.visualstudio" Version="2.8.2" />
    <PackageVersion Include="Moq" Version="4.20.72" />
    <PackageVersion Include="FluentAssertions" Version="6.12.1" />
  </ItemGroup>
</Project>
```

Add new packages with:

```bash
# When CPM is active, dotnet add package still updates Directory.Packages.props
dotnet add package NewPackage --version 1.2.3
```

## Directory.Build.props — solution-wide MSBuild properties

```xml
<!-- Directory.Build.props (at solution root) — applies to ALL projects -->
<Project>
  <PropertyGroup>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <LangVersion>latest</LangVersion>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <AnalysisLevel>latest</AnalysisLevel>
    <Authors>Your Org</Authors>
    <Copyright>© 2025 Your Org</Copyright>
  </PropertyGroup>
</Project>
```

**Do not repeat** properties already in `Directory.Build.props` in individual `.csproj` files — they are inherited automatically.

## Multi-targeting

When a library must support multiple runtimes:

```xml
<PropertyGroup>
  <TargetFrameworks>net6.0;net8.0</TargetFrameworks>  <!-- semicolon-separated -->
</PropertyGroup>
```

Use `#if NET8_0_OR_GREATER` preprocessor symbols to conditionally compile version-specific code.

## dotnet format — code formatting

`dotnet format` respects `.editorconfig` and Roslyn analyzer rules. Run it after writing code:

```bash
# Fix all formatting issues in place
dotnet format

# Only fix whitespace issues (fastest)
dotnet format whitespace

# Only fix style issues (var usage, using directives, etc.)
dotnet format style

# CI gate — fails if any changes would be made
dotnet format --verify-no-changes
```

Create a `.editorconfig` at the solution root to enforce consistent style. Minimum recommended settings:

```ini
root = true

[*.cs]
indent_style = space
indent_size = 4
end_of_line = lf
charset = utf-8-bom
trim_trailing_whitespace = true
insert_final_newline = true

# Prefer file-scoped namespaces
csharp_style_namespace_declarations = file_scoped:warning

# Prefer var when type is apparent
csharp_style_var_for_built_in_types = false:suggestion
csharp_style_var_when_type_is_apparent = true:suggestion
csharp_style_var_elsewhere = false:suggestion
```

## packages.lock.json — lock file for reproducibility

Enable lock files when reproducible restores are required (CI, Docker images):

```xml
<!-- .csproj or Directory.Build.props -->
<PropertyGroup>
  <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
</PropertyGroup>
```

Commit `packages.lock.json` alongside source. In CI, restore with `--locked-mode` to fail on any drift:

```bash
dotnet restore --locked-mode
```
