#!/bin/sh
# storage/cablewatch.sh — Resource governor based on storage health.
# Modes: normal | cable_watch | conservation | rescue
#
# INVARIANT: fsck is NEVER disabled in any mode.
# Degraded storage makes integrity checks MORE important, not less.
# Only I/O intensity and polling frequency change.

cablewatch_mode() {
    _dev="${1:-}"
    if [ -z "$_dev" ]; then
        _rm="$(_sysfile /proc/mounts)"
        [ -r "$_rm" ] && \
            _root_dev=$(awk '$2=="/"{print $1; exit}' "$_rm" 2>/dev/null)
        _dev=$(basename "${_root_dev:-}" | sed 's/[0-9]*$//')
    fi
    [ -z "$_dev" ] && { echo normal; return 0; }

    _h=$(storage_health "$_dev" 2>/dev/null)
    case "$_h" in
        degraded) echo cable_watch ;;
        critical) echo rescue ;;
        *)        echo normal ;;
    esac
}

# Poll interval in seconds for each mode
cablewatch_poll_interval() {
    case "${1:-normal}" in
        normal)       echo 60 ;;
        cable_watch)  echo 300 ;;
        conservation) echo 3600 ;;
        rescue)       echo 3600 ;;
        *)            echo 60 ;;
    esac
}

# Whether heavy I/O (scrub, balance) is permitted in this mode
cablewatch_allow_heavy_io() {
    case "${1:-normal}" in
        normal) return 0 ;;
        cable_watch)
            # Allow scrub but throttled (rate-limited by caller)
            return 0 ;;
        *) return 1 ;;
    esac
}

# INVARIANT ASSERTION — fsck is never disabled (auditable single point)
cablewatch_fsck_policy() {
    echo "never_disabled"
}
