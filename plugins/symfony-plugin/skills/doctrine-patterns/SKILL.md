---
name: doctrine-patterns
description: |
  Doctrine ORM best practices for Symfony: entity mapping as source of truth, repositories, DQL/QueryBuilder with parameters, N+1 prevention with fetch joins, relations (cascade/fetch/orphanRemoval), lifecycle events, batch processing, and generated migrations.
  Apply when: writing or reviewing Doctrine entities, repositories, and queries.
  Activated automatically by symfony-plugin/stack.md as a convention skill for the development and database phases.

  Do NOT use this skill for:
  - PHP language idioms — see php-foundation:php-conventions.
  - Controllers/services/forms — see symfony-plugin:symfony-conventions.
---

# Doctrine Patterns (Symfony)

Patterns for working with Doctrine ORM that catch the common pitfalls (N+1, DQL injection, missing indexes, broken migrations). In Doctrine the **entity mapping is the source of truth** and migrations are generated from it.

## 1. Entity mapping with attributes

```php
namespace App\Entity;

use App\Repository\SubscriptionRepository;
use Doctrine\DBAL\Types\Types;
use Doctrine\ORM\Mapping as ORM;

#[ORM\Entity(repositoryClass: SubscriptionRepository::class)]
#[ORM\Table(name: 'subscriptions')]
#[ORM\Index(columns: ['user_id', 'status'])]
class Subscription
{
    #[ORM\Id, ORM\GeneratedValue, ORM\Column]
    private ?int $id = null;

    #[ORM\ManyToOne(inversedBy: 'subscriptions')]
    #[ORM\JoinColumn(nullable: false, onDelete: 'CASCADE')]
    private User $user;

    #[ORM\Column(length: 255, unique: true)]
    private string $stripeCustomerId;

    #[ORM\Column(enumType: Status::class)]
    private Status $status;

    #[ORM\Column(type: Types::DECIMAL, precision: 10, scale: 2)]
    private string $amount;

    #[ORM\Column(type: Types::DATETIME_IMMUTABLE)]
    private \DateTimeImmutable $startsAt;
}
```

- Use `enumType:` to map a backed enum directly.
- Money/decimals map to `Types::DECIMAL` (string in PHP — never float).
- Prefer `DATETIME_IMMUTABLE` over mutable `DateTime`.
- Declare indexes/unique constraints on the entity — they become migration SQL.

## 2. Repositories — extend ServiceEntityRepository

```php
namespace App\Repository;

use App\Entity\Subscription;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;

/** @extends ServiceEntityRepository<Subscription> */
final class SubscriptionRepository extends ServiceEntityRepository
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, Subscription::class);
    }

    /** @return Subscription[] */
    public function activeForUser(User $user): array
    {
        return $this->createQueryBuilder('s')
            ->where('s.user = :user')
            ->andWhere('s.status = :status')
            ->setParameter('user', $user)
            ->setParameter('status', Status::Active)
            ->getQuery()
            ->getResult();
    }
}
```

Keep query logic in repositories — never build queries inline in controllers. Repositories are autowired by type.

## 3. DQL / QueryBuilder — always parameterized

```php
// Right — named parameters
$em->createQuery('SELECT s FROM App\Entity\Subscription s WHERE s.status = :status')
   ->setParameter('status', Status::Active)
   ->getResult();

// Wrong — string concatenation (DQL injection)
$em->createQuery("SELECT s FROM App\Entity\Subscription s WHERE s.user = " . $userId);  // ❌
$qb->where("s.name = '" . $input . "'");                                                 // ❌
```

Positional (`?1`) or named (`:name`) parameters only. The same rule applies to native SQL via `Connection::executeQuery($sql, $params)`.

## 4. N+1 prevention — fetch joins

The single most common Doctrine performance bug.

```php
// Problem: lazy relation accessed in a loop → 1 query per row
$subscriptions = $repo->findAll();
foreach ($subscriptions as $s) {
    echo $s->getUser()->getEmail();   // N+1
}

// Solution: JOIN FETCH
$repo->createQueryBuilder('s')
    ->addSelect('u')
    ->join('s.user', 'u')
    ->getQuery()
    ->getResult();
```

