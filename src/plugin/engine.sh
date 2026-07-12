#!/bin/sh
# src/plugin/engine.sh — M13-C: directory-based plugin hooks.
# Layout: ${OMNI_PLUGIN_DIR:-/etc/omni-master/plugins.d}/<hook>/<NN-name>.sh
# Hooks:  pre_deploy post_deploy probe heal
# Only EXECUTABLE .sh files run (deliberate opt-in signal).
# Isolation: each plugin runs as ( . "$f" ) in a subshell — a failing or
# exiting plugin cannot clobber parent variables or abort the parent.
# NOTE: '. file args' is NOT POSIX; plugins instead inherit the hook's
# arguments as $1..$n because the subshell preserves positional params.

OMNI_PLUGIN_DIR="${OMNI_PLUGIN_DIR:-/etc/omni-master/plugins.d}"

_plugin_guard() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        printf 'plugin: REFUSING mutation hooks — OMNI_SYSROOT set\n' >&2
        return 126
    fi
    return 0
}

_plugin_valid_hook() {
    case "$1" in
        pre_deploy|post_deploy|probe|heal) return 0 ;;
        *) return 1 ;;
    esac
}

plugin_list() {
    _hook="$1"
    _plugin_valid_hook "$_hook" || return 2
    _dir="$OMNI_PLUGIN_DIR/$_hook"
    [ -d "$_dir" ] || return 0
    for _f in "$_dir"/*.sh; do
        [ -f "$_f" ] || continue
        printf '%s\n' "$_f"
    done | LC_ALL=C sort
}

plugin_run_hooks() {
    _hook="$1"; shift 2>/dev/null || true
    _plugin_valid_hook "$_hook" || {
        printf 'plugin: invalid hook: %s\n' "$_hook" >&2; return 2; }

    # Read-only hook (probe) skips the mutation guard
    if [ "$_hook" != "probe" ]; then
        _plugin_guard || return $?
    fi

    _dir="$OMNI_PLUGIN_DIR/$_hook"
    [ -d "$_dir" ] || return 0

    _fail=0
    for _f in "$_dir"/*.sh; do
        [ -f "$_f" ] || continue
        [ -x "$_f" ] || continue
        # Subshell isolation; sourced plugin sees hook args as $1..$n
        ( . "$_f" ) </dev/null || _fail=1
    done
    return "$_fail"
}

plugin_manifest_get() {
    _pdir="$1"
    _key="$2"
    _mfile="$_pdir/manifest.conf"
    [ -f "$_mfile" ] || return 1
    grep "^${_key}=" "$_mfile" | head -n 1 | cut -d= -f2-
}
