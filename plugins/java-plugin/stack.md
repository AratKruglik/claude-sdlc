---
stack: java
aspects: [backend]
priority: 100
detect:
  any:
    - file_exists: pom.xml
    - file_exists: build.gradle
    - file_exists: build.gradle.kts
---

# Java Stack Profile (backend)

Registers any Maven or Gradle Java project with the SDLC pipeline. Detects the presence of a build file — no framework-specific content is required.

This is the **mid-tier fallback** for Java projects. It activates when no higher-priority framework plugin matches (e.g. `spring-boot-plugin` at priority 150 wins on Spring projects). Suitable for:
- Plain Java libraries or utilities
- CLI applications (no web framework)
- Micro-services using raw Servlet API or minimal HTTP toolkits (Javalin, Spark, etc.)
- Java modules with no recognized framework dependency

## Agents per phase

```yaml
business_analysis: business-analyst         # core agent (aspect-agnostic)
development:
  backend: java-architect                   # owned by this plugin
qa: qa-engineer                             # core agent
security: security-analyst                  # core agent
documentation: document-writer             # core agent
```

## Convention skills to apply

- java-foundation:java-conventions
- java-foundation:build-tooling
- java-foundation:jvm-testing

## Phase prompts injection

For development phase (backend aspect), inject:
> You are working on a **plain Java** project (no high-priority web framework detected).
> Scope: domain objects, business logic, service classes, CLI entry points, internal APIs.
>
> Apply `java-foundation:java-conventions`: records for value objects, sealed types for closed hierarchies, Optional for absence, streams for collection pipelines. Java 17+ idioms unless the build file specifies an older version.
>
> Apply `java-foundation:build-tooling`:
> - Detect build tool from file presence: `pom.xml` → Maven, `build.gradle`/`build.gradle.kts` → Gradle.
> - Always use the wrapper (`./mvnw` / `./gradlew`).
> - Manage dependencies via BOM and version properties — never inline literals.
>
> Run after writing:
> - Maven: `./mvnw -q -DskipTests compile` (compile check)
> - Gradle: `./gradlew -q compileJava` (compile check)

For qa phase, inject:
> Apply `java-foundation:jvm-testing`:
> - JUnit 5 with AAA structure and descriptive method names.
> - Mockito for boundary mocks (repositories, external clients) — constructor injection, not `@InjectMocks`.
> - AssertJ for assertions — never `assertTrue(a.equals(b))`.
> - Testcontainers for integration tests touching real infrastructure (DB, broker).
> - Separate unit tests (`*Test.java`) from integration tests (`*IT.java`).
>
> Run: `./mvnw test` or `./gradlew test`.

For security phase, inject:
> Check Java-specific issues in addition to OWASP Top 10:
> - **Command injection**: `Runtime.exec` / `ProcessBuilder` with user input — flag immediately.
> - **Deserialization**: `ObjectInputStream.readObject` on untrusted data — flag immediately.
> - **SQL injection**: string concatenation in queries — verify parameterized queries are used.
> - **Path traversal**: file paths derived from user input — verify canonical path validation.
> - **Hardcoded secrets**: passwords, tokens in source or `.properties` files.
> - **XXE**: XML parsers without `FEATURE_SECURE_PROCESSING` enabled.

## Post-pipeline checks

- `./mvnw -q test` (or `./gradlew test`)

These are advisory — failures are reported but do not retry.
