#!/usr/bin/env bash
# Materializes /sdlc:security-init: merges every active plugin's security-patterns.yaml into
# <repo>/.claude/security-patterns.yaml and every active stack's security-phase prompt
# injection into <repo>/.claude/claude-security-guidance.md, inside a managed block.
#
# Mirrors commands/security-init.md Steps 1–6. The YAML fragments are never parsed as YAML:
# each `- rule_name:` item is carried as an opaque text block, de-duplicated by rule_name
# (first occurrence wins, sdlc core merged first), so the output is byte-for-byte what the
# plugin authors wrote. Content outside the managed markers is never touched; a file that
# exists without markers is left alone with a warning.
#
# Usage: security-init.sh [--repo DIR] [--plugins-root DIR] [--dev-root DIR] [--dry-run]
#
#   --dry-run   Print what would be written, under a [DRY RUN] banner. Writes nothing.
#
# Exit codes: 0 always once arguments parse; 2 usage error; 3 jq missing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

repo="."
plugins_root="${HOME}/.claude/plugins/cache"
dev_root=""
dry_run=false

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)         repo="${2:-.}"; shift 2 ;;
        --plugins-root) plugins_root="${2:-}"; shift 2 ;;
        --dev-root)     dev_root="${2:-}"; shift 2 ;;
        --dry-run)      dry_run=true; shift ;;
        -h|--help)      sed -n '2,16p' "$0"; exit 0 ;;
        *)              echo "usage: security-init.sh [--repo DIR] [--plugins-root DIR] [--dev-root DIR] [--dry-run]" >&2; exit 2 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "security-init.sh: jq is required" >&2; exit 3; }

if [ -z "$(find "$plugins_root" -name stack.md -type f 2>/dev/null | head -1)" ] && [ -n "$dev_root" ]; then
    plugins_root="$dev_root"
fi

YAML_BEGIN='# >>> sdlc-marketplace managed (do not edit inside this block) >>>'
YAML_END='# <<< sdlc-marketplace managed <<<'
MD_BEGIN='<!-- >>> sdlc-marketplace managed (do not edit inside this block) >>> -->'
MD_END='<!-- <<< sdlc-marketplace managed <<< -->'
JS_STACKS=" nodejs nestjs nextjs react vue angular react-native inertia-vue inertia-react "

# Plugin directory name from a path under the plugins root: installed layout is
# {marketplace}/{plugin}/{version}/…, a dev checkout is plugins/{plugin}/….
plugin_name_of_dir() {
    local dir="$1" base
    base=$(basename "$dir")
    case "$base" in
        [0-9]*) basename "$(dirname "$dir")" ;;
        *) printf '%s' "$base" ;;
    esac
}

# $1 = plugin name → directory holding that plugin's files, newest version first
plugin_dir_of_name() {
    local name="$1" f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        f=$(dirname "$(dirname "$f")")
        [ "$(plugin_name_of_dir "$f")" = "$name" ] && { printf '%s' "$f"; return 0; }
    done < <(find "$plugins_root" -maxdepth 5 -path '*/.claude-plugin/plugin.json' 2>/dev/null | sort -r)
    return 1
}

detect=$(bash "${SCRIPT_DIR}/detect-stack.sh" --repo "$repo" --plugins-root "$plugins_root")

# Active plugin list, in merge order: sdlc core, js-foundation when a JS/TS stack matched,
# then every matched stack plugin by descending priority.
active=()
active+=("sdlc")
js_active=false
while IFS= read -r stack; do
    case "$JS_STACKS" in *" ${stack} "*) js_active=true ;; esac
done < <(jq -r '.matched_profiles[].stack' <<<"$detect")
[ "$js_active" = true ] && active+=("js-foundation")
while IFS= read -r src; do
    [ -n "$src" ] || continue
    name=$(plugin_name_of_dir "$(dirname "${plugins_root}/${src}")")
    [ "$name" = "sdlc" ] && continue
    active+=("$name")
done < <(jq -r '.matched_profiles | sort_by(-.priority, .stack)[] | .source' <<<"$detect")

join_csv() {
    local out="" item
    for item in "$@"; do [ -n "$item" ] && out="${out:+${out}, }${item}"; done
    printf '%s' "${out:-none}"
}

