#!/usr/bin/env bash
# Test harness for the task-type classifier data file (references/task-type-patterns.json).
#
# Compiles each pattern with `node` (ECMAScript regex engine — the same engine the
# orchestrator's model-driven Step C classification is specified against) and checks
# classification outcomes plus a sanity invariant: no pattern may contain a literal `\b`,
# since ECMAScript `\w` is [A-Za-z0-9_] and `\b` never asserts a boundary next to a
# non-Latin character, with or without the `u` flag. That exact bug is why every Cyrillic
# keyword in this table used to be permanently dead — see GIT-FLOW.md Step C-2.
#
# Run: bash plugins/sdlc/scripts/test-task-typing.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATTERNS_FILE="${SCRIPT_DIR}/../references/task-type-patterns.json"

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP  node not found — cannot exercise ECMAScript regex patterns"
    exit 0
fi

if [ ! -f "$PATTERNS_FILE" ]; then
    echo "FAIL  patterns file not found: $PATTERNS_FILE"
    exit 1
fi

CLASSIFY_HELPER=$(mktemp "${TMPDIR:-/tmp}/sdlc-task-typing-helper.XXXXXX.mjs")
trap 'rm -f "$CLASSIFY_HELPER"' EXIT

cat > "$CLASSIFY_HELPER" <<'NODE_EOF'
import { readFileSync } from "node:fs";

const [, , mode, patternsPath, text] = process.argv;
const data = JSON.parse(readFileSync(patternsPath, "utf8"));

if (mode === "sanity-no-word-boundary") {
    const offenders = [];
    const groups = Object.entries(data.types);
    for (const [name, rule] of Object.entries(data.skip_rules ?? {})) groups.push([`skip_rules.${name}`, rule]);
    for (const [type, { patterns }] of groups) {
        for (const pattern of patterns) {
            if (pattern.includes("\\b")) offenders.push(`${type}: ${pattern}`);
        }
    }
    if (offenders.length > 0) {
        process.stderr.write(offenders.join("\n") + "\n");
        process.exit(1);
    }
    process.exit(0);
}

if (mode === "skip-rule") {
    const [, , , , , ruleName] = process.argv;
    const rule = data.skip_rules?.[ruleName];
    if (!rule) { process.stderr.write(`no such skip rule: ${ruleName}\n`); process.exit(2); }
    const hit = rule.patterns.some((p) => new RegExp(p, data.flags).test(text));
    process.stdout.write(hit ? "match\n" : "no-match\n");
    process.exit(0);
}

if (mode === "classify") {
    for (const type of data.precedence) {
        const { patterns } = data.types[type];
        if (patterns.some((p) => new RegExp(p, data.flags).test(text))) {
            process.stdout.write(`${type} matched\n`);
            process.exit(0);
        }
    }
    // GIT-FLOW.md Step C-2: "No match -> feature, confidence low".
    process.stdout.write("feature fallback\n");
    process.exit(0);
}

process.stderr.write(`unknown mode: ${mode}\n`);
process.exit(2);
NODE_EOF

pass_count=0
fail_count=0

# $1 = case name, $2 = input text, $3 = expected "<type> <matched|fallback>"
assert_classify() {
    local case_name="$1" text="$2" expected="$3"
    local actual
    actual=$(node "$CLASSIFY_HELPER" classify "$PATTERNS_FILE" "$text" 2>&1)
    if [ "$actual" = "$expected" ]; then
        pass_count=$((pass_count + 1))
        printf 'PASS  %-46s %-58s -> %s\n' "$case_name" "$text" "$actual"
    else
        fail_count=$((fail_count + 1))
        printf 'FAIL  %-46s %-58s expected %q, got %q\n' "$case_name" "$text" "$expected" "$actual"
    fi
}

