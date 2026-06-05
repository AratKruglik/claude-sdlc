# java-foundation

Shared Java foundation skills for the [SDLC Marketplace](../../README.md).

This is a **pure skill library** — no agent, no stack profile. It ships stack-agnostic Java conventions referenced by every Java plugin in the marketplace (`java-plugin`, `spring-boot-plugin`, and future framework plugins).

## Skills

| Skill | Description |
|---|---|
| `java-foundation:java-conventions` | Modern Java idioms (Java 17+): records, sealed types, pattern matching, `Optional`, streams, immutability, null discipline, `var`, package layout |
| `java-foundation:build-tooling` | Maven vs Gradle detection, wrapper usage, BOM-based dependency management, version properties, multi-module projects |
| `java-foundation:jvm-testing` | JUnit 5 structure, Mockito discipline, AssertJ fluent assertions, Testcontainers integration tests, coverage with JaCoCo |

## Dependencies

- [`sdlc`](../sdlc) — core pipeline (auto-pulled on install)

## Installation

This plugin is pulled automatically as a dependency of `java-plugin` and `spring-boot-plugin`:

```
/plugin install java-plugin@sdlc-marketplace
# or
/plugin install spring-boot-plugin@sdlc-marketplace
```

To install standalone (if you want Java skills without a stack provider):

```
/plugin install java-foundation@sdlc-marketplace
```
