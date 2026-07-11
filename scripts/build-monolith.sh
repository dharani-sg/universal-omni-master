#!/bin/sh
# scripts/build-monolith.sh — bundle all POSIX CLIs + libraries into one file.
# Output: a single #!/bin/sh executable containing the entire framework.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/omni-monolith.sh}"
STAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# POSIX CLIs to embed (fish TUI excluded — not single-file portable)
TOOLS="omni-detect omni-service omni-boot omni-gpu omni-storage
       omni-audit omni-deploy omni-healer omni-snapshot"

# Strip: shebang line, and any `. "$_OMNI_ROOT/..."`/`. "$OMNI_ROOT/..."` source lines,
# and the local _OMNI_ROOT assignment (everything is inlined already).
_strip() {
    sed -e '1{/^#!/d;}' \
        -e '/^[[:space:]]*\. "\$_OMNI_ROOT/d' \
        -e '/^[[:space:]]*\. "\$OMNI_ROOT/d' \
        -e '/^_OMNI_ROOT=/d' \
        -e '/^_OMNI_ROOT="/d' "$1"
}

{
    printf '#!/bin/sh\n'
    printf '# omni-monolith.sh — generated %s\n' "$STAMP"
    printf '# Self-contained Universal Omni-Master bundle. DO NOT EDIT.\n'
    printf '# Dispatch: symlink to a tool name, OR run: omni-monolith.sh <tool> [args]\n'
    printf 'set -u\n\n'

    # 1) Inline every library module (function definitions), load order: core first
    printf '# ===== LIBRARIES =====\n'
    {
        find "$ROOT/src/core" -name '*.sh' 2>/dev/null | sort
        find "$ROOT/src" -name '*.sh' ! -path '*/core/*' ! -path '*/tui/*' 2>/dev/null | sort
    } | while IFS= read -r _f
    do
        printf '# ---- %s ----\n' "${_f#"$ROOT"/}"
        _strip "$_f"
        printf '\n'
    done

    # 2) Inline each CLI as a dispatchable function __main_<tool>
    printf '# ===== CLI ENTRYPOINTS =====\n'
    for _t in $TOOLS; do
        [ -f "$ROOT/bin/$_t" ] || continue
        _fn=$(printf '%s' "$_t" | tr '-' '_')
        printf '__main_%s() {\n' "$_fn"
        _strip "$ROOT/bin/$_t"
        printf '\n}\n\n'
    done

    # 3) Multiplexer: pick tool by $0 basename, else by first arg
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

_sub="${1:-help}"; [ $# -gt 0 ] && shift
case "$_sub" in
    detect)   __main_omni_detect   "$@" ;;
    service)  __main_omni_service  "$@" ;;
    boot)     __main_omni_boot     "$@" ;;
    gpu)      __main_omni_gpu      "$@" ;;
    storage)  __main_omni_storage  "$@" ;;
    audit)    __main_omni_audit    "$@" ;;
    deploy)   __main_omni_deploy   "$@" ;;
    healer)   __main_omni_healer   "$@" ;;
    snapshot) __main_omni_snapshot "$@" ;;
    help|--help|-h)
        printf 'omni-monolith — Universal Omni-Master (bundled)\n'
        printf 'Usage: %s <tool> [args]\n' "$(basename "$0")"
        printf 'Tools: detect service boot gpu storage audit deploy healer snapshot\n'
        printf 'Or symlink this file to a tool name to invoke it directly.\n' ;;
    *) printf 'omni-monolith: unknown tool: %s\n' "$_sub" >&2; exit 2 ;;
esac
MUX
} > "$OUT"

chmod 755 "$OUT"
_lines=$(wc -l < "$OUT")
printf 'Monolith built: %s (%s lines)\n' "$OUT" "$_lines"
