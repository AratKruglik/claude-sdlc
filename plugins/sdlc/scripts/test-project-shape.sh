#!/usr/bin/env bash
# Fixture-based tests for the project_shape probe in detect-stack.sh (--shape-only and the
# key embedded in the full output). Every case builds a throwaway repo under a temp root.
#
# Run: bash plugins/sdlc/scripts/test-project-shape.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="${SCRIPT_DIR}/detect-stack.sh"
REAL_PLUGINS_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-shape-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

pass_count=0
fail_count=0

assert_field() {
    local case_name="$1" filter="$2" expected="$3" json="$4" actual
    actual=$(printf '%s' "$json" | jq -r "$filter" 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        pass_count=$((pass_count + 1)); printf 'PASS  %-64s %s = %s\n' "$case_name" "$filter" "$actual"
    else
        fail_count=$((fail_count + 1)); printf 'FAIL  %-64s %s: expected %q, got %q\n' "$case_name" "$filter" "$expected" "$actual"
    fi
}

shape() { bash "$DETECT" --repo "$1" --shape-only | jq -c '.project_shape'; }

# ── Case 1: Laravel + pnpm + vitest + docker compose ──
REPO="$TMP_ROOT/laravel-pnpm"; mkdir -p "$REPO/.github/workflows"
printf '{"require":{"laravel/framework":"^11"},"require-dev":{"pestphp/pest":"^3","laravel/pint":"^1"}}\n' > "$REPO/composer.json"
printf '{"devDependencies":{"vitest":"^2","@vitest/coverage-v8":"^2","prettier":"^3","eslint":"^9"},"scripts":{"test":"vitest run","lint":"eslint ."}}\n' > "$REPO/package.json"
touch "$REPO/pnpm-lock.yaml" "$REPO/artisan" "$REPO/tsconfig.json" "$REPO/phpstan.neon" "$REPO/.github/workflows/ci.yml"
printf 'services:\n  app:\n    image: php\n' > "$REPO/docker-compose.yml"
OUT=$(shape "$REPO")
assert_field "case1 package manager is pnpm (lockfile wins over composer)" '.package_manager' "pnpm" "$OUT"
assert_field "case1 runner prefix from compose service app" '.runner_prefix' "docker compose exec -T app" "$OUT"
assert_field "case1 test command from package.json script" '.test_command' "pnpm run test" "$OUT"
assert_field "case1 lint command from package.json script" '.lint_command' "pnpm run lint" "$OUT"
assert_field "case1 format command from prettier dev dep" '.format_command' "npx prettier --write ." "$OUT"
assert_field "case1 typecheck from tsconfig" '.typecheck_command' "npx tsc --noEmit" "$OUT"
assert_field "case1 framework vitest" '.test_framework' "vitest" "$OUT"
assert_field "case1 coverage available via @vitest/coverage-v8" '.coverage_available' "true" "$OUT"
assert_field "case1 ci github-actions" '.ci' "github-actions" "$OUT"
assert_field "case1 not a monorepo" '.monorepo' "false" "$OUT"

# ── Case 2: pure Laravel (composer only) ──
REPO="$TMP_ROOT/laravel-only"; mkdir -p "$REPO"
printf '{"require":{"laravel/framework":"^11"},"require-dev":{"pestphp/pest":"^3","laravel/pint":"^1"}}\n' > "$REPO/composer.json"
touch "$REPO/artisan" "$REPO/phpstan.neon.dist"
OUT=$(shape "$REPO")
assert_field "case2 package manager composer" '.package_manager' "composer" "$OUT"
assert_field "case2 artisan test" '.test_command' "php artisan test" "$OUT"
assert_field "case2 pint format" '.format_command' "./vendor/bin/pint" "$OUT"
assert_field "case2 phpstan typecheck" '.typecheck_command' "./vendor/bin/phpstan analyse --no-progress" "$OUT"
assert_field "case2 framework pest" '.test_framework' "pest" "$OUT"
assert_field "case2 empty runner prefix without compose" '.runner_prefix' "" "$OUT"

# ── Case 3: Python poetry + pytest + ruff ──
REPO="$TMP_ROOT/py-poetry"; mkdir -p "$REPO"
cat > "$REPO/pyproject.toml" <<'EOF'
[tool.poetry]
name = "demo"
[tool.poetry.group.dev.dependencies]
pytest = "^8"
pytest-cov = "^5"
[tool.ruff]
line-length = 100
[tool.mypy]
strict = true
EOF
touch "$REPO/poetry.lock" "$REPO/.gitlab-ci.yml"
OUT=$(shape "$REPO")
assert_field "case3 package manager poetry" '.package_manager' "poetry" "$OUT"
assert_field "case3 poetry run pytest" '.test_command' "poetry run pytest" "$OUT"
assert_field "case3 ruff lint" '.lint_command' "ruff check ." "$OUT"
assert_field "case3 ruff format" '.format_command' "ruff format ." "$OUT"
assert_field "case3 mypy typecheck" '.typecheck_command' "mypy ." "$OUT"
assert_field "case3 framework pytest" '.test_framework' "pytest" "$OUT"
assert_field "case3 coverage via pytest-cov" '.coverage_available' "true" "$OUT"
assert_field "case3 ci gitlab" '.ci' "gitlab-ci" "$OUT"

# ── Case 4: Maven with wrapper, Gradle, dotnet ──
REPO="$TMP_ROOT/maven"; mkdir -p "$REPO"
printf '<project><build><plugins><plugin><artifactId>spotless-maven-plugin</artifactId></plugin><plugin><artifactId>jacoco-maven-plugin</artifactId></plugin></plugins></build></project>\n' > "$REPO/pom.xml"
touch "$REPO/mvnw"
OUT=$(shape "$REPO")
assert_field "case4 maven" '.package_manager' "maven" "$OUT"
assert_field "case4 mvnw test" '.test_command' "./mvnw test" "$OUT"
assert_field "case4 spotless check" '.lint_command' "./mvnw -q spotless:check" "$OUT"
assert_field "case4 junit" '.test_framework' "junit" "$OUT"
assert_field "case4 jacoco coverage" '.coverage_available' "true" "$OUT"

REPO="$TMP_ROOT/gradle"; mkdir -p "$REPO"; touch "$REPO/build.gradle.kts"
OUT=$(shape "$REPO")
assert_field "case4 gradle without wrapper" '.test_command' "gradle test" "$OUT"

REPO="$TMP_ROOT/dotnet"; mkdir -p "$REPO"
printf '<Project><ItemGroup><PackageReference Include="xunit" /><PackageReference Include="coverlet.collector" /></ItemGroup></Project>\n' > "$REPO/Demo.csproj"
OUT=$(shape "$REPO")
assert_field "case4 dotnet" '.package_manager' "dotnet" "$OUT"
assert_field "case4 xunit" '.test_framework' "xunit" "$OUT"
assert_field "case4 dotnet test" '.test_command' "dotnet test" "$OUT"
assert_field "case4 coverlet" '.coverage_available' "true" "$OUT"

# ── Case 5: empty repo → nulls, never a crash ──
REPO="$TMP_ROOT/empty"; mkdir -p "$REPO"
OUT=$(shape "$REPO")
assert_field "case5 package manager null" '.package_manager' "null" "$OUT"
assert_field "case5 test command null" '.test_command' "null" "$OUT"
assert_field "case5 framework null" '.test_framework' "null" "$OUT"
assert_field "case5 ci none" '.ci' "none" "$OUT"
assert_field "case5 coverage false" '.coverage_available' "false" "$OUT"

# ── Case 6: monorepo + the key is present in the full output ──
REPO="$TMP_ROOT/mono"; mkdir -p "$REPO"
printf '{"workspaces":["packages/*"],"devDependencies":{"jest":"^29"}}\n' > "$REPO/package.json"
touch "$REPO/yarn.lock" "$REPO/turbo.json"
OUT=$(bash "$DETECT" --repo "$REPO" --plugins-root "$REAL_PLUGINS_ROOT")
assert_field "case6 full output carries project_shape" '.project_shape.package_manager' "yarn" "$OUT"
assert_field "case6 monorepo detected" '.project_shape.monorepo' "true" "$OUT"
assert_field "case6 jest fallback command" '.project_shape.test_command' "npx jest" "$OUT"
assert_field "case6 all_profiles present" '.all_profiles | length > 0' "true" "$OUT"
assert_field "case6 vanilla detect_summary" '.all_profiles[] | select(.stack == "vanilla") | .detect_summary' "always matches" "$OUT"
assert_field "case6 laravel unmatched_reason" '.all_profiles[] | select(.stack == "laravel") | .unmatched_reason' "composer.json not present" "$OUT"

echo
echo "=== ${pass_count} passed, ${fail_count} failed ==="
[ "$fail_count" -eq 0 ]
