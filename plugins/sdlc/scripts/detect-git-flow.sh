#!/usr/bin/env bash
# Read-only git branching-model detector. Emits a single JSON object on stdout.
#
# Consumed by pipeline-orchestrator Step 0b-git (via references/GIT-FLOW.md) and by
# /sdlc:doctor. It reports OBSERVATIONS ONLY — the type→branch policy matrix lives in
# references/GIT-FLOW.md, because that layer is overridable by the `git:` block in
# .claude/sdlc.local.yaml and the script has no business reading project config.
#
# Contract: never exits non-zero on a repo it cannot understand. A detector that fails
# hard would abort a pipeline over a cosmetic question; it degrades to model=unknown and
# lets the caller fall back to its own conservative default.
#
# Usage: detect-git-flow.sh [--allow-network] [--repo <path>]
#
#   --allow-network  permit one `git ls-remote` when the repo has an `origin` but no
#                    remote-tracking refs at all (cloned --no-checkout, or never fetched).
#                    Off by default: detection must not block on a network round-trip.
set -uo pipefail

ALLOW_NETWORK=0
REPO_PATH="."

while [ $# -gt 0 ]; do
    case "$1" in
        --allow-network) ALLOW_NETWORK=1; shift ;;
        --repo)          REPO_PATH="${2:-.}"; shift 2 ;;
        *)               shift ;;
    esac
done

cd "$REPO_PATH" 2>/dev/null || {
    printf '{"schema_version":1,"model":"unknown","confidence":"low","reason":"path not accessible"}\n'
    exit 0
}

# Known git-flow / conventional-commit branch vocabulary. Used for two things only:
# (a) deciding whether a dash-separated name is `fix-foo` (prefix) or `add-foo` (just a
# slug that happens to contain a dash), and (b) labelling the observed vocabulary.
# It is NOT a whitelist — an unrecognised prefix is reported, never discarded.
KNOWN_PREFIXES="feature feat fix bugfix hotfix release docs doc chore refactor test perf ci build style"

