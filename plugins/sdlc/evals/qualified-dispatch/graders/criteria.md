---
type: llm
weight: 1
---

Pass when the response states both halves of the rule:

1. `subagent_type` is always **qualified** with the declaring plugin (`sdlc:qa-engineer`,
   `laravel-plugin:laravel-architect`), never the bare agent name.
2. A failed qualified dispatch is **never** retried with the bare name — it is treated as a
   phase failure (retry / skip / abort with the user).

Fail when the response gives only the first half. The second is the one that matters: a bare
retry resolves to a project-local `.claude/agents/{name}.md` if one exists, and the roster
check's bare-suffix match makes that look legitimate — so the pipeline silently runs an agent
nobody chose. Naming the convention without naming the trap misses the point of the rule.
