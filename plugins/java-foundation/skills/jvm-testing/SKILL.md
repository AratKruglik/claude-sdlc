---
name: jvm-testing
description: |
  JUnit 5, Mockito, AssertJ, and Testcontainers patterns for any JVM project. Covers test structure, parameterised tests, mocking discipline, fluent assertions, and integration testing with real containers. Stack-agnostic — referenced by every Java plugin in the marketplace.

  Use this skill to:
  - Write clear, maintainable unit tests with JUnit 5.
  - Mock dependencies with Mockito without overusing mocks.
  - Write expressive assertions with AssertJ.
  - Spin up real infrastructure (DBs, message brokers) with Testcontainers for integration tests.

  Do NOT use this skill for:
  - Spring-specific test slices (@SpringBootTest, @WebMvcTest, @DataJpaTest — those are in spring-boot-plugin skills).
  - Framework-specific mocking utilities (MockMvc, WebTestClient).
---

# JVM Testing Patterns (stack-agnostic)

## JUnit 5 fundamentals

```java
import org.junit.jupiter.api.*;
import static org.assertj.core.api.Assertions.*;

class UserServiceTest {

    private UserRepository repository;
    private UserService service;

    @BeforeEach
    void setUp() {
        repository = mock(UserRepository.class);
        service = new UserService(repository);
    }

    @Test
    void registerUser_withValidData_returnsActiveUser() {
        // Arrange
        var command = new RegisterUserCommand("alice@example.com", "Secret1!");
        when(repository.existsByEmail("alice@example.com")).thenReturn(false);
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        // Act
        var user = service.register(command);

        // Assert
        assertThat(user.email()).isEqualTo("alice@example.com");
        assertThat(user.isActive()).isTrue();
    }

    @Test
    void registerUser_withDuplicateEmail_throwsException() {
        when(repository.existsByEmail(any())).thenReturn(true);

        assertThatThrownBy(() -> service.register(new RegisterUserCommand("dup@example.com", "pass")))
            .isInstanceOf(DuplicateEmailException.class)
            .hasMessageContaining("dup@example.com");
    }
}
```

**Test method naming:** `methodName_condition_expectedOutcome` (readable without comments). `@DisplayName` for BDD-style prose when the method name would be unwieldy.

**AAA structure:** Arrange → Act → Assert. Separate with blank lines (no comments needed when the structure is clear).

**One assertion concept per test.** Multiple `assertThat` calls are fine when they all verify the same behaviour.

## Parameterised tests

```java
@ParameterizedTest
@ValueSource(strings = { "", " ", "\t", "\n" })
void isBlank_variousBlankStrings_returnsTrue(String input) {
    assertThat(StringUtils.isBlank(input)).isTrue();
}

@ParameterizedTest
@CsvSource({
    "alice@example.com, true",
    "not-an-email,      false",
    "@nodomain.com,     false",
})
void isValidEmail(String email, boolean expected) {
    assertThat(validator.isValid(email)).isEqualTo(expected);
}

@ParameterizedTest
@MethodSource("invalidCommands")
void register_withInvalidCommand_throws(RegisterUserCommand command) {
    assertThatThrownBy(() -> service.register(command))
        .isInstanceOf(ValidationException.class);
}

static Stream<RegisterUserCommand> invalidCommands() {
    return Stream.of(
        new RegisterUserCommand(null, "pass"),
        new RegisterUserCommand("", "pass"),
        new RegisterUserCommand("user@example.com", "")
    );
}
```

## AssertJ — fluent assertions

Prefer AssertJ over JUnit's `assertEquals` — it gives better failure messages and supports fluent chaining.

```java
// Collections
assertThat(users)
    .hasSize(3)
    .extracting(User::email)
    .containsExactlyInAnyOrder("a@x.com", "b@x.com", "c@x.com");

// Exceptions
assertThatThrownBy(() -> service.delete(unknownId))
    .isInstanceOf(EntityNotFoundException.class)
    .hasMessageContaining(unknownId.toString());

// Optional
assertThat(service.findById(42L))
    .isPresent()
    .hasValueSatisfying(u -> assertThat(u.name()).isEqualTo("Alice"));

// Soft assertions — collect all failures
assertSoftly(softly -> {
    softly.assertThat(order.status()).isEqualTo(OrderStatus.CONFIRMED);
    softly.assertThat(order.total()).isEqualByComparingTo("99.99");
    softly.assertThat(order.items()).hasSize(2);
});
```

