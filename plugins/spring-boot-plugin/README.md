# spring-boot-plugin

Spring Boot backend stack provider for the [SDLC Marketplace](../../README.md).

## What it does

Registers Spring Boot projects with the SDLC pipeline. Provides a `spring-boot-architect` agent (Sonnet/medium) as the development-phase backend implementer. Covers REST controllers, Spring Data JPA, Bean Validation, Spring Security, Flyway/Liquibase migrations, and Spring Boot testing slices.

**Priority: 150.** Beats `java-plugin` (100) on the `backend` aspect for Spring Boot projects.

## Detection

Matches any project where at least one build file contains a Spring Boot marker:
- `pom.xml` contains `spring-boot`
- `build.gradle` contains `org.springframework.boot`
- `build.gradle.kts` contains `org.springframework.boot`

## Agents

| Agent | Model | Role |
|---|---|---|
| `spring-boot-architect` | Sonnet/medium | Development-phase backend implementer |

## Skills

| Skill | Description |
|---|---|
| `spring-boot-plugin:spring-conventions` | REST controllers, service layer, constructor injection, @ConfigurationProperties, error handling with ProblemDetail |
| `spring-boot-plugin:spring-data-jpa` | JPA entities, JpaRepository, JPQL, N+1 avoidance, Flyway/Liquibase migrations, pagination |
| `java-foundation:java-conventions` | Modern Java idioms (records, Optional, streams, immutability) |
| `java-foundation:build-tooling` | Maven/Gradle wrapper, BOM dependency management |
| `java-foundation:jvm-testing` | JUnit 5, Mockito, AssertJ, Testcontainers, @WebMvcTest/@DataJpaTest guidance |

## Dependencies

- [`sdlc`](../sdlc) — core pipeline
- [`java-foundation`](../java-foundation) — shared Java skills

## Installation

```
/plugin install spring-boot-plugin@sdlc-marketplace
```

`sdlc` and `java-foundation` are pulled automatically as dependencies.

## Usage

```
/sdlc:start "Add REST endpoint for invoice creation with JPA persistence"
```

The orchestrator detects Spring Boot in your build file, activates `spring-boot-plugin` (priority 150) over `java-plugin` (100), and routes the development phase to `spring-boot-architect`.

## Stack composition

`spring-boot-plugin` owns only the `backend` aspect. No frontend agent is registered — this is an API-first plugin. For full-stack projects, pair with a frontend plugin:

| Frontend | Plugin |
|---|---|
| React SPA | `react-plugin` |
| Vue 3 SPA | `vue-plugin` |
| Angular SPA | `angular-plugin` |

## Roadmap

- `quarkus-plugin` — Quarkus + GraalVM native image (same priority=150 pattern, distinct detection)
- `micronaut-plugin` — Micronaut + compile-time DI
- `jakarta-ee-plugin` — Jakarta EE on application servers
