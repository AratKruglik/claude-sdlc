#!/usr/bin/env python3
"""Read-only stack-profile detector. Emits a single JSON object on stdout.

Mirrors pipeline-orchestrator/SKILL.md Step 0b (profile matching) and Step
0b-aspects (per-aspect winner resolution) exactly — this script does not
introduce new selection semantics, it precomputes the same deterministic
algorithm so the orchestrator (and a SessionStart hook) don't have to spend
LLM tool calls Glob-ing and Read-ing every installed plugin's stack.md.

Contract: never raises on a project or plugin set it cannot parse. A
malformed stack.md is skipped with a note in `parse_errors`, not a crash —
this script's output is a cache; a cache miss (or a script that produced
nothing usable) must degrade to the orchestrator's own full scan, never to
a pipeline abort.

Usage:
  detect-stack.py --repo <path> [--plugins-root <path>] [--write-cache]
                   [--cache-dir <path>]

  --repo          Project directory to evaluate detect rules against.
                   Defaults to the current directory.
  --plugins-root  Root to glob for stack.md files (recursively). Defaults
                   to ~/.claude/plugins/cache — the real installed-plugin
                   location. Overridable for tests.
  --write-cache   Also write the result to the session stack-cache file
                   (see cache_path()) after printing it to stdout.
  --cache-dir     Override the cache directory (default ~/.claude/.sdlc-
                   stack-cache). Overridable for tests.
"""
import argparse
import glob
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

CANONICAL_ASPECTS = ["backend", "frontend", "database", "infra", "testing", "messaging"]

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.S)


def parse_frontmatter(text, parse_errors, source):
    m = FRONTMATTER_RE.match(text)
    if not m:
        parse_errors.append({"source": source, "reason": "no frontmatter block"})
        return None
    fm = m.group(1)

    stack_m = re.search(r"^stack:\s*(\S+)\s*$", fm, re.M)
    if not stack_m:
        parse_errors.append({"source": source, "reason": "missing 'stack' key"})
        return None
    stack = stack_m.group(1).strip()

    priority_m = re.search(r"^priority:\s*(-?\d+)\s*$", fm, re.M)
    priority = int(priority_m.group(1)) if priority_m else 0

    aspects = []
    aspects_m = re.search(r"^aspects:\s*\[(.*?)\]\s*$", fm, re.M)
    if aspects_m:
        aspects = [a.strip().strip("\"'") for a in aspects_m.group(1).split(",") if a.strip()]

    detect = parse_detect_block(fm, parse_errors, source)
    if detect is None:
        return None

    return {"stack": stack, "priority": priority, "aspects": aspects, "detect": detect, "source": source}


def parse_detect_block(fm, parse_errors, source):
    dm = re.search(r"^detect:\s*\n((?:[ \t]+.*\n?)+)", fm, re.M)
    if not dm:
        parse_errors.append({"source": source, "reason": "missing 'detect' block"})
        return None
    block = dm.group(1)
    # The frontmatter regex swallows the newline before the closing "---" fence,
    # so the LAST line of `detect:` (often a `pattern: '...'` line) can arrive
    # here with no trailing "\n" — every line-oriented regex below assumes one.
    if not block.endswith("\n"):
        block += "\n"

    # Inline bracket form: `  any: ["*"]` (only used by the vanilla profile).
    inline_m = re.search(r"^\s*(any|all):\s*\[(.*?)\]\s*$", block, re.M)
    if inline_m:
        kind = inline_m.group(1)
        items = [i.strip().strip("\"'") for i in inline_m.group(2).split(",") if i.strip()]
        return {kind: [{"literal": i} for i in items]}

    # List form:
    #   any:
    #     - file_exists: pyproject.toml
    #     - file_contains:
    #         path: package.json
    #         pattern: '"next"\s*:'
    list_m = re.search(r"^\s*(any|all):\s*\n((?:[ \t]*-.*\n(?:[ \t]+[^-\n].*\n)*)+)", block, re.M)
    if not list_m:
        parse_errors.append({"source": source, "reason": "detect block has neither inline nor list form"})
        return None
    kind = list_m.group(1)
    items_block = list_m.group(2)

    raw_items = []
    current = None
    for line in items_block.splitlines():
        if re.match(r"^[ \t]*-\s", line):
            if current is not None:
                raw_items.append(current)
            current = line
        elif current is not None:
            current += "\n" + line
    if current is not None:
        raw_items.append(current)

    rules = []
    for raw in raw_items:
        raw = re.sub(r"^[ \t]*-\s*", "", raw, count=1)
        fe = re.match(r"^file_exists:\s*(\S+)\s*$", raw)
        if fe:
            rules.append({"file_exists": fe.group(1).strip()})
            continue
        path_m = re.search(r"^\s*path:\s*(\S+)\s*$", raw, re.M)
        pattern_m = re.search(r"^\s*pattern:\s*'(.*)'\s*$", raw, re.M) or re.search(
            r'^\s*pattern:\s*"(.*)"\s*$', raw, re.M
        )
        if path_m and pattern_m:
            rules.append({"file_contains": {"path": path_m.group(1).strip(), "pattern": pattern_m.group(1)}})
            continue
        parse_errors.append({"source": source, "reason": f"unrecognized detect rule: {raw.strip()[:60]}"})
        return None

    return {kind: rules}