# $1 = case name, $2 = rule name, $3 = input text, $4 = expected match|no-match
assert_skip_rule() {
    local case_name="$1" rule="$2" text="$3" expected="$4"
    local actual
    actual=$(node "$CLASSIFY_HELPER" skip-rule "$PATTERNS_FILE" "$text" "$rule" 2>&1)
    if [ "$actual" = "$expected" ]; then
        pass_count=$((pass_count + 1))
        printf 'PASS  %-46s %-58s -> %s\n' "$case_name" "$text" "$actual"
    else
        fail_count=$((fail_count + 1))
        printf 'FAIL  %-46s %-58s expected %q, got %q\n' "$case_name" "$text" "$expected" "$actual"
    fi
}

assert_sanity() {
    local case_name="$1"
    local output
    if output=$(node "$CLASSIFY_HELPER" sanity-no-word-boundary "$PATTERNS_FILE" "" 2>&1); then
        pass_count=$((pass_count + 1))
        printf 'PASS  %-46s no pattern contains a literal \\b\n' "$case_name"
    else
        fail_count=$((fail_count + 1))
        printf 'FAIL  %-46s literal \\b found:\n%s\n' "$case_name" "$output"
    fi
}

echo "=== Sanity: the defect that shipped invisibly ==="
assert_sanity "no-word-boundary-in-patterns"

echo ""
echo "=== Ukrainian input (previously unclassifiable — defect 1) ==="
assert_classify "uk-refactor"      "зробити рефакторинг резолвера"      "refactor matched"
assert_classify "uk-hotfix"        "терміново виправити продакшн"       "hotfix matched"
assert_classify "uk-feature"       "додай нову фазу"                    "feature matched"
assert_classify "uk-docs"          "оновити документацію"               "docs matched"

echo ""
echo "=== English input (regression — must still classify correctly) ==="
assert_classify "en-refactor"      "refactor the resolver"              "refactor matched"
assert_classify "en-fix"           "fix the login bug"                  "fix matched"
assert_classify "en-hotfix"        "urgent production fix"              "hotfix matched"

echo ""
echo "=== False-positive guards (left/right Unicode boundary correctness) ==="
assert_classify "no-match-in-prefix"      "prefix handling"             "feature fallback"
assert_classify "no-match-in-superrefactor" "суперрефакторинг"          "feature fallback"
assert_classify "no-match-in-newsletter"  "newsletter signup"           "feature fallback"
assert_classify "ing-suffix-matches"      "refactoring done"            "refactor matched"

echo ""
echo "=== Precedence on multiple matches (GIT-FLOW.md Step C-3 worked example) ==="
assert_classify "precedence-hotfix-wins" "urgently refactor the broken payment fix" "hotfix matched"

echo ""
echo ""
echo "=== Skip-rule typo_fix patterns (SKILL Step 0c-2 rule 1) ==="
assert_skip_rule "typo-en"            typo_fix "typo in the header"                 match
assert_skip_rule "typo-en-midphrase"  typo_fix "fix the typo in the header"         match
assert_skip_rule "rename-en"          typo_fix "rename userId to accountId"         match
assert_skip_rule "reformat-en"        typo_fix "reformat the config block"          match
assert_skip_rule "misspell-en"        typo_fix "misspelled variable name"           match
assert_skip_rule "typo-uk-opechatka"  typo_fix "виправити опечатку в заголовку"     match
assert_skip_rule "typo-uk-odruk"      typo_fix "одруківка в тексті помилки"         match
assert_skip_rule "format-uk"          typo_fix "переформатувати конфіг"             match
assert_skip_rule "rename-uk"          typo_fix "перейменувати метод"                match
# Guards: a real feature must not be waved through the BA phase.
assert_skip_rule "guard-feature"      typo_fix "add subscription billing"           no-match
assert_skip_rule "guard-format-noun"  typo_fix "support the JSON export format"     no-match
assert_skip_rule "guard-prototype"    typo_fix "prototype the new renamer"          no-match

echo "----------------------------------------"
echo "Passed: $pass_count  Failed: $fail_count"

if [ "$fail_count" -gt 0 ]; then
    exit 1
fi
exit 0
