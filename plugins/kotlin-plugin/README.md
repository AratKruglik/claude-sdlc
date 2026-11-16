# kotlin-plugin

Kotlin/JVM backend stack provider for the [SDLC Marketplace](../../README.md).

## What it does

Registers Kotlin/JVM projects with the SDLC pipeline. Provides a `kotlin-architect` agent (Sonnet/medium) as the development-phase backend implementer for Kotlin libraries, CLIs and services — Ktor, http4k, Javalin or plain JVM.

**Priority: 120.** Beats `java-plugin` (100), which matches every Gradle/Maven project. `spring-boot-plugin` (150) still wins on Spring Boot projects, Kotlin or not.

Out of scope: Android apps, Kotlin Multiplatform, Compose Multiplatform.

## Detection

Matches when any of these root files declares the Kotlin JVM plugin:
- `build.gradle.kts` — `kotlin("jvm")` or `…kotlin.jvm` (plugin id or version-catalog alias)
- `build.gradle` — `org.jetbrains.kotlin.jvm` or `kotlin-gradle-plugin`
- `gradle/libs.versions.toml` — `org.jetbrains.kotlin.jvm`
- `pom.xml` — `kotlin-maven-plugin`

A `build.gradle.kts` without the Kotlin JVM plugin is a Java project using the Kotlin DSL and stays with `java-plugin`.

## Agents

| Agent | Model | Role |
|---|---|---|
| `kotlin-architect` | Sonnet/medium (plan pass: Opus) | Development-phase backend implementer |

## Skills

| Skill | Description |
|---|---|
| `kotlin-plugin:kotlin-conventions` | Null safety, data/sealed/value classes, exhaustive `when`, scope functions, extensions, errors, collections, Java interop |
| `kotlin-plugin:kotlin-coroutines` | Structured concurrency, dispatchers, cancellation, Flow, Ktor coroutines, bridging |
| `kotlin-plugin:kotlin-testing` | JUnit 5 / Kotest, MockK, runTest, Turbine, Ktor `testApplication`, Testcontainers |
| `java-foundation:build-tooling` | Gradle/Maven wrappers, version catalogs and BOMs (shared) |

## Hooks

- **PostToolUse** — on `.kt`/`.kts` edits: `./gradlew spotlessApply` when Spotless is configured, else `./gradlew ktlintFormat` when the ktlint Gradle plugin is, else Maven Spotless.
- **PreToolUse** — blocks edits to `detekt*.yml` and `.editorconfig` while a pipeline run is active.
- **SubagentStop** — `./gradlew -q compileKotlin compileTestKotlin` once after `kotlin-architect` finishes; failures go back to the orchestrator as a retry hint. Maven projects run `./mvnw -q test-compile` instead; each entry is a no-op when its wrapper is absent.

## Dependencies

- [`sdlc`](../sdlc) — core pipeline
- [`java-foundation`](../java-foundation) — shared JVM build tooling

## Installation

```
/plugin install kotlin-plugin@sdlc-marketplace
```

## Usage

```
/sdlc:start "Add an endpoint that exports orders as CSV"
```

On a Gradle project applying `kotlin("jvm")` without Spring Boot, the orchestrator activates `kotlin-plugin` (priority 120) and routes the development phase to `kotlin-architect`.