For read-heavy paths, also consider:
- `setFetchMode` / `#[ORM\... fetch: 'EAGER']` only for relations *always* needed (use sparingly).
- Pagination with `Doctrine\ORM\Tools\Pagination\Paginator` when fetch-joining to-many relations with `LIMIT`.

## 5. Relations — cascade, fetch, orphanRemoval

```php
#[ORM\OneToMany(mappedBy: 'subscription', targetEntity: Invoice::class, cascade: ['persist'], orphanRemoval: true)]
private Collection $invoices;

#[ORM\ManyToOne(fetch: 'LAZY')]
#[ORM\JoinColumn(onDelete: 'CASCADE')]
private User $user;
```

- Default `fetch: 'LAZY'` — avoid `EAGER` (it loads on every query, even when unused).
- `cascade: ['persist']` to save children with the parent; avoid `cascade: ['remove']` for large graphs — prefer DB `onDelete`.
- `orphanRemoval: true` deletes children removed from the collection.
- `onDelete` on `JoinColumn` enforces referential action at the DB level (faster than ORM cascade).

## 6. Identity map and flush discipline

- The `EntityManager` tracks loaded entities (identity map) — fetching the same row twice returns the same object.
- Call `flush()` once per unit of work, not per entity. Doctrine batches the SQL inside a transaction.

```php
foreach ($rows as $row) {
    $em->persist($this->toEntity($row));
}
$em->flush();   // single transaction
```

## 7. Batch processing — clear to avoid memory blowup

```php
$batchSize = 100;
$q = $em->createQuery('SELECT s FROM App\Entity\Subscription s');
foreach ($q->toIterable() as $i => $subscription) {
    $subscription->expire();
    if (($i % $batchSize) === 0) {
        $em->flush();
        $em->clear();   // detach processed entities, free memory
    }
}
$em->flush();
$em->clear();
```

## 8. Lifecycle events / listeners

For cross-cutting concerns (timestamps, audit), prefer entity listeners or event subscribers over fat services.

```php
#[ORM\Entity]
#[ORM\HasLifecycleCallbacks]
class Subscription
{
    #[ORM\PrePersist]
    public function onCreate(): void
    {
        $this->createdAt = new \DateTimeImmutable();
    }
}
```

For reusable behaviour across entities (e.g. timestampable), use a dedicated `#[AsEntityListener]` or the StofDoctrineExtensionsBundle rather than copying callbacks.

## 9. Migrations — generated, then reviewed

- The mapping is the source of truth. Generate: `php bin/console doctrine:migrations:diff`.
- **Review the generated SQL** — `diff` is not always perfect (enum CHECK constraints, defaults, index names).
- Apply: `php bin/console doctrine:migrations:migrate`. Roll back one: `... migrate prev`.
- Verify in sync: `php bin/console doctrine:schema:validate`.
- Never `doctrine:schema:update --force` outside throwaway prototypes — it bypasses migration history.

## 10. Anti-patterns to avoid

| Don't | Do |
|---|---|
| Concatenate input into DQL | `setParameter()` with `:named` / `?1` |
| `fetch: 'EAGER'` everywhere | Lazy by default; `JOIN FETCH` where needed |
| Access lazy relations in a loop | Fetch join upstream |
| `float` for money | `Types::DECIMAL` (string in PHP) |
| `flush()` inside a loop | `flush()` once per unit of work |
| `schema:update --force` | Generated migrations + review |
| Query building in controllers | Repository methods |

## 11. Checklist before merging Doctrine changes

- [ ] No N+1: loops over relations have a fetch join upstream
- [ ] All DQL/QueryBuilder uses bound parameters (no concatenation)
- [ ] Indexes declared on FKs and frequently-filtered columns
- [ ] Money/decimals use `Types::DECIMAL`; datetimes are immutable
- [ ] Relations have correct `fetch` (lazy) and `onDelete`
- [ ] `flush()` called once per unit of work; batch loops `clear()`
- [ ] Migration generated via `diff`, SQL reviewed, `down()` reverses cleanly
- [ ] `doctrine:schema:validate` reports in sync