def evaluate_detect(detect, repo):
    kind, rules = next(iter(detect.items()))
    results = [evaluate_rule(r, repo) for r in rules]
    return any(results) if kind == "any" else all(results)


def evaluate_rule(rule, repo):
    if "literal" in rule:
        return rule["literal"] == "*"
    if "file_exists" in rule:
        return (repo / rule["file_exists"]).is_file()
    if "file_contains" in rule:
        fc = rule["file_contains"]
        target = repo / fc["path"]
        if not target.is_file():
            return False
        try:
            text = target.read_text(encoding="utf-8", errors="replace")
        except OSError:
            return False
        try:
            return re.search(fc["pattern"], text) is not None
        except re.error:
            return False
    return False


def resolve_aspects(matched_profiles):
    active_profiles = {}
    aspect_ties = {}
    for aspect in CANONICAL_ASPECTS:
        candidates = [p for p in matched_profiles if aspect in p["aspects"]]
        if not candidates:
            active_profiles[aspect] = None
            continue
        top_priority = max(c["priority"] for c in candidates)
        winners = [c for c in candidates if c["priority"] == top_priority]
        if len(winners) > 1:
            aspect_ties[aspect] = sorted(w["stack"] for w in winners)
            active_profiles[aspect] = None
        else:
            active_profiles[aspect] = summarize(winners[0])
    return active_profiles, aspect_ties


def summarize(profile):
    return {"stack": profile["stack"], "priority": profile["priority"], "source": profile["source"]}


def resolve_primary(matched_profiles):
    if not matched_profiles:
        return None
    top_priority = max(p["priority"] for p in matched_profiles)
    winners = sorted((p for p in matched_profiles if p["priority"] == top_priority), key=lambda p: p["stack"])
    return summarize(winners[0])


def cache_path(repo, cache_dir):
    digest = hashlib.sha1(str(repo.resolve()).encode("utf-8")).hexdigest()[:16]
    return cache_dir / f"{digest}.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    ap.add_argument("--plugins-root", default=str(Path.home() / ".claude" / "plugins" / "cache"))
    ap.add_argument("--write-cache", action="store_true")
    ap.add_argument("--cache-dir", default=str(Path.home() / ".claude" / ".sdlc-stack-cache"))
    args = ap.parse_args()

    repo = Path(args.repo)
    parse_errors = []

    stack_md_paths = sorted(glob.glob(os.path.join(args.plugins_root, "**", "stack.md"), recursive=True))

    seen_signatures = set()
    profiles = []
    for path in stack_md_paths:
        try:
            text = Path(path).read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            parse_errors.append({"source": path, "reason": f"read error: {exc}"})
            continue
        rel_source = str(Path(path).relative_to(args.plugins_root)) if path.startswith(args.plugins_root) else path
        profile = parse_frontmatter(text, parse_errors, rel_source)
        if profile is None:
            continue
        # De-dupe an identical profile declared twice (e.g. a dev checkout's
        # stack.md alongside an installed copy of the same plugin) rather
        # than letting it manufacture a spurious aspect tie against itself.
        signature = (profile["stack"], profile["priority"], tuple(profile["aspects"]))
        if signature in seen_signatures:
            continue
        seen_signatures.add(signature)
        profiles.append(profile)

    matched_profiles = [p for p in profiles if evaluate_detect(p["detect"], repo)]

    active_profiles, aspect_ties = resolve_aspects(matched_profiles)
    primary_profile = resolve_primary(matched_profiles)

    result = {
        "schema_version": 1,
        "detected_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "repo": str(repo.resolve()),
        "plugins_root": args.plugins_root,
        "stack_md_scanned": len(stack_md_paths),
        "primary_profile": primary_profile,
        "active_profiles": active_profiles,
        "aspect_ties": aspect_ties,
        "matched_profiles": [
            {"stack": p["stack"], "priority": p["priority"], "aspects": p["aspects"], "source": p["source"]}
            for p in matched_profiles
        ],
        "parse_errors": parse_errors,
    }

    print(json.dumps(result))

    if args.write_cache:
        cache_dir = Path(args.cache_dir)
        try:
            cache_dir.mkdir(parents=True, exist_ok=True)
            cache_path(repo, cache_dir).write_text(json.dumps(result), encoding="utf-8")
        except OSError:
            # Cache is a pure optimization — a write failure (permissions,
            # read-only home, disk full) must never surface as an error.
            pass

    return 0


if __name__ == "__main__":
    sys.exit(main())
