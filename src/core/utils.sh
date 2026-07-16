#!/bin/sh
# utils.sh — portable helpers. All SYSROOT-aware for fixture testing.

OMNI_SYSROOT="${OMNI_SYSROOT:-}"

# Prefix a path with the (optional) sysroot for fixture-based testing.
_sysfile() { printf '%s' "${OMNI_SYSROOT}$1"; }
_have()    { [ -e "$(_sysfile "$1")" ]; }
_read()    { _f="$(_sysfile "$1")"; [ -r "$_f" ] && cat "$_f" 2>/dev/null; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }
is_root() { [ "$(id -u)" = "0" ]; }

# Detect if we are inside a chroot (best-effort, portable).
in_chroot() {
    [ -r /proc/1/root ] || return 1
    _r=$(readlink /proc/1/root 2>/dev/null || echo /)
    [ "$_r" != "/" ]
}

# Resolve a binary by marker path (sysroot-aware) OR live command -v.
# usage: resolve_bin <name> <candidate_path> [more_paths...]
resolve_bin() {
    _name="$1"; shift
    for _p in "$@"; do
        if _have "$_p"; then printf '%s' "$_p"; return 0; fi
    done
    if [ -z "$OMNI_SYSROOT" ] && command -v "$_name" >/dev/null 2>&1; then
        command -v "$_name"; return 0
    fi
    return 1
}

# Read a field from an os-release-style file: _osrel_field <file> <KEY>
_osrel_field() {
    [ -r "$1" ] || return 1
    grep -E "^$2=" "$1" 2>/dev/null | head -n 1 | cut -d= -f2- | sed 's/^"//; s/"$//'
}

# JSON string escaper — strips control chars, escapes backslash and double-quote.
_json_escape() { printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Emit one JSON key:value pair (string). usage: json_kv key value [trailing_comma]
json_kv() {
    _k="$1"; _v="$(_json_escape "$2")"; _sep="${3-,}"
    printf '  "%s": "%s"%s\n' "$_k" "$_v" "$_sep"
}
