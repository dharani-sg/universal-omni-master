#!/bin/sh
# storage/smart.sh — SMART health: SATA multi-attribute delta + NVMe bitmask model.
#
# DESIGN PRINCIPLES:
#   SATA: Baseline-relative for CRC(199)/Realloc(5)/ReallocEvent(196).
#         Zero-tolerance for Uncorrectable(187)/PendingSector(197)/Offline(198).
#         A stable nonzero CRC baseline (e.g. 5360) is OK; only DELTA triggers warn.
#
#   NVMe: critical_warning is a STATE REGISTER bitmask, not a counter.
#         Bits 2,3,4,5 (0x04,0x08,0x10,0x20) = CRITICAL (immediate failure).
#         Bits 0,1 (0x01,0x02) = WARN (threshold crossed, not yet failed).
#         media_errors and unsafe_shutdowns are COUNTERS tracked via baseline delta.

# ── Hex conversion (BusyBox ash safe: no printf %d 0x...) ─────────────────────

_hex_to_dec() {
    _x=$(printf '%s' "${1:-0}" | sed 's/^0[xX]//' | tr 'a-f' 'A-F')
    _dec=0
    while [ -n "$_x" ]; do
        _c="${_x%${_x#?}}"
        _x="${_x#?}"
        case "$_c" in
            0) _v=0 ;; 1) _v=1 ;; 2) _v=2 ;; 3) _v=3 ;; 4) _v=4 ;;
            5) _v=5 ;; 6) _v=6 ;; 7) _v=7 ;; 8) _v=8 ;; 9) _v=9 ;;
            A) _v=10 ;; B) _v=11 ;; C) _v=12 ;; D) _v=13 ;;
            E) _v=14 ;; F) _v=15 ;; *) _v=0 ;;
        esac
        _dec=$(( _dec * 16 + _v ))
    done
    echo "$_dec"
}

# ── Baseline read/write ───────────────────────────────────────────────────────

# Read a baseline value (numeric or KEY=VALUE format).
# Priority: OMNI_CRC_BASELINE env > state file > 0
smart_read_baseline() {
    _dev="${1##*/}"
    if [ -n "${OMNI_CRC_BASELINE:-}" ]; then
        echo "$OMNI_CRC_BASELINE"; return 0
    fi
    _sf="$(_sysfile "/var/lib/omni-master/baseline.$_dev")"
    [ -r "$_sf" ] || { echo 0; return 0; }
    # Support both legacy numeric format and KEY=VALUE format
    if grep -q '=' "$_sf" 2>/dev/null; then
        awk -F= '/^UDMA_CRC=/{print $2; found=1} END{if(!found) print 0}' "$_sf"
    else
        cat "$_sf"
    fi
}

# Read a specific KEY from a KEY=VALUE baseline file
smart_read_baseline_key() {
    _dev="${1##*/}"; _key="$2"
    _sf="$(_sysfile "/var/lib/omni-master/baseline.$_dev")"
    [ -r "$_sf" ] || { echo 0; return 0; }
    if grep -q '=' "$_sf" 2>/dev/null; then
        awk -F= -v k="$_key" '$1==k{print $2; found=1} END{if(!found) print 0}' "$_sf"
    else
        # Legacy numeric file — only UDMA_CRC makes sense
        [ "$_key" = "UDMA_CRC" ] && cat "$_sf" || echo 0
    fi
}

smart_set_baseline() {
    _storage_guard_mutation || return $?
    _dev="${1##*/}"
    _t=$(storage_device_type "$_dev")
    run_as_root mkdir -p /var/lib/omni-master

    if [ "$_t" = "nvme" ]; then
        # Write KEY=VALUE format for NVMe
        {
            printf 'CRITICAL_WARNING_MASK=%s\n' "$(smart_nvme_critical_warning "$_dev")"
            printf 'MEDIA_ERRORS=%s\n'          "$(smart_nvme_media_errors "$_dev")"
            printf 'UNSAFE_SHUTDOWNS=%s\n'      "$(smart_nvme_field "$_dev" unsafe_shutdowns)"
            printf 'BASELINE_TIMESTAMP=%s\n'    "$(date +%s 2>/dev/null || echo 0)"
        } | run_as_root tee "/var/lib/omni-master/baseline.$_dev" >/dev/null
    else
        # Write legacy numeric for SATA (CRC is primary baseline)
        smart_sata_crc "$_dev" | run_as_root tee "/var/lib/omni-master/baseline.$_dev" >/dev/null
    fi
    log_info "baseline written for $_dev"
}

