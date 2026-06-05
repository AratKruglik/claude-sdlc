---
name: java-conventions
description: |
  Modern Java idioms for any JVM project (Java 17+): records, sealed types, text blocks, pattern matching, Optional discipline, streams, immutability, null safety, package layout, var usage, and code organisation. Apply when the project is a Java 17+ project. Stack-agnostic — referenced by every Java plugin in the marketplace.

  Use this skill to:
  - Write self-documenting, immutable-by-default value types with records.
  - Model closed type hierarchies with sealed classes and interfaces.
  - Handle optionality explicitly with Optional instead of returning null.
  - Write expressive pipelines with Stream API without performance footguns.
  - Lay out packages consistently (feature-first or layer-first) and keep class responsibilities tight.

  Do NOT use this skill for:
  - Framework-specific idioms (Spring annotations, JPA mappings — those live in framework plugin skills).
  - Build tooling (Maven/Gradle) — see java-foundation:build-tooling.
  - Testing patterns — see java-foundation:jvm-testing.
---

# Java Conventions (stack-agnostic, Java 17+)

This skill encodes idioms that reduce bugs and improve readability in any Java codebase. Apply alongside the active framework plugin's conventions skill (e.g., `spring-boot-plugin:spring-conventions`).

## Detection

Project is Java 17+ when:
- `pom.xml` has `<java.version>17</java.version>` or `<maven.compiler.source>17</maven.compiler.source>` (or higher).
- `build.gradle` / `build.gradle.kts` has `sourceCompatibility = JavaVersion.VERSION_17` (or higher).

Read the build file first to learn the target Java version.

## Records — prefer for value objects

Use records for immutable data carriers. They auto-generate constructor, `equals`, `hashCode`, `toString`.

```java
// Prefer
public record Money(BigDecimal amount, Currency currency) {
    public Money {
        Objects.requireNonNull(amount, "amount");
        Objects.requireNonNull(currency, "currency");
        if (amount.compareTo(BigDecimal.ZERO) < 0) {
            throw new IllegalArgumentException("amount must be non-negative");
        }
    }

    public Money add(Money other) {
        if (!this.currency.equals(other.currency)) {
            throw new IllegalArgumentException("Currency mismatch");
        }
        return new Money(this.amount.add(other.amount), this.currency);
    }
}

// Avoid — a plain class with no behaviour
public class Money {
    private final BigDecimal amount;
    private final Currency currency;
    // ... boilerplate constructor, getters, equals, hashCode, toString
}
```

Compact constructor (without parameter list) is for validation only — do not assign fields there (the canonical constructor does that).

## Sealed types — model closed hierarchies

```java
public sealed interface Shape permits Circle, Rectangle, Triangle {}

public record Circle(double radius) implements Shape {}
public record Rectangle(double width, double height) implements Shape {}
public record Triangle(double base, double height) implements Shape {}

double area(Shape shape) {
    return switch (shape) {
        case Circle c    -> Math.PI * c.radius() * c.radius();
        case Rectangle r -> r.width() * r.height();
        case Triangle t  -> 0.5 * t.base() * t.height();
    };
}
```

The compiler verifies exhaustiveness — no default branch needed. Add `default` only when genuinely required (e.g., a catch-all for unexpected extensions via `--enable-preview`).

## Pattern matching — eliminate casting

```java
// instanceof pattern matching (Java 16+)
if (obj instanceof String s && s.length() > 5) {
    System.out.println(s.toUpperCase());
}

// switch pattern matching (Java 21+)
String format(Object obj) {
    return switch (obj) {
        case Integer i -> "int: " + i;
        case Long l    -> "long: " + l;
        case String s  -> "str: " + s;
        case null      -> "null";
        default        -> "other: " + obj.getClass().getSimpleName();
    };
}
```

Never cast without an `instanceof` check — use pattern binding instead.

## Optional — explicit optionality

