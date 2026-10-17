---
description: List all stack profiles found in installed plugins, with priority and detection rules. Useful for verifying setup and debugging stack auto-detection.
argument-hint: ""
---

# /sdlc:list-stacks

List every `stack.md` profile registered in installed plugins. Shows which one would match the current project.

## Execution (script-first)

Run one Bash call and print its stdout verbatim — it renders the whole table below, the `← active` marker, the override hint, the vanilla-only message and the tie warning:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/list-stacks.sh" --repo .
```

Development checkout fallback: `bash plugins/sdlc/scripts/list-stacks.sh --repo . --dev-root .`. The script exits 3 when `jq` is missing; only then run the inline algorithm below.

## What this command does

1. Use `Glob` to find all stack profiles:
   ```
   ~/.claude/plugins/cache/**/stack.md
   ```
2. For each profile found:
   - `Read` the file.
   - Parse the YAML frontmatter (`stack`, `priority`, `detect`).
   - Evaluate `detect` rules against the current working directory:
     - `detect.any: ["*"]` → always matches.
     - `detect.all: [...]` → all sub-rules must match.
     - `file_exists: <path>` → check via `Glob` if file exists in project root.
     - `file_contains: { path, pattern }` → `Read` the file and run regex.
3. Print a table summarizing each profile.

## Output format

```
Stack profiles found:

  🎯 vanilla       priority=0     (always matches)              ← active fallback
  🎯 laravel       priority=100   matches: composer.json + laravel/framework
  🎯 django        priority=100   no match: manage.py not present

Active profile for this project: laravel (from laravel-plugin/stack.md)
Override with: /sdlc:start --stack=NAME "<feature>"
```

If no profiles found except vanilla:
```
Only the vanilla profile is registered. Install a framework plugin
(e.g. /plugin install laravel-plugin@sdlc-marketplace) to add stack-specific agents.
```

## When to use

- After installing a new stack plugin — verify the profile is picked up.
- When `/sdlc:start` chose the wrong stack — debug detection rules.
- Before running a pipeline on a new project — confirm what will run.

## Instructions

Be concise. Print the table as plain text (no markdown table syntax — that renders poorly in chat). Mark the active profile with `← active`. If multiple profiles share the same priority and all match, mark them all and warn about ambiguity.
