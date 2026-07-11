#!/bin/sh
# healer/storage.sh — dmesg watcher for I/O + filesystem errors (M5 integration).

healer_storage_loop() {
    healer_emit "storage" "init" "storage monitor started"
    _last_snap=0
    dmesg -w 2>/dev/null | while read -r _line; do
        case "$_line" in
            *"I/O error"*|*"EXT4-fs error"*|*"BTRFS error"*|*"BTRFS critical"*|*"ata"*"SError"*)
                healer_emit "storage" "corruption_detected" "$_line"
                # Emergency read-only snapshot — rate-limited to 1 per 5 min
                _now=$(date +%s)
                if mount | grep -q "on / type btrfs" && [ $(( _now - _last_snap )) -ge 300 ]; then
                    btrfs subvolume snapshot -r / "/@backup_emergency_$_now" 2>/dev/null && \
                        healer_emit "storage" "snapshot_created" "emergency RO snapshot @backup_emergency_$_now"
                    _last_snap=$_now
                fi
                ;;
        esac
    done
    healer_emit "storage" "exit" "dmesg stream closed; storage monitor exiting"
}