**Never use `Assertions.assertTrue(a.equals(b))`** — the failure message shows only "expected true" with no values. Use `assertThat(a).isEqualTo(b)`.

## Mockito discipline

```java
// Constructor injection — preferred (no reflection magic, works without Spring)
var repo = mock(UserRepository.class);
var service = new UserService(repo);

// Stubbing — be specific
when(repo.findById(42L)).thenReturn(Optional.of(testUser));

// Argument matchers — use when value doesn't matter; mix carefully
when(repo.existsByEmail(anyString())).thenReturn(false);

// Capture for verification
var captor = ArgumentCaptor.forClass(User.class);
verify(repo).save(captor.capture());
assertThat(captor.getValue().email()).isEqualTo("alice@example.com");

// Verify interaction count
verify(repo, times(1)).save(any());
verify(repo, never()).delete(any());
```

**Avoid `@InjectMocks`** when possible — prefer explicit constructor injection in tests; it makes dependencies visible and avoids field-injection surprises.

**Do not mock value objects or simple data classes.** Only mock boundaries (repositories, HTTP clients, external services).

## Testcontainers — integration tests with real infrastructure

```java
@Testcontainers
class UserRepositoryIT {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine")
        .withDatabaseName("testdb")
        .withUsername("test")
        .withPassword("test");

    @BeforeAll
    static void configure() {
        // Wire datasource — exact mechanism depends on framework
        System.setProperty("spring.datasource.url", postgres.getJdbcUrl());
        System.setProperty("spring.datasource.username", postgres.getUsername());
        System.setProperty("spring.datasource.password", postgres.getPassword());
    }

    @Test
    void saveAndFindById_roundtrip() {
        var repo = buildRepository();
        var user = new User(null, "alice@example.com");

        var saved = repo.save(user);
        var found = repo.findById(saved.id());

        assertThat(found).isPresent()
            .hasValueSatisfying(u -> assertThat(u.email()).isEqualTo("alice@example.com"));
    }
}
```

**Static containers** (`static` field + `@Container`) are reused across all tests in the class — faster than per-test containers. Reuse across test classes via a shared base class or singleton pattern.

**Separate integration tests** from unit tests. Maven Failsafe plugin runs `*IT.java` in `verify`; Gradle can use source sets or a custom test task.

```xml
<!-- Maven: integration tests run in verify phase -->
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-failsafe-plugin</artifactId>
    <executions>
        <execution>
            <goals>
                <goal>integration-test</goal>
                <goal>verify</goal>
            </goals>
        </execution>
    </executions>
</plugin>
```

## Test organisation conventions

```
src/
├── main/java/com/example/...
└── test/java/com/example/
    ├── unit/                   # optional subpackage grouping
    │   └── UserServiceTest.java
    └── integration/
        └── UserRepositoryIT.java
```

Mirror the main package structure — each class under test has a corresponding test class in the same package hierarchy.

**Test class naming:**
- Unit tests: `{Subject}Test`
- Integration tests: `{Subject}IT`
- Slice tests (Spring): `{Subject}Tests` (Spring convention)

## Coverage target

Aim for ≥ 80 % line coverage on business logic (services, domain objects). Framework glue code (configuration, main class) is excluded. Use JaCoCo to measure:

```xml
<plugin>
    <groupId>org.jacoco</groupId>
    <artifactId>jacoco-maven-plugin</artifactId>
    <executions>
        <execution>
            <goals>
                <goal>prepare-agent</goal>
            </goals>
        </execution>
        <execution>
            <id>report</id>
            <phase>test</phase>
            <goals>
                <goal>report</goal>
            </goals>
        </execution>
    </executions>
</plugin>
```