# ── SATA attribute extraction ─────────────────────────────────────────────────

# Read a single SATA attribute fixture file (format: sda.attr<ID>)
_sata_attr_fixture() {
    _dev="${1##*/}"; _id="$2"
    _f="$(_sysfile "/omni_fixture_smart/${_dev}.attr${_id}")"
    [ -r "$_f" ] && cat "$_f" || echo ""
}

# Read SATA UDMA_CRC_Error_Count (ID 199) — the cable-watch counter.
smart_sata_crc() {
    _dev="${1##*/}"
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        # Try both .crc (legacy) and .attr199 fixture names
        _f="$(_sysfile "/omni_fixture_smart/${_dev}.crc")"
        [ -r "$_f" ] && { cat "$_f"; return 0; }
        _sata_attr_fixture "$_dev" 199
        return 0
    fi
    command -v smartctl >/dev/null 2>&1 || { echo ""; return 1; }
    run_as_root smartctl -A "/dev/$_dev" 2>/dev/null |
        awk '$1==199 {print $10; exit}'
}

# Read a single SATA attribute RAW_VALUE by ID.
_sata_attr_live() {
    _dev="${1##*/}"; _id="$2"
    run_as_root smartctl -A "/dev/$_dev" 2>/dev/null |
        awk -v id="$_id" '$1==id {print $10; exit}'
}

smart_sata_attr() {
    _dev="${1##*/}"; _id="$2"
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        _sata_attr_fixture "$_dev" "$_id"
        return 0
    fi
    command -v smartctl >/dev/null 2>&1 || { echo ""; return 1; }
    _sata_attr_live "$_dev" "$_id"
}

# SATA health: baseline-relative + zero-tolerance classification.
smart_sata_health() {
    _dev="${1##*/}"

    # ── CRC baseline check (ID 199) ──
    _crc=$(smart_sata_crc "$_dev")
    [ -z "$_crc" ] && { echo unknown; return 1; }
    case "$_crc" in *[!0-9]*) echo unknown; return 1 ;; esac

    _base=$(smart_read_baseline "$_dev")
    case "$_base" in *[!0-9]*) _base=0 ;; esac

    if [ "$_crc" -gt "$_base" ]; then
        echo degraded; return 0
    fi

    # ── Zero-tolerance attributes ──
    # ID 187: Reported_Uncorrectable_Errors — ANY nonzero = degraded
    _v=$(smart_sata_attr "$_dev" 187)
    if [ -n "$_v" ]; then
        case "$_v" in *[!0-9]*) : ;; *)
            [ "$_v" -gt 0 ] && { echo degraded; return 0; } ;;
        esac
    fi

    # ID 197: Current_Pending_Sector_Count — ANY nonzero = degraded
    _v=$(smart_sata_attr "$_dev" 197)
    if [ -n "$_v" ]; then
        case "$_v" in *[!0-9]*) : ;; *)
            [ "$_v" -gt 0 ] && { echo degraded; return 0; } ;;
        esac
    fi

    # ID 198: Offline_Uncorrectable — ANY nonzero = degraded
    _v=$(smart_sata_attr "$_dev" 198)
    if [ -n "$_v" ]; then
        case "$_v" in *[!0-9]*) : ;; *)
            [ "$_v" -gt 0 ] && { echo degraded; return 0; } ;;
        esac
    fi

    echo ok
}

# ── NVMe field extraction ─────────────────────────────────────────────────────

# Read an NVMe field from fixture file (e.g. nvme0n1.media_errors) or live nvme/smartctl.
smart_nvme_field() {
    _dev="${1##*/}"; _field="$2"

    if [ -n "${OMNI_SYSROOT:-}" ]; then
        # Try short name first, then a unified smartlog fixture
        _f="$(_sysfile "/omni_fixture_smart/${_dev}.${_field}")"
        [ -r "$_f" ] && { cat "$_f"; return 0; }
        _log="$(_sysfile "/omni_fixture_smart/${_dev}.smartlog")"
        if [ -r "$_log" ]; then
            awk -F: -v f="$_field" 'tolower($1) ~ tolower(f) {
                gsub(/[, %]/, "", $2); print $2; exit}' "$_log"
        fi
        return 0
    fi

    # Live: try nvme-cli first, fall back to smartctl
    if command -v nvme >/dev/null 2>&1; then
        nvme smart-log "/dev/$_dev" 2>/dev/null |
            awk -F: -v f="$_field" 'tolower($1) ~ tolower(f) {
                gsub(/[, %x]/, "", $2); print $2; exit}'
        return 0
    fi
    if command -v smartctl >/dev/null 2>&1; then
        run_as_root smartctl -a "/dev/$_dev" 2>/dev/null |
            awk -F: -v f="$_field" 'tolower($1) ~ tolower(f) {
                gsub(/[, %]/, "", $2); print $2; exit}'
    fi
}

