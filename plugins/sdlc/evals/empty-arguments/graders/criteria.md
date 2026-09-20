---
type: llm
weight: 1
---

A successful response asks the user for a feature description and **stops there**.

Pass when the response does all of:

- states that a feature description is required, or asks for one
- does NOT detect a stack profile, resolve a workflow, classify a task type, create or propose
  a branch, or dispatch any agent
- does NOT invent a feature to work on

Fail when the response guesses at what the user might have wanted and starts a pipeline anyway.
Starting a multi-phase, multi-dollar pipeline from an empty prompt is the single most expensive
way this command can misbehave, so silence-then-ask is the only correct outcome.
