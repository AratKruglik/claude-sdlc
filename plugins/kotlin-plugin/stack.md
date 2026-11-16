---
stack: kotlin
aspects: [backend]
priority: 120
detect:
  any:
    - file_contains:
        path: build.gradle.kts
        pattern: 'kotlin\("jvm"\)|kotlin\.jvm'
    - file_contains:
        path: build.gradle
        pattern: 'org\.jetbrains\.kotlin\.jvm|kotlin-gradle-plugin'
    - file_contains:
        path: gradle/libs.versions.toml
        pattern: 'org\.jetbrains\.kotlin\.jvm'
    - file_contains:
        path: pom.xml
        pattern: 'kotlin-maven-plugin'
---

# Kotlin Stack Profile (backend)

Registers Kotlin/JVM projects with the SDLC pipeline. Detects the Kotlin JVM plugin in the root build file (`kotlin("jvm")`, `org.jetbrains.kotlin.jvm`, a version-catalog alias `libs.plugins.kotlin.jvm`) or `kotlin-maven-plugin` in `pom.xml`. Gradle's Kotlin DSL alone (`build.gradle.kts` without the Kotlin JVM plugin) does not count — that is a Java project.

Priority 120:
- Beats `java-plugin` (100), which also matches every Gradle/Maven project.
- Loses to `spring-boot-plugin` (150) on Spring Boot projects, Kotlin or not — Spring knowledge outweighs language idioms there.

Covers:
- Kotlin libraries and CLIs (`clikt`, `kotlinx-cli`)
- Ktor servers (`io.ktor:ktor-server-*`)
- Plain JVM services (http4k, Javalin, Vert.x Kotlin)

Out of scope: Android apps (`com.android.application`), Kotlin Multiplatform shared modules, Compose Multiplatform UIs.

## Agents per phase

```yaml
business_analysis: business-analyst         # core agent (aspect-agnostic)
development:
  backend: kotlin-architect                 # owned by this plugin
qa: qa-engineer                             # core agent
security: security-analyst                  # core agent
documentation: document-writer             # core agent
```

## Convention skills to apply

- kotlin-plugin:kotlin-conventions
- kotlin-plugin:kotlin-coroutines
- kotlin-plugin:kotlin-testing
- java-foundation:build-tooling

## Phase prompts injection

For development phase (backend aspect), inject:
> You are working on a **Kotlin/JVM** project.
> Detect before writing:
> - Build: `build.gradle.kts` (Kotlin DSL, usually with `gradle/libs.versions.toml`) or `pom.xml` with `kotlin-maven-plugin`. Always use the wrapper (`./gradlew` / `./mvnw`).
> - Kotlin version and JVM target: `kotlin("jvm") version` / catalog `kotlin =` entry, `jvmToolchain(…)` or `kotlinOptions.jvmTarget`. Do not use language features newer than the Kotlin version.
> - Framework: `io.ktor:ktor-server-*` → Ktor (`Application.module()`, plugins via `install(…)`, routing DSL); otherwise plain JVM / library / CLI.
> - Serialization: `kotlinx-serialization` (`@Serializable`) vs Jackson (`jackson-module-kotlin`) — use what is installed.
> - Persistence: Exposed, jOOQ, Spring-free JDBC, or SQLDelight — reuse what is installed.
> - DI: Koin, Kodein, Dagger, or manual constructor wiring — follow it.
> - Static analysis: ktlint (`org.jlleitschuh.gradle.ktlint` or Spotless `ktlint()`), detekt (`io.gitlab.arturbosch.detekt`). Never edit `detekt.yml` or `.editorconfig` to silence findings.
>
> Apply `kotlin-plugin:kotlin-conventions`: null safety without `!!`, `data`/`sealed`/`value` classes, immutable `val` and read-only collections, exhaustive `when`, extension functions over util classes.
> Apply `kotlin-plugin:kotlin-coroutines` for any suspend/Flow code: structured concurrency, no `GlobalScope`, `Dispatchers.IO` only around blocking calls, cancellation-safe `try/finally`.
> Apply `java-foundation:build-tooling` for dependencies: add them through the version catalog when the project has one.
>
> Formatting runs per edit via the plugin's PostToolUse hook (Spotless or ktlintFormat when configured). `./gradlew -q compileKotlin compileTestKotlin` runs after you return via the SubagentStop hook and must be clean.
>
> If superpowers is available, invoke superpowers:verification-before-completion before returning.

For qa phase, inject:
> Apply `kotlin-plugin:kotlin-testing`:
> - Use the installed framework: JUnit 5 + `kotlin.test` / AssertJ, or Kotest (`FunSpec`/`StringSpec`/`BehaviorSpec` — mirror neighbours).
> - MockK for mocks (`mockk`, `coEvery`/`coVerify` for suspend functions); never Mockito in a project that already uses MockK.
> - Coroutines: `runTest` from `kotlinx-coroutines-test`, inject dispatchers, Turbine for `Flow` if installed.
> - Ktor: `testApplication { application { module() }; client.get(...) }` — no real ports.
> - Testcontainers for integration tests touching a real database.
>
> Run: `./gradlew test` (or `./mvnw test`).

For security phase, inject:
> Check Kotlin/JVM-specific issues in addition to OWASP Top 10:
> - **SQL injection**: string templates (`"... $id"`) inside SQL, Exposed `exec("...")`, raw jOOQ — must use bound parameters.
> - **Command injection**: `ProcessBuilder` / `Runtime.exec` with user input.
> - **Deserialization**: Java `ObjectInputStream`, Jackson default typing, `kotlinx.serialization` polymorphism with open, unregistered subclasses on untrusted input.
> - **Ktor**: routes added outside the `authenticate { }` block they belong in, `CORS { anyHost() }`, `StatusPages` returning exception messages or stack traces, missing request size limits, `CallLogging` logging Authorization headers.
> - **Secrets**: credentials in `application.conf` / `application.yaml` / source instead of `${?ENV_VAR}` or a secrets manager.
> - **Null-safety escapes**: `!!` and `lateinit` on values derived from untrusted input (crash = DoS).
> - **Dependencies**: OWASP dependency-check or `./gradlew dependencyUpdates` if configured — flag Critical/High.

## Post-pipeline checks

- ./gradlew test

These are advisory — failures are reported but do not retry.
