#!/bin/sh
# diag/storage.sh — storage audit via omni-storage.

audit_storage() {
    audit_section "STORAGE"

    _list="$OMNI_AUDIT_TMP/storage-list"
    ./bin/omni-storage list > "$_list" 2>/dev/null || true

    if [ ! -s "$_list" ]; then
        audit_emit unknown storage "no block devices detected"
        return 0
    fi

    while IFS='|' read -r dev type; do
        [ -n "$dev" ] || continue

        health="$(./bin/omni-storage health "$dev" 2>/dev/null || echo unknown)"
        mode="$(./bin/omni-storage mode   "$dev" 2>/dev/null || echo normal)"
        fs="$(./bin/omni-storage fs-type "$dev" 2>/dev/null || echo unknown)"

        case "$health" in
            ok)
                audit_emit ok storage "$dev type=$type fs=$fs health=ok mode=$mode"
                ;;
            degraded)
                audit_emit warn storage "$dev type=$type fs=$fs health=degraded mode=$mode"
                ;;
            critical)
                audit_emit critical storage "$dev type=$type health=critical"
                ;;
            *)
                audit_emit unknown storage "$dev type=$type fs=$fs health=$health"
                ;;
        esac

        # CRC detail for SATA devices
        case "$type" in
            ssd|hdd|sata)
                crc="$(./bin/omni-storage crc "$dev" 2>/dev/null || true)"
                base="$(./bin/omni-storage baseline "$dev" 2>/dev/null || true)"
                [ -n "$crc" ] && audit_emit info storage "$dev UDMA_CRC=$crc baseline=${base:-0}"
                ;;
        esac

        # NVMe critical_warning detail
        case "$type" in
            nvme)
                cw_sev="$(./bin/omni-storage nvme-cw-sev "$dev" 2>/dev/null || true)"
                case "$cw_sev" in
                    critical) audit_emit critical storage "$dev NVMe critical_warning=critical" ;;
                    warn)     audit_emit warn    storage "$dev NVMe critical_warning=warn" ;;
                esac
                ;;
        esac
    done < "$_list"

    # fsck safety invariant
    fsck_policy="$(./bin/omni-storage fsck-policy 2>/dev/null || echo unknown)"
    if [ "$fsck_policy" = "never_disabled" ]; then
        audit_emit ok storage "fsck policy: never_disabled"
    else
        audit_emit critical storage "fsck policy violated: $fsck_policy"
    fi

    # --- Btrfs section: ONLY if root is actually Btrfs ---
    root_fs="$(./bin/omni-storage fs-type / 2>/dev/null || echo unknown)"
    audit_emit info storage "root filesystem: $root_fs"

    if [ "$root_fs" = "btrfs" ]; then
        free_bytes="$(./bin/omni-storage btrfs-free / 2>/dev/null || echo 0)"
        case "$free_bytes" in ''|*[!0-9]*) free_bytes=0 ;; esac

        if [ "$free_bytes" -gt 10737418240 ]; then
            audit_emit ok   storage "Btrfs unallocated headroom healthy: $free_bytes bytes"
        elif [ "$free_bytes" -gt 3221225472 ]; then
            audit_emit warn storage "Btrfs unallocated headroom low: $free_bytes bytes"
        elif [ "$free_bytes" -eq 0 ]; then
            audit_emit warn storage "Btrfs unallocated headroom could not be read"
        else
            audit_emit fail storage "Btrfs unallocated headroom critically low: $free_bytes bytes"
        fi

        # Btrfs device stats
        btrfs_health="$(./bin/omni-storage btrfs-device-health / 2>/dev/null || echo unknown)"
        case "$btrfs_health" in
            ok)       audit_emit ok       storage "Btrfs device stats clean" ;;
            fail)     audit_emit fail     storage "Btrfs device I/O errors present" ;;
            critical) audit_emit critical storage "Btrfs device corruption/generation errors" ;;
            *)        audit_emit unknown  storage "Btrfs device stats unknown" ;;
        esac

        # Scrub status
        scrub="$(./bin/omni-storage btrfs-scrub / 2>/dev/null || echo unknown)"
        case "$scrub" in
            ok)       audit_emit ok   storage "Btrfs last scrub: clean" ;;
            running)  audit_emit info storage "Btrfs scrub currently running" ;;
            errors)   audit_emit fail storage "Btrfs last scrub reported errors" ;;
            no_scrub) audit_emit info storage "Btrfs not yet scrubbed" ;;
            *)        audit_emit info storage "Btrfs scrub status unknown" ;;
        esac
    else
        audit_emit info storage "Btrfs checks skipped: root is $root_fs, not btrfs"
    fi
}
