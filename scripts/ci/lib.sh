# shellcheck shell=bash
# shellcheck disable=SC2034  # REPO_ROOT is consumed by the sourcing script
# Shared helpers for scripts/ci/*.sh. Sourced, never executed.
#
# Every CI helper is bash + jq (+ yq for YAML). No Python anywhere.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ci_fail_count=0
ci_check_count=0

report() {
    local status="$1" detail="$2"
    ci_check_count=$((ci_check_count + 1))
    if [ "$status" = "ok" ]; then
        printf 'PASS  %s\n' "$detail"
    else
        ci_fail_count=$((ci_fail_count + 1))
        printf 'FAIL  %s\n' "$detail"
    fi
}

summary() {
    printf '\n=== %s: %d checked, %d failed ===\n' "$1" "$ci_check_count" "$ci_fail_count"
    [ "$ci_fail_count" -eq 0 ]
}

require_tool() {
    local tool="$1" hint="$2"
    command -v "$tool" >/dev/null 2>&1 && return 0
    printf 'ERROR: %s is required but not installed. %s\n' "$tool" "$hint" >&2
    exit 2
}

# Prints the YAML frontmatter of a markdown file (the block between the first
# two `---` lines), or nothing when the file has none.
frontmatter() {
    awk '
        NR == 1 && $0 != "---" { exit }
        NR == 1 { next }
        /^---[[:space:]]*$/ { exit }
        { print }
    ' "$1"
}
