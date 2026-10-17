#!/usr/bin/env bash
# Run a stack tool the way this project can actually run it — locally, or inside the running
# Docker Compose service that has it — or skip silently when neither applies.
#
#   run-tool.sh --lang <php|node|python|java|dotnet|any> [--service-hint NAME] [--quiet] [--probe]
#               -- <command> [args…]
#
#   --lang          Which language marker must exist in the project for the tool to apply
#                   (composer.json, package.json, pyproject.toml/requirements*.txt, pom.xml/
#                   build.gradle*, *.sln/*.csproj). Not applicable → exit 0, nothing run.
#   --service-hint  Preferred compose service when falling back to Docker (default: the first
#                   of app, php, web, api, backend, node, frontend, python, worker found).
#   --quiet         Discard the tool's output and always exit 0 (PostToolUse formatters).
#   --probe         Print the resolution as JSON instead of running:
#                   {"lang","applicable","mode":"local|docker|none","service","reason"}
#
# Resolution order and caching are documented in _runner-lib.sh. The project root is
# $CLAUDE_PROJECT_DIR when set, else the current directory. Without --quiet the tool's exit
# code is propagated; a resolution to "none" always exits 0.
set -uo pipefail

# shellcheck source=_runner-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_runner-lib.sh"

lang=""; hint=""; quiet=false; probe=false
while [ $# -gt 0 ]; do
    case "$1" in
        --lang)         lang="${2:-}"; shift 2 ;;
        --service-hint) hint="${2:-}"; shift 2 ;;
        --quiet)        quiet=true; shift ;;
        --probe)        probe=true; shift ;;
        --)             shift; break ;;
        *)              break ;;
    esac
done

[ -n "$lang" ] && [ $# -gt 0 ] || exit 0

root=$(runner_project_root)
applicable=false
runner_applicable "$lang" "$root" && applicable=true

runner_resolve "$lang" "$root" "$hint" "$@"
resolved=$?

if [ "$probe" = true ]; then
    runner_probe_json "$lang" "$applicable"
    exit 0
fi

[ "$resolved" -eq 0 ] || exit 0

if [ "$quiet" = true ]; then
    runner_exec "$root" "$@" >/dev/null 2>&1
    exit 0
fi
runner_exec "$root" "$@"