```java
// Return Optional when absence is a normal outcome
public Optional<User> findById(Long id) {
    return repository.findById(id); // JPA returns Optional
}

// Consume safely
findById(id)
    .map(User::email)
    .ifPresent(email -> sendWelcome(email));

// With fallback
String name = findById(id)
    .map(User::name)
    .orElse("Guest");

// Throwing on absence (documented expectation)
User user = findById(id)
    .orElseThrow(() -> new EntityNotFoundException("User " + id));
```

**Avoid `Optional.get()` without `isPresent()`** — defeats the purpose. Prefer `orElse`, `orElseThrow`, `orElseGet`, `map`, `flatMap`, `ifPresent`, `ifPresentOrElse`.

**Never use `Optional` as a field type or method parameter** — it is designed for return types only.

## Streams — readable pipelines

```java
// Prefer readable pipeline over imperative loop
List<String> activeEmails = users.stream()
    .filter(User::isActive)
    .map(User::email)
    .sorted()
    .toList();                        // Java 16+ — unmodifiable

// Collect to mutable list when mutation needed
List<String> mutable = users.stream()
    .map(User::name)
    .collect(Collectors.toCollection(ArrayList::new));

// Grouping
Map<Department, List<User>> byDept = users.stream()
    .collect(Collectors.groupingBy(User::department));

// Reduction
BigDecimal total = orders.stream()
    .map(Order::amount)
    .reduce(BigDecimal.ZERO, BigDecimal::add);
```

**Avoid `forEach` with side effects** on parallel streams — use sequential streams or synchronised structures. Use `parallelStream` only after profiling.

## Immutability

- Prefer `final` fields. Make classes effectively immutable where feasible.
- Return `List.copyOf`, `Map.copyOf`, `Set.copyOf` to defensive-copy mutable collections.
- Use `List.of`, `Map.of`, `Set.of` for literals.
- Never expose mutable internal state via getters — return a copy or an unmodifiable view.

```java
public List<String> getTags() {
    return List.copyOf(this.tags);       // defensive copy
}
```

## Null discipline

- Annotate parameters and return types with `@NonNull` / `@Nullable` (Jakarta / JetBrains / SpotBugs — match project choice).
- Validate at public API boundaries with `Objects.requireNonNull(value, "fieldName")`.
- Do not return `null` from public methods — use `Optional`, empty collections, or throw.

```java
public User register(String email, String password) {
    Objects.requireNonNull(email, "email");
    Objects.requireNonNull(password, "password");
    // ...
}
```

## Text blocks (Java 15+)

```java
String json = """
        {
            "name": "%s",
            "active": true
        }
        """.formatted(user.name());
```

Use for multi-line SQL, JSON, HTML snippets, and test fixtures. Indent consistently with the enclosing code — the compiler strips common leading whitespace.

## `var` — local type inference

```java
// Good — type obvious from right-hand side
var users = new ArrayList<User>();
var result = userRepository.findAll();

// Avoid — type not obvious from right-hand side
var x = process(data);     // what type is x?
```

`var` is for local variables only. Never use it for fields, parameters, or return types.

## Package layout

Choose one layout and be consistent:

**Feature-first (preferred for domain-rich apps):**
```
com.example.app/
├── user/
│   ├── User.java
│   ├── UserRepository.java
│   ├── UserService.java
│   └── UserController.java
├── order/
│   └── ...
└── shared/
    └── ...
```

**Layer-first (acceptable for simple CRUD services):**
```
com.example.app/
├── controller/
├── service/
├── repository/
├── model/
└── dto/
```

Mirror the existing project layout. Do not introduce a new layout as part of feature work.

## Class design rules

- Single Responsibility: one reason to change per class.
- Keep public API minimal — `package-private` by default, `public` only when needed.
- Prefer composition over inheritance for behaviour reuse.
- Use `interface` to define contracts; keep implementations in the same package unless genuinely shared.
- No `static` utility classes with state. Static helpers for stateless pure functions are fine.
