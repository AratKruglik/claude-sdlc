# csharp-foundation

Shared C#/.NET foundation skills for the [SDLC Marketplace](../../README.md).

This is a **pure skill library** — no agent, no stack profile. It ships stack-agnostic C#/.NET conventions referenced by every .NET plugin in the marketplace (`aspnet-core-plugin` and future framework plugins).

## Skills

| Skill | Description |
|---|---|
| `csharp-foundation:csharp-conventions` | Modern C# (C# 10+) idioms: nullable reference types, records, readonly structs, pattern matching, async/await + CancellationToken, IDisposable/IAsyncDisposable, file-scoped namespaces, naming conventions, class design rules |
| `csharp-foundation:dotnet-tooling` | dotnet CLI commands (build/run/test/publish/format), NuGet package management, PackageReference, central package management (Directory.Packages.props), global.json, Directory.Build.props, dotnet format + .editorconfig |
| `csharp-foundation:dotnet-testing` | xUnit ([Fact]/[Theory]/[InlineData]), Moq/NSubstitute discipline, FluentAssertions, coverlet coverage, IClassFixture for shared resources, test project layout |

## Dependencies

- [`sdlc`](../sdlc) — core pipeline (auto-pulled on install)

## Installation

This plugin is pulled automatically as a dependency of `aspnet-core-plugin`:

```
/plugin install aspnet-core-plugin@sdlc-marketplace
```

To install standalone (if you want C# skills without a stack provider):

```
/plugin install csharp-foundation@sdlc-marketplace
```
