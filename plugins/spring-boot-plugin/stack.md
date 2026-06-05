---
stack: spring-boot
aspects: [backend]
priority: 150
detect:
  any:
    - file_contains:
        path: pom.xml
        pattern: 'spring-boot'
    - file_contains:
        path: build.gradle
        pattern: 'org.springframework.boot'
    - file_contains:
        path: build.gradle.kts
        pattern: 'org.springframework.boot'
---

# Spring Boot Stack Profile (backend)

Registers Spring Boot projects with the SDLC pipeline. Auto-detected by presence of `spring-boot` in `pom.xml` or `org.springframework.boot` in `build.gradle` / `build.gradle.kts`.

This plugin owns the **backend** aspect. Priority 150 beats `java-plugin` (100) on Spring projects.

## Agents per phase

```yaml
business_analysis: business-analyst             # core agent (aspect-agnostic)
development:
  backend: spring-boot-architect               # owned by this plugin
qa: qa-engineer                                 # core agent
security: security-analyst                      # core agent
documentation: document-writer                 # core agent
```

## Convention skills to apply

- java-foundation:java-conventions
- java-foundation:build-tooling
- java-foundation:jvm-testing
- spring-boot-plugin:spring-conventions
- spring-boot-plugin:spring-data-jpa

## Phase prompts injection

For development phase (backend aspect), inject:
> You are working on the **backend** aspect of a **Spring Boot** project.
> Scope: REST controllers, DTOs, service classes, Spring Data JPA repositories, domain entities, Bean Validation, Flyway/Liquibase migrations (stub only — elaborate in your report), Spring Security configuration, `application.yml` / `application.properties`.
>
> Apply `spring-boot-plugin:spring-conventions`:
> - Annotate service classes with `@Service`; mark transactional boundaries with `@Transactional` at the service layer, not the controller.
> - Use `@RestController` + `@RequestMapping` (class-level) for REST endpoints. Return `ResponseEntity<T>` only when you need explicit HTTP control (status, headers); otherwise return the DTO directly.
> - Validate inputs with Bean Validation annotations on DTOs + `@Valid` on controller parameters. Never validate inline in the controller body.
> - Use constructor injection (not `@Autowired` on fields) — record components or `@RequiredArgsConstructor` (Lombok) are fine.
> - Configuration in `application.yml` via `@ConfigurationProperties` bound to a record or class — no `@Value` on fields unless single scalar.
>
> Apply `spring-boot-plugin:spring-data-jpa`:
> - Entities use `@Entity` + `@Table`; ID with `@Id` + `@GeneratedValue(strategy = GenerationType.IDENTITY)`.
> - Relations: prefer lazy loading (`@OneToMany(fetch = FetchType.LAZY)`) to avoid N+1; add `@EntityGraph` or `JOIN FETCH` in the repository when eager data is needed.
> - Repositories extend `JpaRepository<Entity, Id>`; add `@Query` JPQL for complex reads — no raw SQL unless unavoidable.
> - Migrations: create stub Flyway/Liquibase file (e.g. `V{n}__description.sql`) with `-- TODO: elaborate` and document the schema changes needed; the QA phase verifies the migration runs.
>
> Apply `java-foundation:java-conventions` for domain/value objects (records, Optional, sealed types where appropriate).
>
> After writing code:
> - `./mvnw -q -DskipTests compile` or `./gradlew -q compileJava` — fix all compilation errors.
> - `./mvnw -q checkstyle:check` or `./gradlew -q checkstyleMain` if Checkstyle is configured (treat as advisory).

For qa phase, inject:
> Apply `java-foundation:jvm-testing` plus Spring-specific slices:
> - `@SpringBootTest` for full-context integration tests (slow — use sparingly, one per feature flow).
> - `@WebMvcTest(YourController.class)` for controller-layer tests: MockMvc, `@MockBean` for services.
> - `@DataJpaTest` for repository-layer tests: in-memory H2 or Testcontainers PostgreSQL, `TestEntityManager`.
> - `@ExtendWith(MockitoExtension.class)` for pure service unit tests (no Spring context — fastest).
>
> ```java
> @WebMvcTest(UserController.class)
> class UserControllerTest {
>     @Autowired MockMvc mvc;
>     @MockBean  UserService userService;
>
>     @Test
>     void getUser_existing_returns200() throws Exception {
>         given(userService.findById(1L)).willReturn(new UserDto(1L, "Alice"));
>         mvc.perform(get("/users/1"))
>            .andExpect(status().isOk())
>            .andExpect(jsonPath("$.name").value("Alice"));
>     }
> }
> ```
>
> Run: `./mvnw test` or `./gradlew test`.

For security phase, inject:
> Check Spring-specific security in addition to OWASP Top 10:
> - **Spring Security config**: confirm `HttpSecurity` has explicit `authorizeHttpRequests` — no `.anyRequest().permitAll()` in production.
> - **CSRF**: verify CSRF protection is enabled for browser-facing endpoints (stateful session). API-only endpoints using JWT may disable CSRF — document the decision.
> - **Method security**: prefer `@PreAuthorize` / `@PostAuthorize` over inline `if (user.role == ...)` checks.
> - **Mass assignment / binding**: request DTOs should bind only the fields allowed — use explicit `@JsonIgnore` or separate `CreateXxxRequest` vs `UpdateXxxRequest` DTOs.
> - **Spring Actuator exposure**: `management.endpoints.web.exposure.include` must not include sensitive endpoints in production config (`/actuator/env`, `/actuator/beans`).
> - **SQL injection via JPQL**: `@Query` values with string concatenation — flag and rewrite with named parameters.
> - **`.env` / secrets**: verify `application.yml` has no hardcoded passwords — all sensitive values via `${ENV_VAR}` placeholders.

## Post-pipeline checks

- `./mvnw -q test` (or `./gradlew test`)
- `./mvnw -q -DskipTests package` (or `./gradlew -q bootJar`) — verify the JAR/WAR builds cleanly

These are advisory — failures are reported but do not retry.
