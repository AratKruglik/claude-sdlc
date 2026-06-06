# java-plugin

Plain Java backend stack provider for the [SDLC Marketplace](../../README.md).

## What it does

Registers any Maven or Gradle Java project with the SDLC pipeline. Provides a `java-architect` agent (Sonnet/medium) as the development-phase backend implementer for projects without a higher-priority web framework.

**Priority: 100.** Activates for plain Java projects — libraries, CLI tools, micro-services using minimal HTTP toolkits (Javalin, Spark, etc.). If `spring-boot-plugin` (priority 150) also matches, it wins the `backend` aspect and `java-plugin` stays inactive for that project.

## Detection

Matches any project with at least one of:
- `pom.xml`
- `build.gradle`
- `build.gradle.kts`

## Agents

| Agent | Model | Role |
|---|---|---|
| `java-architect` | Sonnet/medium | Development-phase backend implementer |

## Skills (via java-foundation)

| Skill | Description |
|---|---|
| `java-foundation:java-conventions` | Modern Java idioms (records, sealed types, Optional, streams, immutability) |
| `java-foundation:build-tooling` | Maven/Gradle wrapper, BOM dependency management |
| `java-foundation:jvm-testing` | JUnit 5, Mockito, AssertJ, Testcontainers |

## Dependencies

- [`sdlc`](../sdlc) — core pipeline
- [`java-foundation`](../java-foundation) — shared Java skills

## Installation

```
/plugin install java-plugin@sdlc-marketplace
```

`sdlc` and `java-foundation` are pulled automatically as dependencies.

## Usage

```
/sdlc:start "Add CSV export for orders"
```

On a plain Maven/Gradle project with no Spring Boot marker, the orchestrator activates `java-plugin` (priority 100) and routes the development phase to `java-architect`.
