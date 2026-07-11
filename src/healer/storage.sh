#!/bin/sh
# healer/storage.sh — dmesg watcher for I/O + filesystem errors (M5 integration).
# BusyBox dmesg has no -w/--follow (util-linux-only feature) — falls back to
# poll-diff mode on musl/BusyBox hosts (Alpine primary target).

_dmesg_has_follow() {
    dmesg --help 2>&1 | grep -qE -- '(-w|--follow)'
}

_storage_check_line() {
    _line="$1"
    case "$_line" in
        *"I/O error"*|*"EXT4-fs error"*|*"BTRFS error"*|*"BTRFS critical"*|*"ata"*"SError"*)
            healer_emit "storage" "corruption_detected" "$_line"
            _now=$(date +%s)
            if mount | grep -q "on / type btrfs" && [ $(( _now - _last_snap )) -ge 300 ]; then
                btrfs subvolume snapshot -r / "/@backup_emergency_$_now" 2>/dev/null && \
                    healer_emit "storage" "snapshot_created" "emergency RO snapshot @backup_emergency_$_now"
                _last_snap=$_now
            fi
            ;;
    esac
}

healer_storage_loop() {
    healer_emit "storage" "init" "storage monitor started"
    _last_snap=0

    if _dmesg_has_follow; then
        # util-linux dmesg: true streaming follow mode
        dmesg -w 2>/dev/null | while read -r _line; do
            _storage_check_line "$_line"
        done
    else
        # BusyBox dmesg: no follow support — poll-diff the ring buffer instead
        healer_emit "storage" "fallback" "dmesg -w unsupported (BusyBox); using poll-diff mode"
        _prev_count=0
        _poll_interval="${HEALER_STORAGE_POLL_INTERVAL:-15}"
        while :; do
            _cur=$(dmesg 2>/dev/null)
            _cur_count=$(printf '%s\n' "$_cur" | wc -l)
            if [ "$_cur_count" -gt "$_prev_count" ]; then
                printf '%s\n' "$_cur" | tail -n "$(( _cur_count - _prev_count ))" | while read -r _line; do
                    _storage_check_line "$_line"
                done
                _prev_count="$_cur_count"
            fi
            sleep "$_poll_interval"
        done
    fi

    healer_emit "storage" "exit" "storage monitor exiting"
}
