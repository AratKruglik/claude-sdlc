---
stack: vanilla
priority: 0
detect:
  any: ["*"]
---

# Vanilla Stack Profile

Fallback profile. Always matches. Loses to any framework profile with higher `priority`.

## Agents per phase

- business_analysis: business-analyst
- development: developer
- qa: qa-engineer
- security: security-analyst
- documentation: document-writer

## Convention skills to apply

(none)

## Extra phases

(none)

## Phase prompts injection

(none — base prompts in pipeline-orchestrator are used as-is)

## Pre-phase commands

(none)

## Post-pipeline checks

(none — vanilla pipeline assumes the project has its own test/lint scripts that the user invokes manually)
