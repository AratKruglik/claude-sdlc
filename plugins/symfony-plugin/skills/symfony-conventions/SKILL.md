---
name: symfony-conventions
description: |
  Consolidated Symfony conventions (Symfony 6.4 / 7.x): attribute routing, controllers as services, autowiring/DI, Form types, Validation constraints, Voters for authorization, the Serializer/DTO contract, and Messenger. Apply when writing or reviewing Symfony backend code.
  Activated automatically by symfony-plugin/stack.md as a convention skill for the development phase.

  Apply when: writing or reviewing Symfony controllers, services, forms, validators, voters, and serialization.

  Do NOT use this skill for:
  - PHP language idioms (strict_types, enums, readonly) — see php-foundation:php-conventions.
  - Doctrine queries / entities — see symfony-plugin:doctrine-patterns.
  - Testing — injected by the QA phase (WebTestCase/KernelTestCase) + php-foundation:php-testing.
---

# Symfony Conventions (6.4 / 7.x)

This skill encodes the conventions used across modern Symfony projects. Apply alongside `php-foundation:php-conventions` (language idioms) when implementing features.

## 1. Attribute routing

Routes are declared with `#[Route]` attributes on controller actions — not YAML/XML for new code.

```php
namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

#[Route('/subscriptions', name: 'subscription_')]
final class SubscriptionController extends AbstractController
{
    #[Route('/{id}', name: 'show', methods: ['GET'], requirements: ['id' => '\d+'])]
    public function show(int $id): Response
    {
        // ...
    }
}
```

A class-level `#[Route]` sets a path prefix and name prefix. Always set `methods:` explicitly. Use `requirements:` to constrain route params.

## 2. Controllers as services + thin actions

- Extend `AbstractController` (gives `render()`, `json()`, `denyAccessUnlessGranted()`, `getUser()`).
- A controller with `#[Route]` is automatically registered as a service with autowired action arguments.
- Keep actions thin: authorize → map/validate input → call a service → return a response. Business logic lives in services.

```php
public function __construct(
    private readonly SubscriptionManager $subscriptions,
) {
}

#[Route('', name: 'store', methods: ['POST'])]
public function store(#[MapRequestPayload] CreateSubscriptionRequest $request): Response
{
    $this->denyAccessUnlessGranted('SUBSCRIPTION_CREATE');

    $subscription = $this->subscriptions->create($this->getUser(), $request);

    return $this->redirectToRoute('subscription_show', ['id' => $subscription->getId()]);
}
```

`#[MapRequestPayload]` deserializes + validates the request body into a DTO automatically.

## 3. Dependency injection / autowiring

- **Constructor injection only.** Never property injection or `@required` setters for new code.
- Services are autowired + autoconfigured by default (`config/services.yaml` `_defaults: autowire: true, autoconfigure: true`).
- Inject scalars/parameters with `#[Autowire]`:

```php
public function __construct(
    private readonly HttpClientInterface $http,
    #[Autowire('%env(STRIPE_SECRET)%')] private readonly string $stripeSecret,
) {
}
```

- Bind/alias an interface to an implementation in `services.yaml` only when autowiring can't resolve it. Avoid manual service definitions otherwise.

## 4. Form types

Use Form types for HTML form workflows; constructor-inject collaborators.

```php
namespace App\Form;

use Symfony\Component\Form\AbstractType;
use Symfony\Component\Form\FormBuilderInterface;
use Symfony\Component\OptionsResolver\OptionsResolver;

final class SubscriptionType extends AbstractType
{
    public function buildForm(FormBuilderInterface $builder, array $options): void
    {
        $builder
            ->add('plan', ChoiceType::class, ['choices' => Plan::cases()])
            ->add('startsAt', DateType::class, ['required' => false]);
    }

    public function configureOptions(OptionsResolver $resolver): void
    {
        $resolver->setDefaults(['data_class' => CreateSubscriptionRequest::class]);
    }
}
```

For JSON APIs prefer `#[MapRequestPayload]` DTOs over Form types.

## 5. Validation — constraints on DTOs/entities

**Always** declare validation with Constraint attributes; never validate inline in the controller.

```php
namespace App\Dto;

use Symfony\Component\Validator\Constraints as Assert;

final class CreateSubscriptionRequest
{
    public function __construct(
        #[Assert\NotBlank]
        #[Assert\Choice(['basic', 'pro', 'enterprise'])]
        public readonly string $plan,

        #[Assert\GreaterThanOrEqual('today')]
        public readonly ?\DateTimeImmutable $startsAt = null,
    ) {
    }
}
```

