#!/usr/bin/env bash
# Verifies that every relative markdown link in a tracked .md file resolves to
# a tracked path.
#
# Targets are resolved against the git index rather than the working tree, so a
# link into a gitignored directory (docs/ holds pipeline artefacts) fails here
# exactly as it would in a fresh CI checkout.
#
# Run: bash scripts/ci/check-links.sh
set -uo pipefail

# shellcheck source=scripts/ci/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_tool git "Run this inside a git checkout."
cd "$REPO_ROOT" || exit 2

WORK=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-links.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

git ls-files -z > "$WORK/tracked.z"

# Collapses `.` and `..` segments without touching the filesystem, so a link
# is resolved the same way whether or not its target exists locally.
normalize_path() {
    local IFS=/ segment
    local -a out=()
    for segment in $1; do
        case "$segment" in
            ""|.) ;;
            ..) [ ${#out[@]} -gt 0 ] && unset "out[$(( ${#out[@]} - 1 ))]" && out=("${out[@]}") ;;
            *) out+=("$segment") ;;
        esac
    done
    printf "%s" "${out[*]}"
}

tracked() {
    local path="$1"
    grep -qzxF "$path" "$WORK/tracked.z" && return 0
    grep -qz "^${path}/" "$WORK/tracked.z"
}

broken=0
links=0

while IFS= read -r -d '' file; do
    dir=$(dirname "$file")
    while IFS= read -r target; do
        case "$target" in
            ''|http://*|https://*|mailto:*|\#*) continue ;;
        esac
        target="${target%%#*}"
        target="${target%% *}"
        [ -n "$target" ] || continue
        links=$((links + 1))
        resolved=$(normalize_path "$dir/$target")
        if ! tracked "$resolved"; then
            report fail "$file → $target (resolves to $resolved, not tracked)"
            broken=$((broken + 1))
        fi
    done < <(grep -oE '\]\([^)]+\)' "$file" | sed -E 's/^\]\(//; s/\)$//')
done < <(git ls-files -z '*.md')

if [ "$broken" -eq 0 ]; then
    report ok "all $links relative markdown link(s) resolve to tracked paths"
fi

summary "check-links"
