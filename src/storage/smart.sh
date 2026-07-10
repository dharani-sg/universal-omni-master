#!/bin/sh
# storage/smart.sh — SMART/NVMe health and SATA CRC delta-watch.

# ---------- Baselines ----------

smart_read_baseline() {
    _dev="${1##*/}"

    if [ -n "${OMNI_CRC_BASELINE:-}" ]; then
        echo "$OMNI_CRC_BASELINE"
        return 0
    fi

    _state="$(_sysfile "/var/lib/omni-master/baseline.$_dev")"

    [ -r "$_state" ] || { echo 0; return 0; }

    # Supports old numeric baseline file and new KEY=VALUE file.
    if grep -q '=' "$_state" 2>/dev/null; then
        awk -F= '/^UDMA_CRC=/{print $2; found=1} END{if(!found) print 0}' "$_state"
    else
        cat "$_state"
    fi
}

smart_read_baseline_key() {
    _dev="${1##*/}"
    _key="$2"
    _state="$(_sysfile "/var/lib/omni-master/baseline.$_dev")"
    [ -r "$_state" ] || { echo 0; return 0; }

    if grep -q '=' "$_state" 2>/dev/null; then
        awk -F= -v k="$_key" '$1==k {print $2; found=1} END{if(!found) print 0}' "$_state"
    else
        # Legacy numeric file means SATA CRC baseline only.
        [ "$_key" = "UDMA_CRC" ] && cat "$_state" || echo 0
    fi
}

# ---------- SATA ----------

smart_sata_crc() {
    _dev="${1##*/}"

    if [ -n "${OMNI_SYSROOT:-}" ]; then
        _f="$(_sysfile "/omni_fixture_smart/$_dev.crc")"
        [ -r "$_f" ] && cat "$_f" || echo ""
        return 0
    fi

    command -v smartctl >/dev/null 2>&1 || { echo ""; return 1; }
    run_as_root smartctl -A "/dev/$_dev" 2>/dev/null |
        awk '/UDMA_CRC_Error_Count/{print $10; exit}'
}

smart_sata_health() {
    _dev="${1##*/}"
    _crc=$(smart_sata_crc "$_dev")
    [ -z "$_crc" ] && { echo unknown; return 1; }
    case "$_crc" in *[!0-9]*) echo unknown; return 1 ;; esac

    _base=$(smart_read_baseline "$_dev")
    case "$_base" in *[!0-9]*) _base=0 ;; esac

    [ "$_crc" -le "$_base" ] && echo ok || echo degraded
}

# ---------- NVMe ----------

_nvme_fixture_field() {
    _dev="${1##*/}"
    _field="$2"

    # Preferred: simple per-field fixture files.
    _f="$(_sysfile "/omni_fixture_smart/$_dev.$_field")"
    [ -r "$_f" ] && { cat "$_f"; return 0; }

    # Optional: raw smart-log fixture.
    _log="$(_sysfile "/omni_fixture_smart/$_dev.smartlog")"
    [ -r "$_log" ] || return 1

    awk -F: -v f="$_field" '
        tolower($1) ~ tolower(f) {
            gsub(/[, ]/, "", $2)
            print $2
            exit
        }
    ' "$_log"
}

smart_nvme_field() {
    _dev="${1##*/}"
    _field="$2"

    if [ -n "${OMNI_SYSROOT:-}" ]; then
        _nvme_fixture_field "$_dev" "$_field"
        return $?
    fi

    if command -v nvme >/dev/null 2>&1; then
        nvme smart-log "/dev/$_dev" 2>/dev/null |
            awk -F: -v f="$_field" '
                tolower($1) ~ tolower(f) {
                    gsub(/[, %]/, "", $2)
                    print $2
                    exit
                }'
        return 0
    fi

    command -v smartctl >/dev/null 2>&1 || return 1
    run_as_root smartctl -a "/dev/$_dev" 2>/dev/null |
        awk -F: -v f="$_field" '
            tolower($1) ~ tolower(f) {
                gsub(/[, %]/, "", $2)
                print $2
                exit
            }'
}

smart_nvme_media_errors() {
    smart_nvme_field "$1" "media_errors"
}

smart_nvme_critical_warning() {
    _v=$(smart_nvme_field "$1" "critical_warning")
    [ -n "$_v" ] || _v=$(smart_nvme_field "$1" "Critical Warning")
    [ -n "$_v" ] || _v=0
    echo "$_v"
}

_hex_to_dec() {
    _x="$1"
    _x=$(echo "$_x" | sed 's/^0x//; s/^0X//')
    printf '%d' "0x$_x" 2>/dev/null || echo 0
}

smart_nvme_health() {
    _dev="${1##*/}"

    _cw=$(smart_nvme_critical_warning "$_dev")
    _cw_dec=$(_hex_to_dec "$_cw")

    # Bit 5: read-only mode. Catastrophic no matter baseline.
    if [ $(( _cw_dec & 32 )) -ne 0 ]; then
        echo critical
        return 0
    fi

    _media=$(smart_nvme_media_errors "$_dev")
    [ -z "$_media" ] && _media=0
    case "$_media" in *[!0-9]*) _media=0 ;; esac

    _base_media=$(smart_read_baseline_key "$_dev" MEDIA_ERRORS)
    case "$_base_media" in *[!0-9]*) _base_media=0 ;; esac

    # Existing matrix expects "degraded" for nonzero media error delta.
    if [ "$_media" -gt "$_base_media" ]; then
        echo degraded
        return 0
    fi

    # Any other critical_warning bit is degraded unless it was already baseline.
    _base_cw=$(smart_read_baseline_key "$_dev" CRITICAL_WARNING_MASK)
    _base_cw_dec=$(_hex_to_dec "$_base_cw")
    _newbits=$(( _cw_dec & ~_base_cw_dec ))
    if [ "$_newbits" -ne 0 ]; then
        echo degraded
        return 0
    fi

    echo ok
}

# ---------- Universal dispatcher ----------

storage_health() {
    _dev="${1##*/}"
    _t=$(storage_device_type "$_dev")

    case "$_t" in
        nvme) smart_nvme_health "$_dev" ;;
        ssd|hdd|sata|emmc) smart_sata_health "$_dev" ;;
        *) echo unknown ;;
    esac
}

smart_set_baseline() {
    _storage_guard_mutation || return $?
    _dev="${1##*/}"

    _t=$(storage_device_type "$_dev")
    run_as_root mkdir -p /var/lib/omni-master

    if [ "$_t" = "nvme" ]; then
        {
            echo "CRITICAL_WARNING_MASK=$(smart_nvme_critical_warning "$_dev")"
            echo "MEDIA_ERRORS=$(smart_nvme_media_errors "$_dev")"
            echo "BASELINE_TIMESTAMP=$(date +%s)"
        } | run_as_root tee "/var/lib/omni-master/baseline.$_dev" >/dev/null
    else
        smart_sata_crc "$_dev" | run_as_root tee "/var/lib/omni-master/baseline.$_dev" >/dev/null
    fi

    log_info "baseline written for $_dev"
}
