#!/usr/bin/env python3
"""
PreToolUse hook: enforce declared model on every Agent() dispatch.

Claude Code sends a JSON payload on stdin:
  { "tool_name": "Agent",
    "tool_input": { "subagent_type": "...", "model": "...", ... } }

The hook reads the agent's .md frontmatter, resolves the declared model ID,
and injects it via updatedInput if missing or wrong.
"""
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

TIER_TO_MODEL = {
    "opus":   "claude-opus-4-8",
    "sonnet": "claude-sonnet-4-6",
    "haiku":  "claude-haiku-4-5-20251001",
}


def find_agent_md(agent_name: str, project_root: Path) -> Path | None:
    for candidate in project_root.rglob(f"agents/{agent_name}.md"):
        return candidate
    return None


def extract_model_from_frontmatter(md_path: Path) -> str | None:
    text = md_path.read_text(encoding="utf-8")
    m = re.search(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return None
    fm = m.group(1)
    match = re.search(r"^model:\s*(\S+)", fm, re.MULTILINE)
    return match.group(1).strip() if match else None


def resolve_model_id(tier: str) -> str | None:
    return TIER_TO_MODEL.get(tier.lower())


def log_correction(log_path: Path, agent: str, requested: str | None, enforced: str) -> None:
    ts = datetime.now(timezone.utc).isoformat(timespec="seconds")
    line = f"[{ts}] CORRECTED agent={agent} requested={requested or 'absent'} enforced={enforced}\n"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with open(log_path, "a", encoding="utf-8") as f:
        f.write(line)


def main() -> None:
    payload = json.load(sys.stdin)
    tool_name = payload.get("tool_name", "")
    tool_input = payload.get("tool_input", {})

    if tool_name != "Agent":
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}))
        return

    agent_name = tool_input.get("subagent_type", "")
    requested_model = tool_input.get("model")

    project_root = Path(os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
    log_path = project_root / "docs" / "plans" / "_model-enforcement.log"

    if not agent_name:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}))
        return

    md_path = find_agent_md(agent_name, project_root)
    if md_path is None:
        out = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
            },
            "systemMessage": f"[model-enforcement] agent '{agent_name}' .md not found — skipping model check (non-SDLC agent?)",
        }
        print(json.dumps(out))
        return

    tier = extract_model_from_frontmatter(md_path)
    if tier is None:
        out = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
            },
            "systemMessage": f"[model-enforcement] agent '{agent_name}' has no model: in frontmatter — skipping",
        }
        print(json.dumps(out))
        return

    declared_model = resolve_model_id(tier)
    if declared_model is None:
        out = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
            },
            "systemMessage": f"[model-enforcement] unknown tier '{tier}' for agent '{agent_name}' — skipping",
        }
        print(json.dumps(out))
        return

    if requested_model == declared_model:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}))
        return

    # Correction needed
    updated_input = {**tool_input, "model": declared_model}
    log_correction(log_path, agent_name, requested_model, declared_model)
    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "updatedInput": updated_input,
        },
        "systemMessage": f"[model-enforcement] CORRECTED {agent_name}: {requested_model or 'absent'} → {declared_model}",
    }
    print(json.dumps(out))


if __name__ == "__main__":
    main()
