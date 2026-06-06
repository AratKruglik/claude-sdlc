---
name: spring-data-jpa
description: |
  Spring Data JPA entity design, repository patterns, query methods, JPQL, Flyway/Liquibase migrations, and N+1 avoidance. Apply on Spring Boot projects with spring-boot-starter-data-jpa. Pairs with spring-boot-plugin:spring-conventions and java-foundation:java-conventions.

  Use this skill to:
  - Design JPA entities with proper annotations, ID strategy, and lazy loading.
  - Write JpaRepository interfaces with derived query methods and JPQL @Query.
  - Avoid N+1 queries using @EntityGraph or JOIN FETCH.
  - Manage schema evolution with Flyway or Liquibase.
  - Project query results with Spring Data Projections and DTOs.

  Do NOT use this skill for:
  - Service or controller patterns — see spring-boot-plugin:spring-conventions.
  - Build tool setup — see java-foundation:build-tooling.
  - Test slices (@DataJpaTest) — see java-foundation:jvm-testing.
---

# Spring Data JPA Patterns

## Entity design

```java
@Entity
@Table(name = "users", indexes = {
    @Index(name = "idx_users_email", columnList = "email", unique = true)
})
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true, length = 255)
    private String email;

    @Column(nullable = false)
    private String passwordHash;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 50)
    private Role role;

    @CreationTimestamp
    @Column(updatable = false)
    private Instant createdAt;

    @UpdateTimestamp
    private Instant updatedAt;

    @Version
    private Long version;                   // Optimistic locking

    protected User() {}                     // JPA requires no-arg constructor

    public User(String email, String passwordHash, Role role) {
        this.email = Objects.requireNonNull(email);
        this.passwordHash = Objects.requireNonNull(passwordHash);
        this.role = Objects.requireNonNull(role);
    }

    // Getters only — no public setters; mutate via domain methods
    public Long id() { return id; }
    public String getEmail() { return email; }
    public Role getRole() { return role; }
    public Instant getCreatedAt() { return createdAt; }

    public void changeEmail(String newEmail) {
        this.email = Objects.requireNonNull(newEmail);
    }
}
```

**ID strategy:** Use `IDENTITY` for single-node deployments (PostgreSQL, MySQL sequences). Use `SEQUENCE` with a named sequence for batch inserts (avoids INSERT per row). Avoid `AUTO` — it behaves inconsistently across databases.

**No public setters on entities.** Expose domain methods (`changeEmail`, `deactivate`, `addItem`) to enforce invariants. JPA requires a no-arg constructor — mark it `protected` so it is not called outside the framework.

**Audit timestamps:** `@CreationTimestamp` and `@UpdateTimestamp` (Hibernate) or `@EntityListeners(AuditingEntityListener.class)` + `@CreatedDate` / `@LastModifiedDate` (Spring Data Auditing). Prefer `Instant` for UTC storage.

## Relationships

```java
// Owner side (has the foreign key column)
@ManyToOne(fetch = FetchType.LAZY)
@JoinColumn(name = "user_id", nullable = false)
private User user;

// Inverse side — cascade for aggregate roots only
@OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true)
private final List<OrderItem> items = new ArrayList<>();

// Many-to-many via join table
@ManyToMany
@JoinTable(
    name = "user_roles",
    joinColumns = @JoinColumn(name = "user_id"),
    inverseJoinColumns = @JoinColumn(name = "role_id")
)
private final Set<Role> roles = new HashSet<>();
```

**Always use `FetchType.LAZY` for `@ManyToOne` and `@OneToMany`.** Eager loading (`EAGER`) fetches related data for every query including those that don't need it — a common N+1 root cause.

**`cascade = CascadeType.ALL` only on aggregate root → child relationships.** Do not cascade to unrelated entities (e.g., `Order.user` should not cascade — deleting an order must not delete the user).

## Repositories

```java
public interface UserRepository extends JpaRepository<User, Long> {

    // Derived query methods (simple cases)
    Optional<User> findByEmail(String email);
    boolean existsByEmail(String email);
    List<User> findByRoleOrderByCreatedAtDesc(Role role);

    // JPQL for joins / projections
    @Query("SELECT u FROM User u WHERE u.createdAt > :since AND u.role = :role")
    List<User> findRecentByRole(@Param("since") Instant since, @Param("role") Role role);

    // Fetch join to avoid N+1 (load items with orders in one query)
    @Query("SELECT DISTINCT o FROM Order o LEFT JOIN FETCH o.items WHERE o.user.id = :userId")
    List<Order> findOrdersWithItemsByUserId(@Param("userId") Long userId);

    // DTO projection (Spring Data interface projection)
    @Query("SELECT u.id AS id, u.email AS email FROM User u WHERE u.role = :role")
    List<UserSummary> findSummariesByRole(@Param("role") Role role);

    // Pagination
    Page<User> findByRole(Role role, Pageable pageable);

    // Modifying query
    @Modifying
    @Transactional
    @Query("UPDATE User u SET u.role = :role WHERE u.id IN :ids")
    int updateRoleForUsers(@Param("role") Role role, @Param("ids") Collection<Long> ids);
}

// DTO projection interface
public interface UserSummary {
    Long getId();
    String getEmail();
}
```