`#[MapRequestPayload]` runs validation automatically and returns 422 on failure. Otherwise call the `ValidatorInterface` in the service and use `#[Valid]` for nested objects.

## 6. Authorization — Voters

Centralize authorization in Voters; never inline role checks.

```php
namespace App\Security\Voter;

use App\Entity\Subscription;
use App\Entity\User;
use Symfony\Component\Security\Core\Authentication\Token\Storage\TokenInterface;
use Symfony\Component\Security\Core\Authorization\Voter\Voter;

final class SubscriptionVoter extends Voter
{
    public const VIEW = 'SUBSCRIPTION_VIEW';
    public const EDIT = 'SUBSCRIPTION_EDIT';

    protected function supports(string $attribute, mixed $subject): bool
    {
        return in_array($attribute, [self::VIEW, self::EDIT], true)
            && $subject instanceof Subscription;
    }

    protected function voteOnAttribute(string $attribute, mixed $subject, TokenInterface $token): bool
    {
        $user = $token->getUser();
        if (!$user instanceof User) {
            return false;
        }

        return $subject->getOwner() === $user || $user->isAdmin();
    }
}
```

Use via `#[IsGranted('SUBSCRIPTION_EDIT', subject: 'subscription')]` on the action, or `$this->denyAccessUnlessGranted(...)`. Coarse, path-based rules go in `security.yaml` `access_control`.

**Never** inline `if (in_array('ROLE_ADMIN', $user->getRoles()))` — that bypasses the authorization layer and is untestable.

## 7. Serializer / DTO contract

Never serialize a raw entity with all fields. Use serialization groups or dedicated DTOs.

```php
use Symfony\Component\Serializer\Attribute\Groups;

class Subscription
{
    #[Groups(['subscription:read'])]
    private int $id;

    #[Groups(['subscription:read'])]
    private string $plan;

    // no #[Groups] on stripeCustomerId → never serialized
}

// in the controller:
return $this->json($subscription, context: ['groups' => 'subscription:read']);
```

Document the exposed shape (DTO/group) so a SPA frontend agent can consume it.

## 8. Messenger — async work

Offload slow/side-effectful work to the message bus.

```php
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

final readonly class SendSubscriptionReceipt
{
    public function __construct(public int $subscriptionId) {}
}

#[AsMessageHandler]
final class SendSubscriptionReceiptHandler
{
    public function __construct(private readonly Mailer $mailer) {}

    public function __invoke(SendSubscriptionReceipt $message): void
    {
        // ...
    }
}
```

Dispatch with `$this->bus->dispatch(new SendSubscriptionReceipt($id))`. Configure transports (`async`) in `config/packages/messenger.yaml`.

## 9. Configuration

- Service config in `config/services.yaml`; package config in `config/packages/*.yaml`.
- Env values via `%env(...)%` (typed: `%env(int:...)%`, `%env(bool:...)%`). Secrets via the Secrets Vault (`bin/console secrets:set`). Never hardcode.
- Bind app parameters under `parameters:` and inject with `#[Autowire('%param%')]`.

## 10. Anti-patterns to avoid

| Don't | Do |
|---|---|
| YAML/XML routing for new controllers | `#[Route]` attributes |
| Property/setter injection | Constructor injection |
| Inline `$validator->validate()` in controllers | Constraint attributes + `#[MapRequestPayload]` / `#[Valid]` |
| `in_array('ROLE_X', $user->getRoles())` | Voter + `#[IsGranted]` |
| `return $this->json($entity)` (all fields) | Serialization groups or a DTO |
| Business logic in the controller | Service class |
| Hardcoded secrets in config | `%env(...)%` / Secrets Vault |

## 11. Checklist before completing development phase

- [ ] All new routes use `#[Route]` with explicit `methods:`
- [ ] Controllers extend `AbstractController` and are thin; logic in services
- [ ] All collaborators injected via constructor
- [ ] All input validated via Constraint attributes (no inline validation)
- [ ] Authorization via Voters / `access_control` (no inline role checks)
- [ ] Serialized output uses groups/DTOs (no raw-entity exposure)
- [ ] No hardcoded secrets — `%env(...)%` only
- [ ] `php bin/console lint:container` passes
- [ ] `vendor/bin/php-cs-fixer fix` clean
