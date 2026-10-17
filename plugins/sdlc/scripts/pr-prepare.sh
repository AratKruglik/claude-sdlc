#!/usr/bin/env bash
# Git context for the documentation phase in one call, plus the optional commit + push the
# document-writer otherwise performs as a chain of separate tool calls. Emits one JSON object.
#
# Read-only without --commit-message. With it: `git add -A`, one commit with the message
# verbatim (nothing appended), and with --push a push that sets the upstream when the branch
# has none. Never force-pushes, never switches branch, never creates the PR — that stays with
# the agent, which still has to write the description.
#
# `commits_ahead` is measured against --pr-base, else the repository default branch
# (origin/HEAD, then main, then master). A base that cannot be resolved is a warning, not an
# error: the agent must see "no base" rather than a silently wrong count.
#
# Exit codes: 0 for any repository state (failures are reported inside the JSON); 2 usage.
#
# Usage: pr-prepare.sh [--project-root DIR] [--pr-base BRANCH] [--task-type TYPE]
#                      [--commit-message MSG] [--push]
set -uo pipefail

usage() {
    echo "usage: pr-prepare.sh [--project-root DIR] [--pr-base BRANCH] [--task-type TYPE] [--commit-message MSG] [--push]"
}

root="."; pr_base=""; task_type=""; commit_message=""; push=false
while [ $# -gt 0 ]; do
    case "$1" in
        --project-root)   root="${2:-}"; shift 2 ;;
        --pr-base)        pr_base="${2:-}"; shift 2 ;;
        --task-type)      task_type="${2:-}"; shift 2 ;;
        --commit-message) commit_message="${2:-}"; shift 2 ;;
        --push)           push=true; shift ;;
        -h|--help)        usage; exit 0 ;;
        *)                usage >&2; exit 2 ;;
    esac
done
[ "$push" = true ] && [ -z "$commit_message" ] && { echo "error: --push requires --commit-message" >&2; exit 2; }

json_str() {
    printf '%s' "$1" | LC_ALL=C tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_array() {
    local out="" item
    while IFS= read -r item; do
        [ -n "$item" ] || continue
        out="${out:+${out},}\"$(json_str "$item")\""
    done
    printf '[%s]' "$out"
}

warnings=""
warn() { warnings="${warnings:+${warnings},}\"$(json_str "$1")\""; }

cd "$root" 2>/dev/null || { printf '{"error":"project root not accessible","can_create_pr":false}\n'; exit 0; }
git rev-parse --git-dir >/dev/null 2>&1 || { printf '{"error":"not a git repository","can_create_pr":false}\n'; exit 0; }

case "$task_type" in
    feature)            conventional_type="feat" ;;
    fix|bugfix|hotfix)  conventional_type="fix" ;;
    refactor)           conventional_type="refactor" ;;
    docs)               conventional_type="docs" ;;
    chore|release)      conventional_type="chore" ;;
    "")                 conventional_type="feat"; warn "task_type missing: conventional_type defaulted to feat" ;;
    *)                  conventional_type="feat"; warn "task_type '${task_type}' unknown: conventional_type defaulted to feat" ;;
esac

current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
remote_url=$(git remote get-url origin 2>/dev/null || echo "")
upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo "")
has_upstream=false; [ -n "$upstream" ] && has_upstream=true

pr_base_resolved_from="flag"
if [ -z "$pr_base" ]; then
    pr_base_resolved_from="default-branch"
    pr_base=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
    if [ -z "$pr_base" ]; then
        for candidate in main master; do
            git rev-parse --verify --quiet "$candidate" >/dev/null 2>&1 && { pr_base="$candidate"; break; }
        done
    fi
    if [ -n "$pr_base" ]; then
        warn "pr_base missing: fell back to default branch ${pr_base}"
    else
        warn "pr_base missing and no default branch found: commits_ahead is unknown"
    fi
fi

base_ref=""
if [ -n "$pr_base" ]; then
    if git rev-parse --verify --quiet "$pr_base" >/dev/null 2>&1; then base_ref="$pr_base"
    elif git rev-parse --verify --quiet "origin/$pr_base" >/dev/null 2>&1; then base_ref="origin/$pr_base"
    else warn "pr_base '${pr_base}' does not resolve locally or on origin"; fi
fi

committed_sha=""; commit_error=""; pushed=false; push_error=""
if [ -n "$commit_message" ]; then
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        if git add -A 2>/dev/null && git commit -q -m "$commit_message" 2>/dev/null; then
            committed_sha=$(git rev-parse HEAD 2>/dev/null)
        else
            commit_error="git commit failed"
        fi
    else
        warn "nothing to commit: working tree clean"
    fi
    if [ "$push" = true ] && [ -z "$commit_error" ]; then
        if [ "$has_upstream" = true ]; then
            out=$(git push 2>&1) && pushed=true || push_error="$out"
        else
            out=$(git push -u origin "$current_branch" 2>&1) && pushed=true || push_error="$out"
        fi
        if [ "$pushed" = true ]; then
            upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo "")
            [ -n "$upstream" ] && has_upstream=true
        fi
    fi
fi

dirty_files=$(git status --porcelain 2>/dev/null | cut -c4-)
dirty_count=$(printf '%s\n' "$dirty_files" | grep -c '[^[:space:]]' || true)
dirty=false; [ "$dirty_count" -gt 0 ] && dirty=true

commits_ahead="null"
if [ -n "$base_ref" ]; then
    commits_ahead=$(git rev-list --count "${base_ref}..HEAD" 2>/dev/null || echo "null")
fi
can_create_pr=false
[ "$commits_ahead" != "null" ] && [ "$commits_ahead" -gt 0 ] 2>/dev/null && can_create_pr=true

gh_available=false; command -v gh >/dev/null 2>&1 && gh_available=true

opt() { if [ -n "$1" ]; then printf '"%s"' "$(json_str "$1")"; else printf 'null'; fi; }

printf '{'
printf '"current_branch":%s,' "$(opt "$current_branch")"
printf '"remote_url":%s,' "$(opt "$remote_url")"
printf '"has_upstream":%s,"upstream":%s,' "$has_upstream" "$(opt "$upstream")"
printf '"dirty":%s,"dirty_count":%s,"dirty_files":%s,' "$dirty" "$dirty_count" "$(printf '%s\n' "$dirty_files" | json_array)"
printf '"pr_base":%s,"pr_base_resolved_from":"%s",' "$(opt "$pr_base")" "$pr_base_resolved_from"
printf '"commits_ahead":%s,' "$commits_ahead"
printf '"conventional_type":"%s",' "$conventional_type"
printf '"committed_sha":%s,"commit_error":%s,' "$(opt "$committed_sha")" "$(opt "$commit_error")"
printf '"pushed":%s,"push_error":%s,' "$pushed" "$(opt "$push_error")"
printf '"gh_available":%s,"github_mcp_hint":false,' "$gh_available"
printf '"can_create_pr":%s,' "$can_create_pr"
printf '"warnings":[%s]' "$warnings"
printf '}\n'
exit 0
