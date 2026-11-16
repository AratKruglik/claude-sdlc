# dart-foundation

Shared Dart foundation skills for the [SDLC Marketplace](../../README.md).

This is a **pure skill library** — no agent, no stack profile. It ships stack-agnostic Dart conventions referenced by every Dart plugin in the marketplace (`dart-plugin`, `flutter-plugin`).

## Skills

| Skill | Description |
|---|---|
| `dart-foundation:dart-conventions` | Dart 3 idioms: sound null safety, records, patterns and `switch` expressions, `sealed`/`final`/`base`/`interface` class modifiers, `Future`/`Stream` discipline, immutability, Effective Dart naming and layout |
| `dart-foundation:dart-tooling` | `pubspec.yaml` constraints, `dart pub` workflow, pub workspaces, `analysis_options.yaml` + lint packages, `dart format` / `dart analyze` / `dart fix`, `build_runner` code generation |
| `dart-foundation:dart-testing` | `package:test` structure, `mocktail` mocks and fakes, async and stream matchers, test tags, coverage |

## Dependencies

- [`sdlc`](../sdlc) — core pipeline (auto-pulled on install)

## Installation

This plugin is pulled automatically as a dependency of `dart-plugin` and `flutter-plugin`:

```
/plugin install dart-plugin@sdlc-marketplace
# or
/plugin install flutter-plugin@sdlc-marketplace
```

To install standalone (if you want Dart skills without a stack provider):

```
/plugin install dart-foundation@sdlc-marketplace
```
