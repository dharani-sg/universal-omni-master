#!/bin/sh
# storage/cablewatch.sh — Resource governor modes based on storage health.
# Modes: normal | cable_watch | conservation | rescue
# CRITICAL: fsck is NEVER disabled in any mode — degraded storage makes
# integrity checks MORE important, not less. Only I/O intensity is reduced.

cablewatch_mode() {
    _dev="${1:-}"
    if [ -z "$_dev" ]; then
        # Auto-detect: check the device backing the root filesystem
        _root_dev=$(awk '$2=="/"{print $1; exit}' "$(_sysfile /proc/mounts)" 2>/dev/null)
        _dev=$(basename "${_root_dev:-}" | sed 's/[0-9]*$//')
    fi
    [ -z "$_dev" ] && { echo "normal"; return 0; }

    _health=$(storage_health "$_dev")
    case "$_health" in
        degraded) echo "cable_watch" ;;
        unknown)  echo "normal" ;;   # cannot assess -> do not restrict unnecessarily
        ok)       echo "normal" ;;
    esac
}

# Returns the recommended SMART/health poll interval in seconds for a mode.
cablewatch_poll_interval() {
    case "$1" in
        normal)       echo 60 ;;
        cable_watch)  echo 300 ;;
        conservation) echo 3600 ;;
        rescue)       echo 3600 ;;
        *)            echo 60 ;;
    esac
}

# Returns whether heavy I/O operations (deep scans, aggressive scrub) are permitted.
cablewatch_allow_heavy_io() {
    case "$1" in
        normal) return 0 ;;
        *)      return 1 ;;
    esac
}

# Explicit safety statement: fsck policy is NEVER touched by this module.
# This function exists so any caller/plugin that might be tempted to disable
# fsck has a documented, auditable single point to check against.
cablewatch_fsck_policy() {
    echo "never_disabled"
}
