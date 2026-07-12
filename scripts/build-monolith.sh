#!/bin/sh
# scripts/build-monolith.sh — bundle POSIX CLIs + libraries into one file.
# Uses awk (deterministic, no BusyBox regex quirks). Explicit set +eu at top
# to prevent inherited strict mode from killing library loads.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/omni-monolith.sh}"
STAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

TOOLS="omni-detect omni-service omni-boot omni-gpu omni-storage
       omni-audit omni-deploy omni-healer omni-snapshot"

# _strip: awk-based — matches source calls ANYWHERE on line (not just line start)
# Handles: leading-space . source, mid-line "; . " chains, all quoting variants,
# set -e / -u / -eu / -ue / -o errexit / -o nounset patterns.
_strip() {
    awk '
        # Skip shebang
        NR == 1 && /^#!/ { next }

        # Skip source/dot-include lines — pattern: dot preceded by start-of-line
        # or whitespace, followed by whitespace and OMNI_ROOT reference.
        # Catches mid-line: "then . "$_OMNI_ROOT/..."" and "&& . "$OMNI_ROOT/...""
        /(^|[[:space:]])\.[[:space:]]+.*OMNI_ROOT/ { next }
        /(^|[[:space:]])\.[[:space:]]+.*omni-master/ { next }

        # Skip source command lines
        /^[[:space:]]*source[[:space:]]/ { next }
        /(^|[[:space:]]);[[:space:]]*source[[:space:]]/ { next }

        # Skip _OMNI_ROOT / OMNI_ROOT variable assignments (any indentation)
        /^[[:space:]]*_?OMNI_ROOT[[:space:]]*=/ { next }
        /^[[:space:]]*export[[:space:]]+_?OMNI_ROOT/ { next }

        # Skip ALL strict-mode variants to prevent monolith-wide crashes
        /^[[:space:]]*set[[:space:]]+-e[eu]?[[:space:]]*$/ { next }
        /^[[:space:]]*set[[:space:]]+-u[eu]?[[:space:]]*$/ { next }
        /^[[:space:]]*set[[:space:]]+-ue[[:space:]]*$/ { next }
        /^[[:space:]]*set[[:space:]]+-o[[:space:]]+errexit/ { next }
        /^[[:space:]]*set[[:space:]]+-o[[:space:]]+nounset/ { next }

        { print }
    ' "$1"
}

{
    printf '#!/bin/sh\n'
    printf '# omni-monolith.sh — generated %s\n' "$STAMP"
    printf '# Self-contained Universal Omni-Master bundle. DO NOT EDIT.\n'
    printf '# Dispatch: symlink to a tool name, OR run: omni-monolith.sh <tool> [args]\n'
    printf '\n'
    # CRITICAL: prevent inherited strict mode from crashing library init.
    # Libraries may reference unbound vars during load — that must not exit.
    printf 'set +eu\n'
    printf '\n'

    printf '# ===== LIBRARIES =====\n'
    {
        find "$ROOT/src/core" -name '*.sh' 2>/dev/null | sort
        find "$ROOT/src" -name '*.sh' ! -path '*/core/*' ! -path '*/tui/*' 2>/dev/null | sort
    } | while IFS= read -r _f; do
        printf '# ---- %s ----\n' "${_f#"$ROOT"/}"
        _strip "$_f"
        printf '\n'
    done

    printf '# ===== CLI ENTRYPOINTS =====\n'
    for _t in $TOOLS; do
        [ -f "$ROOT/bin/$_t" ] || continue
        _fn=$(printf '%s' "$_t" | tr '-' '_')
        printf '__main_%s() {\n' "$_fn"
        _strip "$ROOT/bin/$_t"
        printf '\n}\n\n'
    done

    printf '# ===== DISPATCHER =====\n'
    cat << 'MUX'
_prog=$(basename "$0" .sh)
case "$_prog" in
    omni-detect)   __main_omni_detect   "$@"; exit $? ;;
    omni-service)  __main_omni_service  "$@"; exit $? ;;
    omni-boot)     __main_omni_boot     "$@"; exit $? ;;
    omni-gpu)      __main_omni_gpu      "$@"; exit $? ;;
    omni-storage)  __main_omni_storage  "$@"; exit $? ;;
    omni-audit)    __main_omni_audit    "$@"; exit $? ;;
    omni-deploy)   __main_omni_deploy   "$@"; exit $? ;;
    omni-healer)   __main_omni_healer   "$@"; exit $? ;;
    omni-snapshot) __main_omni_snapshot "$@"; exit $? ;;
esac

_sub="${1:-help}"
if [ $# -gt 0 ]; then shift; fi

case "$_sub" in
    detect)   __main_omni_detect   "$@"; exit $? ;;
    service)  __main_omni_service  "$@"; exit $? ;;
    boot)     __main_omni_boot     "$@"; exit $? ;;
    gpu)      __main_omni_gpu      "$@"; exit $? ;;
    storage)  __main_omni_storage  "$@"; exit $? ;;
    audit)    __main_omni_audit    "$@"; exit $? ;;
    deploy)   __main_omni_deploy   "$@"; exit $? ;;
    healer)   __main_omni_healer   "$@"; exit $? ;;
    snapshot) __main_omni_snapshot "$@"; exit $? ;;
    help|--help|-h)
        printf 'omni-monolith — Universal Omni-Master (bundled)\n'
        printf 'Usage: %s <tool> [args]\n' "$(basename "$0")"
        printf 'Tools: detect service boot gpu storage audit deploy healer snapshot\n'
        printf 'Or symlink this file to a tool name.\n'
        exit 0
        ;;
    *)
        printf 'omni-monolith: unknown tool: %s\n' "$_sub" >&2
        exit 2
        ;;
esac
MUX
} > "$OUT"

chmod 755 "$OUT"
_lines=$(wc -l < "$OUT")
printf 'Monolith built: %s (%s lines)\n' "$OUT" "$_lines"