**Naming consistency:** Spring Data derives queries from method names — `findBy`, `existsBy`, `countBy`, `deleteBy`. Match field names exactly (case-sensitive on the entity field name).

**Never use `@Query` with string concatenation.** Named parameters only (`:paramName`). Positional parameters (`?1`) are allowed but named is more readable.

## Avoiding N+1 queries

The N+1 problem: loading a list of entities, then JPA fires a separate SELECT for each entity's lazy collection.

```java
// Problem — 1 query for orders + N queries for items
List<Order> orders = orderRepository.findAll();
orders.forEach(o -> o.getItems().size()); // triggers N lazy loads

// Solution 1 — @EntityGraph (no JPQL rewrite needed)
@EntityGraph(attributePaths = {"items", "items.product"})
List<Order> findAll();

// Solution 2 — JOIN FETCH in JPQL (more explicit)
@Query("SELECT DISTINCT o FROM Order o LEFT JOIN FETCH o.items WHERE o.status = :status")
List<Order> findWithItemsByStatus(@Param("status") OrderStatus status);
```

**Use `DISTINCT` with `LEFT JOIN FETCH` on `@OneToMany`** — without it, the same order row is duplicated for each item in the result set.

**Do not use `@EntityGraph` or `JOIN FETCH` by default on all queries.** Apply only when the caller actually needs the association. Over-fetching is also a performance problem.

## Schema migrations

### Flyway (preferred)

```
src/main/resources/
└── db/migration/
    ├── V1__create_users.sql
    ├── V2__create_orders.sql
    └── V3__add_order_status.sql
```

Naming convention: `V{version}__{description}.sql`. Version must be monotonically increasing (integers or timestamps). Description uses underscores.

```sql
-- V3__add_order_status.sql
ALTER TABLE orders
    ADD COLUMN status VARCHAR(50) NOT NULL DEFAULT 'PENDING';

CREATE INDEX idx_orders_status ON orders (status);
```

**Flyway runs on startup** when `spring.flyway.enabled=true` (default when `flyway-core` is on the classpath). Migrations are applied in version order and checksummed — never edit a migration that has already been applied.

**Test migrations** with Testcontainers (`@DataJpaTest` or `@SpringBootTest` with a PostgreSQL container) — H2 may accept SQL that PostgreSQL rejects.

### Liquibase (alternative)

```yaml
# src/main/resources/db/changelog/db.changelog-master.yaml
databaseChangeLog:
  - include:
      file: db/changelog/changes/0001-create-users.yaml
```

```yaml
# db/changelog/changes/0001-create-users.yaml
databaseChangeLog:
  - changeSet:
      id: 0001
      author: dev
      changes:
        - createTable:
            tableName: users
            columns:
              - column:
                  name: id
                  type: BIGINT
                  autoIncrement: true
                  constraints:
                    primaryKey: true
              - column:
                  name: email
                  type: VARCHAR(255)
                  constraints:
                    nullable: false
                    unique: true
```

## Pagination and sorting

```java
// Endpoint
@GetMapping
public Page<UserResponse> list(
    @RequestParam(defaultValue = "0") int page,
    @RequestParam(defaultValue = "20") int size,
    @RequestParam(defaultValue = "createdAt,desc") String sort
) {
    var pageable = PageableHandlerMethodArgumentResolver.DEFAULT_PAGE_SIZE > 0
        ? PageRequest.of(page, Math.min(size, 100), Sort.by(Sort.Direction.DESC, "createdAt"))
        : Pageable.unpaged();
    return userRepository.findAll(pageable).map(UserResponse::from);
}
```

Cap the maximum `size` to prevent unbounded queries (`Math.min(size, 100)`). Use `PageRequest.of(page, size, sort)` — always validate sort field against an allowlist to prevent arbitrary column exposure.

## Optimistic locking

Add `@Version Long version` to entities shared across concurrent writes. On update, Hibernate includes `WHERE id = ? AND version = ?`. If the version does not match, `OptimisticLockException` is thrown — catch it at the service layer and translate to a domain exception.

```java
@Transactional
public OrderResponse confirmOrder(Long orderId) {
    try {
        var order = orderRepository.findById(orderId).orElseThrow(...);
        order.confirm();
        return OrderResponse.from(orderRepository.save(order));
    } catch (OptimisticLockException | StaleObjectStateException e) {
        throw new ConcurrentModificationException("Order was modified concurrently, please retry");
    }
}
```