smart_nvme_media_errors()       { smart_nvme_field "$1" media_errors; }
smart_nvme_critical_warning()   {
    _v=$(smart_nvme_field "$1" critical_warning)
    [ -z "$_v" ] && _v=$(smart_nvme_field "$1" "Critical Warning")
    [ -n "$_v" ] && echo "$_v" || echo "0x00"
}

# Decode critical_warning bitmask — returns severity: ok | warn | critical
# Bits: 0x01=spare_low(W), 0x02=temp(W), 0x04=reliability(C),
#       0x08=read_only(C), 0x10=backup_fail(C), 0x20=persist_readonly(C)
smart_nvme_cw_severity() {
    _cw=$(smart_nvme_critical_warning "$1")
    _dec=$(_hex_to_dec "$_cw")

    # Critical bits: 0x04|0x08|0x10|0x20 = 60 decimal
    _crit_mask=60
    if [ $(( _dec & _crit_mask )) -ne 0 ]; then
        echo critical; return 0
    fi

    # Warning bits: 0x01|0x02 = 3 decimal
    _warn_mask=3
    if [ $(( _dec & _warn_mask )) -ne 0 ]; then
        echo warn; return 0
    fi

    echo ok
}

# Decode and explain each set bit in critical_warning
smart_nvme_cw_explain() {
    _cw=$(smart_nvme_critical_warning "$1")
    _dec=$(_hex_to_dec "$_cw")

    [ $(( _dec & 1  )) -ne 0 ] && echo "WARN:  bit0=0x01 available_spare below threshold"
    [ $(( _dec & 2  )) -ne 0 ] && echo "WARN:  bit1=0x02 temperature threshold exceeded"
    [ $(( _dec & 4  )) -ne 0 ] && echo "CRIT:  bit2=0x04 NVM reliability degraded (media/internal error)"
    [ $(( _dec & 8  )) -ne 0 ] && echo "CRIT:  bit3=0x08 media in read-only mode"
    [ $(( _dec & 16 )) -ne 0 ] && echo "CRIT:  bit4=0x10 volatile memory backup device failed"
    [ $(( _dec & 32 )) -ne 0 ] && echo "CRIT:  bit5=0x20 persistent memory region read-only/unreliable"
}

# NVMe health: combines critical_warning bitmask + media_errors delta.
smart_nvme_health() {
    _dev="${1##*/}"

    # Step 1: check critical_warning bitmask (state register — most authoritative)
    _cw_sev=$(smart_nvme_cw_severity "$_dev")
    [ "$_cw_sev" = "critical" ] && { echo critical; return 0; }

    # Step 2: check media_errors delta
    _media=$(smart_nvme_media_errors "$_dev")
    if [ -n "$_media" ]; then
        case "$_media" in *[!0-9]*) : ;; *)
            _base=$(smart_read_baseline_key "$_dev" MEDIA_ERRORS)
            case "$_base" in *[!0-9]*) _base=0 ;; esac
            [ "$_media" -gt "$_base" ] && { echo degraded; return 0; }
            ;;
        esac
    fi

    # Step 3: warning from critical_warning bits 0/1
    [ "$_cw_sev" = "warn" ] && { echo degraded; return 0; }

    # No data at all = unknown
    if [ -z "$_media" ]; then
        _cw=$(smart_nvme_critical_warning "$_dev")
        [ -z "$_cw" ] || [ "$_cw" = "0x00" ] && : || { echo unknown; return 1; }
    fi

    echo ok
}

# ── Universal dispatcher ──────────────────────────────────────────────────────

storage_health() {
    _dev="${1##*/}"
    _t=$(storage_device_type "$_dev")
    case "$_t" in
        nvme) smart_nvme_health "$_dev" ;;
        ssd|hdd|sata|emmc) smart_sata_health "$_dev" ;;
        *) echo unknown ;;
    esac
}