# ── patterns ────────────────────────────────────────────────────────────────────────────────
# Splits a security-patterns.yaml into one record per `- rule_name:` item: first line is the
# rule_name, the rest is the verbatim block. Records are separated by a \x1e line.
split_rules() {
    awk '
        /^patterns:[[:space:]]*$/ { inp = 1; next }
        !inp { next }
        /^[^[:space:]#]/ { inp = 0; next }
        /^[[:space:]]*-[[:space:]]+rule_name:/ {
            if (name != "") { printf "%s\n%s\n\036\n", name, block }
            name = $0; sub(/^[[:space:]]*-[[:space:]]+rule_name:[[:space:]]*/, "", name); gsub(/["\x27[:space:]]/, "", name)
            block = $0; next
        }
        name != "" && /^[[:space:]]*$/ { next }
        name != "" { block = block "\n" $0 }
        END { if (name != "") printf "%s\n%s\n\036\n", name, block }
    ' "$1"
}

seen_rules=" "
pattern_body=""
sources_used=()
declare -a rule_counts=()
for name in "${active[@]}"; do
    dir=$(plugin_dir_of_name "$name") || continue
    file="${dir}/security-patterns.yaml"
    [ -f "$file" ] || continue
    section=""
    count=0
    rule=""
    block=""
    while IFS= read -r line; do
        if [ "$line" = $'\x1e' ]; then
            case "$seen_rules" in
                *" ${rule} "*) ;;
                *) seen_rules="${seen_rules}${rule} "; section="${section}${block}"$'\n\n'; count=$((count + 1)) ;;
            esac
            rule=""; block=""
            continue
        fi
        if [ -z "$rule" ]; then rule="$line"; else block="${block:+${block}$'\n'}${line}"; fi
    done < <(split_rules "$file")
    [ "$count" -gt 0 ] || continue
    label="$name"; [ "$name" = "sdlc" ] && label="sdlc (core)"
    pattern_body="${pattern_body}  # --- ${label} ---"$'\n'"${section}"
    sources_used+=("$name")
    rule_counts+=("${label}|${count}")
done

sources_csv=$(join_csv "${sources_used[@]:-}")
total_rules=0
for rc in "${rule_counts[@]:-}"; do [ -n "$rc" ] && total_rules=$((total_rules + ${rc#*|})); done

yaml_block="${YAML_BEGIN}
# Generated by /sdlc:security-init. Re-run to regenerate. Sources: ${sources_csv}.
patterns:
$(printf '%s' "$pattern_body" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')
${YAML_END}"

# ── guidance ────────────────────────────────────────────────────────────────────────────────
# Pulls the security-phase injection out of a stack.md: the lines after "For security phase,
# inject:" up to the next heading or paragraph, with blockquote markers / indentation / the
# wrapping quotes removed. Both authoring styles in this marketplace are handled.
security_injection() {
    awk '
        /^For security phase, inject:/ { inb = 1; next }
        !inb { next }
        /^## / || /^For [a-z]+ phase/ { exit }
        /^[[:space:]]*$/ { if (seen) blank = 1; next }
        {
            line = $0
            if (line ~ /^>/) { sub(/^>[ ]?/, "", line) }
            else if (line ~ /^[[:space:]]/) { sub(/^[[:space:]]+/, "", line) }
            else if (seen && blank) { exit }
            if (blank && seen) print ""
            blank = 0; seen = 1
            print line
        }
    ' "$1" | sed -e '1s/^"//' -e '$s/"$//'
}

stack_title() {
    local title
    title=$(sed -nE 's/^# (.*) Stack Profile.*$/\1/p' "$1" | head -1)
    [ -n "$title" ] || title=$(sed -nE 's/^stack:[[:space:]]*([^[:space:]]+).*$/\1/p' "$1" | head -1)
    printf '%s' "$title"
}

guidance_body=""
guidance_sources=()
while IFS= read -r src; do
    [ -n "$src" ] || continue
    file="${plugins_root}/${src}"
    [ -f "$file" ] || continue
    name=$(plugin_name_of_dir "$(dirname "$file")")
    [ "$name" = "sdlc" ] && continue
    text=$(security_injection "$file")
    [ -n "$(printf '%s' "$text" | tr -d '[:space:]')" ] || continue
    guidance_body="${guidance_body}### $(stack_title "$file")"$'\n'"${text}"$'\n\n'
    guidance_sources+=("$name")
done < <(jq -r '.matched_profiles | sort_by(-.priority, .stack)[] | .source' <<<"$detect")

guidance_csv=$(join_csv "${guidance_sources[@]:-}")
md_block="${MD_BEGIN}
<!-- Generated by /sdlc:security-init. Sources: ${guidance_csv}. -->

## Stack-specific security guidance

$(printf '%s' "$guidance_body" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')
${MD_END}"

# ── managed-block writer ────────────────────────────────────────────────────────────────────
# $1 = target, $2 = begin marker, $3 = end marker, $4 = full block. Prints "created",
# "updated" or "skipped".
write_managed() {
    local target="$1" begin="$2" end="$3" block="$4" tmp
    if [ ! -f "$target" ]; then
        [ "$dry_run" = true ] || { mkdir -p "$(dirname "$target")"; printf '%s\n' "$block" > "$target"; }
        echo created; return
    fi
    if ! grep -qF -- "$begin" "$target" || ! grep -qF -- "$end" "$target"; then
        echo skipped; return
    fi
    if [ "$dry_run" = false ]; then
        tmp=$(mktemp "${TMPDIR:-/tmp}/sdlc-sec.XXXXXX")
        blockfile=$(mktemp "${TMPDIR:-/tmp}/sdlc-sec-block.XXXXXX")
        printf '%s\n' "$block" > "$blockfile"
        awk -v begin="$begin" -v end="$end" -v blockfile="$blockfile" '
            index($0, begin) == 1 { while ((getline l < blockfile) > 0) print l; skipping = 1; next }
            skipping && index($0, end) == 1 { skipping = 0; next }
            skipping { next }
            { print }
        ' "$target" > "$tmp" && mv "$tmp" "$target"
        rm -f "$blockfile"
    fi
    echo updated
}

yaml_target="${repo}/.claude/security-patterns.yaml"
md_target="${repo}/.claude/claude-security-guidance.md"

if [ "$dry_run" = true ]; then
    echo "[DRY RUN] would write ${yaml_target}:"
    printf '%s\n\n' "$yaml_block"
    echo "[DRY RUN] would write ${md_target}:"
    printf '%s\n\n' "$md_block"
fi

yaml_status=$(write_managed "$yaml_target" "$YAML_BEGIN" "$YAML_END" "$yaml_block")
md_status=$(write_managed "$md_target" "$MD_BEGIN" "$MD_END" "$md_block")

warn_skipped() {
    local target="$1"
    echo "⚠️ ${target#"${repo}"/} exists without sdlc-marketplace markers."
    echo "   Manual file detected — skipping to avoid clobbering your rules."
    echo "   To enable managed rules: add the managed block markers manually or delete the file and re-run."
    echo
}
[ "$yaml_status" = skipped ] && warn_skipped "$yaml_target"
[ "$md_status" = skipped ] && warn_skipped "$md_target"

sg_present=false
[ -n "$(find "$plugins_root" -path '*/security-guidance/*/.claude-plugin/plugin.json' -o -path '*/security-guidance/.claude-plugin/plugin.json' 2>/dev/null | head -1)" ] && sg_present=true

[ "$dry_run" = true ] && echo "[DRY RUN] nothing written."
echo "✅ /sdlc:security-init complete"
echo
echo "Files written:"
printf '  %-36s — %s rules (sources: %s)%s\n' ".claude/security-patterns.yaml" "$total_rules" "$sources_csv" "$([ "$yaml_status" = skipped ] && printf ' [skipped]')"
printf '  %-36s — %s stacks%s\n' ".claude/claude-security-guidance.md" "${#guidance_sources[@]}" "$([ "$md_status" = skipped ] && printf ' [skipped]')"
echo
echo "Rules by source:"
for rc in "${rule_counts[@]:-}"; do
    [ -n "$rc" ] || continue
    printf '  %-20s %s rules\n' "${rc%%|*}:" "${rc#*|}"
done
printf '  %-20s %s rules\n' "Total:" "$total_rules"
echo
if [ "$sg_present" = true ]; then
    echo "Security-guidance plugin: ✅ active"
else
    echo "Security-guidance plugin: ⚠️ not installed (see below)"
    echo
    echo "ℹ️  security-guidance plugin not detected. Install it to activate these rules:"
    echo "   /plugin install security-guidance@claude-plugins"
    echo "   /reload-plugins"
fi
echo
echo "Re-run /sdlc:security-init after:"
echo "  - Installing a new stack plugin"
echo "  - Upgrading the marketplace"
echo "  - Changing the project's detected stack"
exit 0
