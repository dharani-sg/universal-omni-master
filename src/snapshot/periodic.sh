#!/bin/sh
# src/snapshot/periodic.sh — Periodic snapshot trigger logic.
# Determines whether a new hourly/daily/weekly snapshot is due,
# based on the timestamp embedded in the most recent snapshot name.
# No cron/timer dependency: called from omni-snapshot periodic.

_period_seconds() {
    case "$1" in
        hourly)  printf '3600' ;;
        daily)   printf '86400' ;;
        weekly)  printf '604800' ;;
        *)       printf '3600' ;;
    esac
}

# Returns 0 if a new snapshot of this period is due, 1 if not yet.
_snap_period_due() {
    _period="$1"
    _interval=$(_period_seconds "$_period")
    _now=$(date +%s)

    # Find the most recent snapshot of this period
    _latest=$(snap_list_names | grep "@auto_.*_${_period}" | tail -1)

    if [ -z "$_latest" ]; then
        return 0   # no snapshot of this period exists — create one
    fi

    # Extract timestamp from name: @auto_YYYYMMDD-HHMMSS_period[_reason]
    _ts_str=$(printf '%s' "$_latest" | sed 's/^@auto_//;s/_.*//')
    # Parse YYYYMMDD-HHMMSS to epoch via date (portable POSIX)
    _year=${_ts_str%????-*}; _year=$(printf '%s' "$_ts_str" | cut -c1-4)
    _mon=$(printf '%s' "$_ts_str" | cut -c5-6)
    _day=$(printf '%s' "$_ts_str" | cut -c7-8)
    _hr=$(printf '%s' "$_ts_str" | cut -c10-11)
    _min=$(printf '%s' "$_ts_str" | cut -c12-13)
    _sec=$(printf '%s' "$_ts_str" | cut -c14-15)

    # Use date -d or date -j depending on host
    if date --version >/dev/null 2>&1; then
        _snap_epoch=$(date -d "${_year}-${_mon}-${_day}T${_hr}:${_min}:${_sec}" +%s 2>/dev/null || echo 0)
    else
        _snap_epoch=$(date -j -f '%Y%m%d-%H%M%S' "$_ts_str" +%s 2>/dev/null || echo 0)
    fi

    _elapsed=$(( _now - _snap_epoch ))
    [ "$_elapsed" -ge "$_interval" ]
}

# Run all due periodic snapshots
snap_run_periodic() {
    _snap_guard_mutation || return $?
    _snap_require_btrfs / || return 0
    _snap_check_free_space / || {
        snap_prune_emergency
        _snap_check_free_space / || return 1
    }

    for _period in hourly daily weekly; do
        if _snap_period_due "$_period"; then
            snap_create "$_period" ""
        fi
    done
}
