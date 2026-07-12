#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/omni-monolith.sh}"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TOOLS="omni-detect omni-service omni-boot omni-gpu omni-storage omni-audit omni-deploy omni-healer omni-snapshot omni-security omni-fleet omni-manifest"

_strip() {
    awk '
        NR==1 && /^#!/ {next}
        /\.[[:space:]]+.*OMNI_ROOT/ {next}
        /source[[:space:]]+.*OMNI_ROOT/ {next}
        /^[[:space:]]*set[[:space:]]+-[eu]/ {next}
        /^[[:space:]]*set[[:space:]]+-o[[:space:]]+(errexit|nounset)/ {next}
        {print}
    ' "$1"
}

{
    printf '#!/bin/sh\n'
    printf '# omni-monolith — generated %s\n' "$TS"
    printf '# Self-contained Universal Omni-Master. DO NOT EDIT.\n'
    printf 'set +eu 2>/dev/null || true\n'
    printf 'OMNI_MONOLITH=1\n'
    printf '_OMNI_ROOT=__MONOLITH_SELF_CONTAINED__\n'
    printf 'OMNI_ROOT="$_OMNI_ROOT"\n'
    printf 'export _OMNI_ROOT OMNI_ROOT OMNI_MONOLITH\n\n'

    # ARCHITECTURAL FIX: Wrap all library code in a function.
    # Library files contain top-level init code with "return 1" statements.
    # When sourced normally, "return" exits the sourced file harmlessly.
    # When concatenated into a monolith, "return" at top-level = "exit" in
    # POSIX sh (BusyBox ash). This kills the monolith before the dispatcher.
    # Wrapping in a function makes "return" exit the function, not the script.
    # POSIX sh function definitions are ALWAYS global, so all functions and
    # variables defined inside the wrapper are still available at top-level.
    printf '__omni_load_libs() {\n'
    { find "$ROOT/src/core" -name '*.sh' | sort; find "$ROOT/src" -name '*.sh' ! -path '*/core/*' ! -path '*/tui/*' | sort; } | while IFS= read -r f; do
        printf '# -- %s --\n' "${f#"$ROOT"/}"
        _strip "$f"
        printf '\n'
    done
    printf '}\n'
    printf '__omni_load_libs 2>/dev/null || true\n\n'

    printf '# ===== ENTRYPOINTS =====\n'
    for t in $TOOLS; do
        [ -f "$ROOT/bin/$t" ] || continue
        fn=$(printf '%s' "$t" | tr '-' '_')
        printf '__main_%s() {\n' "$fn"
        _strip "$ROOT/bin/$t"
        printf '\n}\n\n'
    done

    printf '# ===== DISPATCHER =====\n'
    cat << 'D'
_p=$(basename "$0" .sh)
case "$_p" in omni-detect)__main_omni_detect "$@";exit;;omni-service)__main_omni_service "$@";exit;;omni-boot)__main_omni_boot "$@";exit;;omni-gpu)__main_omni_gpu "$@";exit;;omni-storage)__main_omni_storage "$@";exit;;omni-audit)__main_omni_audit "$@";exit;;omni-deploy)__main_omni_deploy "$@";exit;;omni-healer)__main_omni_healer "$@";exit;;omni-snapshot)__main_omni_snapshot "$@";exit;;esac
_s="${1:-help}";[ $# -gt 0 ]&&shift
case "$_s" in detect)__main_omni_detect "$@";;service)__main_omni_service "$@";;boot)__main_omni_boot "$@";;gpu)__main_omni_gpu "$@";;storage)__main_omni_storage "$@";;audit)__main_omni_audit "$@";;deploy)__main_omni_deploy "$@";;healer)__main_omni_healer "$@";;snapshot)__main_omni_snapshot "$@";;help|--help|-h)printf 'omni-monolith: detect service boot gpu storage audit deploy healer snapshot\n';;*)printf 'unknown: %s\n' "$_s" >&2;exit 2;;esac
D
} > "$OUT"
chmod 755 "$OUT"
printf 'Built: %s (%s lines)\n' "$OUT" "$(wc -l < "$OUT")"
