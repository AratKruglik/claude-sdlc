---
name: spring-conventions
description: |
  Spring Boot coding conventions: REST controller design, service layer, dependency injection, configuration, DTO patterns, exception handling, and Bean Validation. Apply on any Spring Boot project. Works alongside spring-boot-plugin:spring-data-jpa for persistence and java-foundation:java-conventions for domain objects.

  Use this skill to:
  - Structure REST endpoints with @RestController, proper HTTP semantics, and DTO mapping.
  - Enforce constructor injection and @ConfigurationProperties over @Value on fields.
  - Write @Service classes with transactional boundaries at the right layer.
  - Handle errors consistently with @RestControllerAdvice and ProblemDetail (RFC 9457).

  Do NOT use this skill for:
  - JPA entity and repository patterns — see spring-boot-plugin:spring-data-jpa.
  - Spring Security configuration — see the security phase injection in stack.md.
  - Build tool configuration — see java-foundation:build-tooling.
---

# Spring Boot Conventions

## REST Controller design

```java
@RestController
@RequestMapping("/api/v1/users")
@RequiredArgsConstructor            // Lombok — generates constructor for final fields
public class UserController {

    private final UserService userService;

    @GetMapping("/{id}")
    public UserResponse getById(@PathVariable Long id) {
        return userService.findById(id)
            .orElseThrow(() -> new EntityNotFoundException("User", id));
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public UserResponse create(@RequestBody @Valid CreateUserRequest request) {
        return userService.create(request);
    }

    @PutMapping("/{id}")
    public UserResponse update(@PathVariable Long id,
                               @RequestBody @Valid UpdateUserRequest request) {
        return userService.update(id, request);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable Long id) {
        userService.delete(id);
    }
}
```

**Return DTO directly** (not `ResponseEntity<T>`) unless you need explicit control over headers or status codes beyond `@ResponseStatus`. `ResponseEntity` is valid for partial-update responses (202 Accepted + Location header) or conditional-GET (`ETag` / `If-None-Match`).

**HTTP semantics:**
- `GET` — idempotent, no body.
- `POST` — create, return `201 Created` + new resource.
- `PUT` — replace entire resource, return `200 OK` with updated resource.
- `PATCH` — partial update.
- `DELETE` — return `204 No Content`.

## DTO patterns

```java
// Request DTO — mutable, with Bean Validation
public record CreateUserRequest(
    @NotBlank @Email String email,
    @NotBlank @Size(min = 8) String password,
    @NotNull Role role
) {}

// Response DTO — immutable record, projection of domain data
public record UserResponse(
    Long id,
    String email,
    Role role,
    Instant createdAt
) {
    public static UserResponse from(User user) {
        return new UserResponse(user.id(), user.getEmail(), user.getRole(), user.getCreatedAt());
    }
}
```

**Separate request and response types.** Never expose the JPA entity directly from the controller — it leaks schema details and creates bidirectional serialization issues.

Use **static factory methods** (`from(Entity)`) on response records for clean mapping without a mapper library when the mapping is trivial. For complex mappings with many fields, introduce a `UserMapper` interface and implement with MapStruct or plain Java.

## Service layer

```java
@Service
@Transactional(readOnly = true)     // Default to read-only; override on write methods
@RequiredArgsConstructor
public class UserService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    public Optional<UserResponse> findById(Long id) {
        return userRepository.findById(id).map(UserResponse::from);
    }

    @Transactional
    public UserResponse create(CreateUserRequest request) {
        if (userRepository.existsByEmail(request.email())) {
            throw new DuplicateEmailException(request.email());
        }
        var user = new User(request.email(), passwordEncoder.encode(request.password()), request.role());
        return UserResponse.from(userRepository.save(user));
    }

    @Transactional
    public void delete(Long id) {
        var user = userRepository.findById(id)
            .orElseThrow(() -> new EntityNotFoundException("User", id));
        userRepository.delete(user);
    }
}
```

`@Transactional(readOnly = true)` on the class sets a safe default; `@Transactional` on write methods overrides it. Avoid `@Transactional` on controllers — it spans too wide a scope and complicates error handling.

## Constructor injection

```java
// Prefer (with Lombok @RequiredArgsConstructor or explicit constructor)
@Service
public class OrderService {

    private final OrderRepository orderRepository;
    private final InvoiceService invoiceService;

    public OrderService(OrderRepository orderRepository, InvoiceService invoiceService) {
        this.orderRepository = orderRepository;
        this.invoiceService = invoiceService;
    }
}

// Avoid — field injection hides dependencies and makes testing harder
@Service
public class OrderService {
    @Autowired private OrderRepository orderRepository;  // DON'T
}
```

## Configuration with @ConfigurationProperties

```java
// application.yml
// app:
//   mail:
//     host: smtp.example.com
//     port: 587
//     from: noreply@example.com

@ConfigurationProperties(prefix = "app.mail")
public record MailProperties(String host, int port, String from) {}

// Register it
@SpringBootApplication
@EnableConfigurationProperties(MailProperties.class)
public class Application { ... }

// Inject like any bean
@Service
@RequiredArgsConstructor
public class MailService {
    private final MailProperties mailProperties;
}
```

Use `@ConfigurationProperties` records for any group of related configuration values. Avoid `@Value` on fields for groups — it scatters configuration and makes testing harder.

## Bean Validation on DTOs

```java
public record CreateProductRequest(
    @NotBlank(message = "name is required") String name,
    @NotNull @Positive BigDecimal price,
    @NotNull @Min(0) Integer stock,
    @NotBlank @Pattern(regexp = "[A-Z]{3}") String currencyCode
) {}
```

Activate in controllers with `@Valid` on `@RequestBody` / `@PathVariable` / `@ModelAttribute`. Spring Boot auto-configures `MethodArgumentNotValidException` handling — provide a `@RestControllerAdvice` to shape the error response.

## Error handling with @RestControllerAdvice

```java
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(EntityNotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ProblemDetail handleNotFound(EntityNotFoundException ex) {
        var problem = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.getMessage());
        problem.setTitle("Resource Not Found");
        return problem;
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    @ResponseStatus(HttpStatus.UNPROCESSABLE_ENTITY)
    public ProblemDetail handleValidation(MethodArgumentNotValidException ex) {
        var errors = ex.getBindingResult().getFieldErrors().stream()
            .map(e -> e.getField() + ": " + e.getDefaultMessage())
            .toList();
        var problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.UNPROCESSABLE_ENTITY, "Validation failed");
        problem.setProperty("errors", errors);
        return problem;
    }
}
```

Use `ProblemDetail` (Spring Boot 3.x, RFC 9457) for structured error responses. For Spring Boot 2.x, return a custom `ErrorResponse` record.

## Domain exceptions

```java
public class EntityNotFoundException extends RuntimeException {
    public EntityNotFoundException(String entityName, Object id) {
        super(entityName + " not found: " + id);
    }
}

public class DuplicateEmailException extends RuntimeException {
    public DuplicateEmailException(String email) {
        super("Email already registered: " + email);
    }
}
```

Keep domain exceptions in a dedicated package (`exception` or `error`). Do not catch and re-throw `RuntimeException` unless translating (e.g., wrapping a JPA exception into a domain exception).
