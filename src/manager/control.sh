#!/bin/sh
# src/manager/control.sh — M21: Central Control Manager.
# NO eval. POSIX only. BusyBox ash-safe.

manager_inventory_clis() {
    _root="${OMNI_ROOT:-.}"
    for _f in "$_root"/bin/omni-*; do
        [ -f "$_f" ] && [ -x "$_f" ] && basename "$_f"
    done | sort
}

manager_inventory_tests() {
    _root="${OMNI_ROOT:-.}"
    for _f in "$_root"/scripts/test-*.sh; do
        [ -f "$_f" ] && basename "$_f"
    done | sort
}

manager_monolith_tools() {
    _root="${OMNI_ROOT:-.}"
    _builder="$_root/scripts/build-monolith.sh"
    [ -f "$_builder" ] || { printf 'manager: build-monolith.sh missing\n' >&2; return 1; }
    sed -n 's/^TOOLS="\(.*\)"/\1/p' "$_builder" | tr ' ' '\n' | sort
}

manager_sync_check() {
    _root="${OMNI_ROOT:-.}"
    _exit=0
    _tools=$(manager_monolith_tools)
    manager_inventory_clis | while IFS= read -r _cli; do
        case "$_cli" in omni-tui|omni-manager) continue ;; esac
        if ! printf '%s\n' "$_tools" | grep -qx "$_cli"; then
            printf 'DESYNC: %s missing from TOOLS\n' "$_cli" >&2
            _exit=1
        fi
    done
    return "$_exit"
}

manager_snapshot_meta() {
    _snap="/tmp/omni-manager-meta-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$_snap"
    _root="${OMNI_ROOT:-.}"
    cp "$_root/scripts/build-monolith.sh" "$_snap/" 2>/dev/null || true
    cp "$_root/scripts/test-m13-monolith.sh" "$_snap/" 2>/dev/null || true
    cp "$_root/docs/AI-HANDOFF.md" "$_snap/" 2>/dev/null || true
    cp "$_root/README.md" "$_snap/" 2>/dev/null || true
    printf 'manager: snapshot saved to %s\n' "$_snap" >&2
    printf '%s\n' "$_snap"
}

manager_add_tool() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        printf 'manager: REFUSING — OMNI_SYSROOT set\n' >&2
        return 126
    fi
    _name="${1:?manager_add_tool: tool name required}"
    _root="${OMNI_ROOT:-.}"
    _builder="$_root/scripts/build-monolith.sh"
    _test_mon="$_root/scripts/test-m13-monolith.sh"
    manager_snapshot_meta >/dev/null 2>&1
    if manager_monolith_tools | grep -qx "$_name"; then
        printf 'manager: %s already in TOOLS\n' "$_name"
        return 0
    fi
    cp "$_builder" "$_builder.bak"
    sed "s/^TOOLS=\"\(.*\)\"/TOOLS=\"\1 ${_name}\"/" "$_builder.bak" > "$_builder"
    if [ -f "$_test_mon" ]; then
        _old=$(sed -n 's/.*tools inlined" \([0-9][0-9]*\).*/\1/p' "$_test_mon" | head -1)
        if [ -n "$_old" ]; then
            _new=$((_old + 1))
            cp "$_test_mon" "$_test_mon.bak"
            sed "s/${_old} tools inlined/${_new} tools inlined/g" "$_test_mon.bak" > "$_test_mon"
            rm -f "$_test_mon.bak"
        fi
    fi
    sh -n "$_builder" || { cp "$_builder.bak" "$_builder"; return 1; }
    rm -f "$_builder.bak"
    printf 'manager: added %s\n' "$_name"
}

manager_remove_tool() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        printf 'manager: REFUSING — OMNI_SYSROOT set\n' >&2
        return 126
    fi
    _name="${1:?manager_remove_tool: tool name required}"
    _root="${OMNI_ROOT:-.}"
    _builder="$_root/scripts/build-monolith.sh"
    _test_mon="$_root/scripts/test-m13-monolith.sh"
    manager_snapshot_meta >/dev/null 2>&1
    if ! manager_monolith_tools | grep -qx "$_name"; then
        printf 'manager: %s not in TOOLS\n' "$_name"
        return 0
    fi
    cp "$_builder" "$_builder.bak"
    sed "s/ ${_name}//g" "$_builder.bak" > "$_builder"
    if [ -f "$_test_mon" ]; then
        _old=$(sed -n 's/.*tools inlined" \([0-9][0-9]*\).*/\1/p' "$_test_mon" | head -1)
        if [ -n "$_old" ] && [ "$_old" -gt 0 ]; then
            _new=$((_old - 1))
            cp "$_test_mon" "$_test_mon.bak"
            sed "s/${_old} tools inlined/${_new} tools inlined/g" "$_test_mon.bak" > "$_test_mon"
            rm -f "$_test_mon.bak"
        fi
    fi
    sh -n "$_builder" || { cp "$_builder.bak" "$_builder"; return 1; }
    rm -f "$_builder.bak"
    printf 'manager: removed %s\n' "$_name"
}