is_known_prefix() {
    case " $KNOWN_PREFIXES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# Minimal JSON string escaping. Git ref names forbid space, ~, ^, :, ?, *, [ and \ but
# permit a double quote, so unescaped interpolation of a branch name can produce invalid
# JSON. Control characters are stripped rather than escaped — they have no legitimate
# place in a ref name and the consumer is a JSON parser, not a terminal.
json_str() {
    printf '%s' "$1" | LC_ALL=C tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

emit_unknown() {
    printf '{"schema_version":1,"model":"unknown","confidence":"low","reason":"%s",' "$(json_str "$1")"
    printf '"default_branch":null,"develop_branch":null,"current_branch":null,'
    printf '"prefix_style":"none","prefix_histogram":{},"branches_analyzed":0,'
    printf '"git_flow_cli_available":false,"git_flow_initialized":false}\n'
    exit 0
}

git rev-parse --git-dir >/dev/null 2>&1 || emit_unknown "not a git repository"

# ---------------------------------------------------------------------------
# Collect branch names
# ---------------------------------------------------------------------------

LOCAL_BRANCHES=$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)
REMOTE_REFS=$(git for-each-ref --format='%(refname:short)' refs/remotes 2>/dev/null \
    | grep -v '/HEAD$' || true)

# Strip the remote name so origin/feature/x and feature/x collapse to one entry.
REMOTE_BRANCHES=$(printf '%s\n' "$REMOTE_REFS" | sed 's|^[^/]*/||' | grep -v '^$' || true)
REMOTE_REF_COUNT=$(printf '%s\n' "$REMOTE_REFS" | grep -c '[^[:space:]]' || true)

BRANCHES=$(printf '%s\n%s\n' "$LOCAL_BRANCHES" "$REMOTE_BRANCHES" \
    | grep -v '^$' | sort -u || true)
BRANCH_COUNT=$(printf '%s\n' "$BRANCHES" | grep -c '[^[:space:]]' || true)

[ "$BRANCH_COUNT" -eq 0 ] && emit_unknown "repository has no branches"

has_branch() {
    printf '%s\n' "$BRANCHES" | grep -qx "$1"
}

# ---------------------------------------------------------------------------
# Default branch
# ---------------------------------------------------------------------------

DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')

if [ -z "$DEFAULT_BRANCH" ]; then
    # No origin/HEAD (common in a local-only repo, or a clone that never ran
    # `git remote set-head`). Probe the conventional names before trusting
    # init.defaultBranch, which describes how NEW repos are created, not this one.
    for candidate in main master trunk; do
        if has_branch "$candidate"; then DEFAULT_BRANCH="$candidate"; break; fi
    done
fi
[ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH=$(git config --get init.defaultBranch 2>/dev/null)
[ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

# ---------------------------------------------------------------------------
# develop branch, gitflow config, release branches
# ---------------------------------------------------------------------------

DEVELOP_BRANCH=""
for candidate in develop dev development; do
    if has_branch "$candidate"; then DEVELOP_BRANCH="$candidate"; break; fi
done

# A repo with an origin but zero remote-tracking refs has never been fetched, so the
# local ref scan above cannot see a develop branch that exists on the remote. This is
# the only case worth a network call, and only when explicitly permitted.
if [ -z "$DEVELOP_BRANCH" ] && [ "$ALLOW_NETWORK" -eq 1 ] && [ "$REMOTE_REF_COUNT" -eq 0 ]; then
    if git remote get-url origin >/dev/null 2>&1; then
        REMOTE_HEADS=$(git ls-remote --heads origin develop dev development 2>/dev/null || true)
        for candidate in develop dev development; do
            if printf '%s\n' "$REMOTE_HEADS" | grep -q "refs/heads/$candidate$"; then
                DEVELOP_BRANCH="$candidate"
                break
            fi
        done
    fi
fi

GITFLOW_CONFIG_COUNT=$(git config --get-regexp '^gitflow\.' 2>/dev/null | grep -c '[^[:space:]]' || true)

RELEASE_BRANCHES=$(printf '%s\n' "$BRANCHES" | grep -E '^(release|releases)/' || true)

# ---------------------------------------------------------------------------
# git-flow CLI (AVH edition) availability — read-only probe, never installs or inits
# ---------------------------------------------------------------------------

GIT_FLOW_CLI_AVAILABLE="false"
command -v git-flow >/dev/null 2>&1 && GIT_FLOW_CLI_AVAILABLE="true"
if [ "$GIT_FLOW_CLI_AVAILABLE" = "false" ]; then
    git flow version >/dev/null 2>&1 && GIT_FLOW_CLI_AVAILABLE="true"
fi

# `git flow init` writes gitflow.branch.master / gitflow.branch.develop, distinct from the
# gitflow.prefix.* keys a prefix-only config might carry.
GIT_FLOW_INITIALIZED="false"
if [ -n "$(git config --get gitflow.branch.master 2>/dev/null)" ] \
    && [ -n "$(git config --get gitflow.branch.develop 2>/dev/null)" ]; then
    GIT_FLOW_INITIALIZED="true"
fi

# ---------------------------------------------------------------------------
# Naming convention
# ---------------------------------------------------------------------------

SEPARATOR="/"
PREFIXED=$(printf '%s\n' "$BRANCHES" | grep -E '^[A-Za-z][A-Za-z0-9._-]*/' || true)

if [ -z "$PREFIXED" ]; then
    # No slash-separated names. Only treat a dash as the separator when the leading
    # token is actually vocabulary — otherwise `add-healthz-endpoint` would be read as
    # prefix `add`, inventing a convention out of an ordinary slug.
    DASH_CANDIDATES=""
    while IFS= read -r branch; do
        [ -z "$branch" ] && continue
        head="${branch%%-*}"
        [ "$head" = "$branch" ] && continue
        if is_known_prefix "$(printf '%s' "$head" | tr '[:upper:]' '[:lower:]')"; then
            DASH_CANDIDATES="${DASH_CANDIDATES}${branch}
"
        fi
    done <<EOF
$BRANCHES
EOF
    DASH_COUNT=$(printf '%s\n' "$DASH_CANDIDATES" | grep -c '[^[:space:]]' || true)
    if [ "$DASH_COUNT" -ge 2 ]; then
        SEPARATOR="-"
        PREFIXED="$DASH_CANDIDATES"
    fi
fi

# Histogram of prefixes. A count of 1 is discarded: a single occurrence is far more
# often a typo (this repo carries a real `feaature/optimization`) than a convention,
# and learning it would propose misspelled branch names forever.
HISTOGRAM_RAW=""
if [ -n "$PREFIXED" ]; then
    if [ "$SEPARATOR" = "/" ]; then
        HISTOGRAM_RAW=$(printf '%s\n' "$PREFIXED" | sed 's|/.*||' | grep -v '^$' | sort | uniq -c | sort -rn)
    else
        HISTOGRAM_RAW=$(printf '%s\n' "$PREFIXED" | sed 's|-.*||' | grep -v '^$' | sort | uniq -c | sort -rn)
    fi
fi

HISTOGRAM_JSON=""
DISTINCT_PREFIXES=0
KNOWN_HITS=0
UNKNOWN_HITS=0
while IFS= read -r line; do
    [ -z "$line" ] && continue
    count=$(printf '%s' "$line" | awk '{print $1}')
    name=$(printf '%s' "$line" | awk '{print $2}')
    [ -z "$name" ] && continue
    [ "$count" -lt 2 ] && continue
    DISTINCT_PREFIXES=$((DISTINCT_PREFIXES + 1))
    if is_known_prefix "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"; then
        KNOWN_HITS=$((KNOWN_HITS + 1))
    else
        UNKNOWN_HITS=$((UNKNOWN_HITS + 1))
    fi
    [ -n "$HISTOGRAM_JSON" ] && HISTOGRAM_JSON="${HISTOGRAM_JSON},"
    HISTOGRAM_JSON="${HISTOGRAM_JSON}\"$(json_str "$name")\":${count}"
done <<EOF
$HISTOGRAM_RAW
EOF

if [ "$DISTINCT_PREFIXES" -eq 0 ]; then
    PREFIX_STYLE="none"
    SEPARATOR="/"
elif [ "$UNKNOWN_HITS" -gt "$KNOWN_HITS" ]; then
    PREFIX_STYLE="custom"
else
    PREFIX_STYLE="conventional"
fi

# Description part of each prefixed branch = everything after the first separator.
DESCRIPTIONS=""
if [ "$PREFIX_STYLE" != "none" ]; then
    if [ "$SEPARATOR" = "/" ]; then
        DESCRIPTIONS=$(printf '%s\n' "$PREFIXED" | sed 's|^[^/]*/||')
    else
        DESCRIPTIONS=$(printf '%s\n' "$PREFIXED" | sed 's|^[^-]*-||')
    fi
else
    DESCRIPTIONS=$(printf '%s\n' "$BRANCHES" | grep -vx "$DEFAULT_BRANCH" || true)
fi

DASH_WORDS=$(printf '%s\n' "$DESCRIPTIONS" | grep -c -- '-' || true)
UNDERSCORE_WORDS=$(printf '%s\n' "$DESCRIPTIONS" | grep -c '_' || true)
if [ "$UNDERSCORE_WORDS" -gt "$DASH_WORDS" ]; then
    WORD_SEPARATOR="_"
else
    WORD_SEPARATOR="-"
fi

# Ticket keys: learned only from >=2 branches, so one JIRA-tagged branch in an otherwise
# untagged repo does not force every future branch to carry a ticket id.
TICKET_AFTER=$(printf '%s\n' "$DESCRIPTIONS" | grep -cE '^[A-Z][A-Z0-9]{1,9}-[0-9]+' || true)
TICKET_LEADING=$(printf '%s\n' "$BRANCHES" | grep -cE '^[A-Z][A-Z0-9]{1,9}-[0-9]+' || true)
TICKET_PATTERN="null"
TICKET_POSITION="null"
if [ "$TICKET_AFTER" -ge 2 ]; then
    TICKET_PATTERN='"^[A-Z][A-Z0-9]{1,9}-[0-9]+$"'
    TICKET_POSITION='"after-prefix"'
elif [ "$TICKET_LEADING" -ge 2 ]; then
    TICKET_PATTERN='"^[A-Z][A-Z0-9]{1,9}-[0-9]+$"'
    TICKET_POSITION='"leading"'
fi

MAX_LENGTH=$(printf '%s\n' "$BRANCHES" | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')

# ---------------------------------------------------------------------------
# Model classification
# ---------------------------------------------------------------------------

SOURCES=""
add_source() {
    [ -n "$SOURCES" ] && SOURCES="${SOURCES},"
    SOURCES="${SOURCES}\"$(json_str "$1")\""
}

if [ -n "$DEVELOP_BRANCH" ] || [ "$GITFLOW_CONFIG_COUNT" -gt 0 ]; then
    MODEL="git-flow"
    [ -n "$DEVELOP_BRANCH" ] && add_source "topology:${DEVELOP_BRANCH}-branch"
    [ "$GITFLOW_CONFIG_COUNT" -gt 0 ] && add_source "config:gitflow.*"
    [ -n "$RELEASE_BRANCHES" ] && add_source "topology:release-branch"

    if [ "$GITFLOW_CONFIG_COUNT" -gt 0 ] && [ -n "$DEVELOP_BRANCH" ]; then
        CONFIDENCE="high"
    elif [ -n "$DEVELOP_BRANCH" ] && [ "$DISTINCT_PREFIXES" -ge 3 ]; then
        CONFIDENCE="high"
    else
        # gitflow config with no develop branch yet (freshly `git flow init`ed), or a
        # develop branch with too little prefix history to corroborate it.
        CONFIDENCE="medium"
    fi
else
    MODEL="github-flow"
    add_source "topology:no-develop-branch"
    [ "$PREFIX_STYLE" != "none" ] && add_source "topology:prefix-histogram"

    if [ "$BRANCH_COUNT" -ge 5 ]; then
        CONFIDENCE="high"
    elif [ "$BRANCH_COUNT" -ge 2 ]; then
        CONFIDENCE="medium"
    else
        CONFIDENCE="low"
    fi
fi

# ---------------------------------------------------------------------------
# Working-tree state (saves the caller two more git calls at the branch gate)
# ---------------------------------------------------------------------------

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
[ "$CURRENT_BRANCH" = "HEAD" ] && CURRENT_BRANCH=""

CURRENT_IS_BASE="false"
if [ -n "$CURRENT_BRANCH" ]; then
    case "$CURRENT_BRANCH" in
        "$DEFAULT_BRANCH"|main|master|trunk|develop|dev|development) CURRENT_IS_BASE="true" ;;
        release/*|releases/*)                                        CURRENT_IS_BASE="true" ;;
    esac
    [ -n "$DEVELOP_BRANCH" ] && [ "$CURRENT_BRANCH" = "$DEVELOP_BRANCH" ] && CURRENT_IS_BASE="true"
fi

DIRTY_COUNT=$(git status --porcelain 2>/dev/null | grep -c '[^[:space:]]' || true)

RELEASE_JSON=""
while IFS= read -r branch; do
    [ -z "$branch" ] && continue
    [ -n "$RELEASE_JSON" ] && RELEASE_JSON="${RELEASE_JSON},"
    RELEASE_JSON="${RELEASE_JSON}\"$(json_str "$branch")\""
done <<EOF
$RELEASE_BRANCHES
EOF

# ---------------------------------------------------------------------------
# Emit
# ---------------------------------------------------------------------------

develop_json="null"
[ -n "$DEVELOP_BRANCH" ] && develop_json="\"$(json_str "$DEVELOP_BRANCH")\""
current_json="null"
[ -n "$CURRENT_BRANCH" ] && current_json="\"$(json_str "$CURRENT_BRANCH")\""

cat <<JSON
{
  "schema_version": 1,
  "model": "${MODEL}",
  "confidence": "${CONFIDENCE}",
  "sources": [${SOURCES}],
  "default_branch": "$(json_str "$DEFAULT_BRANCH")",
  "develop_branch": ${develop_json},
  "release_branches": [${RELEASE_JSON}],
  "gitflow_config_keys": ${GITFLOW_CONFIG_COUNT},
  "prefix_style": "${PREFIX_STYLE}",
  "prefix_histogram": {${HISTOGRAM_JSON}},
  "naming": {
    "separator": "${SEPARATOR}",
    "word_separator": "${WORD_SEPARATOR}",
    "ticket_pattern": ${TICKET_PATTERN},
    "ticket_position": ${TICKET_POSITION},
    "observed_max_length": ${MAX_LENGTH}
  },
  "current_branch": ${current_json},
  "current_branch_is_base": ${CURRENT_IS_BASE},
  "dirty_file_count": ${DIRTY_COUNT},
  "branches_analyzed": ${BRANCH_COUNT},
  "git_flow_cli_available": ${GIT_FLOW_CLI_AVAILABLE},
  "git_flow_initialized": ${GIT_FLOW_INITIALIZED}
}
JSON
