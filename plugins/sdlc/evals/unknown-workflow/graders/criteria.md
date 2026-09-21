---
type: llm
weight: 1
---

The user named a workflow recipe explicitly, and no such recipe exists.

Pass when the response halts and says the named workflow was not found — ideally listing the
recipes that do exist, and mentioning that omitting `--workflow=NAME` uses the default.

Fail when the response silently falls back to the `default` recipe and runs the pipeline. An
explicitly named recipe that does not exist is an operator error, not a signal to improvise:
the user asked for a specific pipeline, and quietly running a different one produces work they
did not ask for while looking like success. (Compare: a recipe *inferred* from the task type
may degrade to `default` with a warning — but this one was named.)
