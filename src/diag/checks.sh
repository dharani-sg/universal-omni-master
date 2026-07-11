#!/bin/sh
# diag/checks.sh — read-only system audit using existing omni modules.
# Requires: logging, utils, priv, detect, detect_hw, init interface,
#           boot interface, gpu interface, storage interface already loaded.

diag_check_platform() {
    _audit_section "PLATFORM"
    _d=$(detect_distro); _i=$(detect_init); _l=$(detect_libc)
    _p=$(detect_pkgmgr); _v=$(detect_priv); _b=$(detect_bootloader)
    _s=$(detect_seat_model); _a=$(detect_arch)
    _audit_info "distro=$_d  init=$_i  libc=$_l  arch=$_a"
    _audit_info "pkgmgr=$_p  priv=$_v  bootloader=$_b  seat=$_s"
    [ "$_d" = "unknown" ] && _audit_warn "distro detection failed"
    [ "$_i" = "unknown" ] && _audit_warn "init system unknown"
    [ "$_p" = "none" ] && _audit_warn "no package manager detected"
    [ "$_v" = "none" ] && _audit_warn "no privilege helper (sudo/doas)"
}

diag_check_hardware() {
    _audit_section "HARDWARE"
    _cv=$(detect_cpu_vendor); _cm=$(detect_cpu_model); _cc=$(detect_cpu_count)
    _audit_info "cpu: $_cv / $_cm (${_cc} logical)"
    _gv=$(detect_gpu_vendors 2>/dev/null || gpu_vendors 2>/dev/null)
    _gc=$(detect_gpu_count 2>/dev/null || gpu_count 2>/dev/null)
    _audit_info "gpu: count=${_gc:-?} vendors=${_gv:-?}"
    _st=$(detect_storage_types 2>/dev/null || storage_enumerate 2>/dev/null | tr '\n' ' ')
    _audit_info "storage: ${_st:-unknown}"
    _ps=$(detect_power_source 2>/dev/null)
    _audit_info "power: ${_ps:-unknown}"
}

diag_check_services() {
    _audit_section "SERVICES"
    # Critical services differ by distro; probe common names, skip not_found
    for _svc in networkmanager NetworkManager sshd ssh dbus elogind seatd \
                chronyd chrony smartd nopm-enforcer wifi-watchdog dgpu-manager; do
        _st=$(svc_status "$_svc" 2>/dev/null) || _st="not_found"
        case "$_st" in
            running)  _audit_ok "$_svc: running" ;;
            stopped)  _audit_info "$_svc: stopped" ;;
            failed)   _audit_crit "$_svc: failed" ;;
            not_found|not_supervised|unknown|"") : ;;  # skip absent
            *)        _audit_info "$_svc: $_st" ;;
        esac
    done
}

diag_check_boot() {
    _audit_section "BOOTLOADER"
    if command -v boot_detect >/dev/null 2>&1 || type boot_detect >/dev/null 2>&1; then
        _bd=$(boot_detect 2>/dev/null)
        _audit_info "detected: ${_bd:-unknown}"
        if type boot_get_default >/dev/null 2>&1; then
            _def=$(boot_get_default 2>/dev/null)
            [ -n "$_def" ] && _audit_info "default entry: $_def"
        fi
        if type boot_entry_count >/dev/null 2>&1; then
            _n=$(boot_entry_count 2>/dev/null)
            [ -n "$_n" ] && _audit_info "entries: $_n"
            [ "${_n:-0}" -eq 0 ] && [ "$_bd" != "unknown" ] && _audit_warn "bootloader present but zero entries parsed"
        fi
        if type boot_is_uefi >/dev/null 2>&1; then
            boot_is_uefi && _audit_info "firmware: UEFI" || _audit_info "firmware: legacy/unknown"
        fi
        if type boot_is_secureboot >/dev/null 2>&1; then
            if boot_is_secureboot; then
                _audit_info "Secure Boot: enabled (kernel signing is operator responsibility)"
            else
                _audit_info "Secure Boot: disabled or not reported"
            fi
        fi
    else
        _audit_warn "boot interface not loaded"
    fi
}

diag_check_gpu() {
    _audit_section "GPU"
    if ! type gpu_count >/dev/null 2>&1; then
        _audit_warn "gpu interface not loaded"
        return 0
    fi
    _audit_info "vendors=$(gpu_vendors) count=$(gpu_count) hybrid=$(gpu_hybrid)"
    _audit_info "intel=$(gpu_intel_status 2>/dev/null || echo n/a)"
    _audit_info "dgpu_vendor=${_OMNI_DGPU:-?} bdf=$(gpu_dgpu_bdf 2>/dev/null || echo none)"
    _audit_info "dgpu_driver=$(gpu_dgpu_driver) bound=$(gpu_dgpu_bound && echo yes || echo no) users=$(gpu_dgpu_users)"
    # Policy: on hybrid laptops, unbound dGPU at idle is OK (HP Pavilion model)
    if [ "$(gpu_hybrid)" = "yes" ] && gpu_dgpu_bound; then
        _u=$(gpu_dgpu_users)
        [ "${_u:-0}" -eq 0 ] && _audit_info "dGPU bound but idle (users=0)"
        [ "${_u:-0}" -gt 0 ] && _audit_info "dGPU in active use (users=$_u)"
    fi
}

diag_check_storage() {
    _audit_section "STORAGE"
    if ! type storage_enumerate >/dev/null 2>&1; then
        _audit_warn "storage interface not loaded"
        return 0
    fi

    storage_enumerate 2>/dev/null | while IFS='|' read -r _dev _type; do
        [ -n "$_dev" ] || continue
        _h=$(storage_health "$_dev" 2>/dev/null || echo unknown)
        _m=$(cablewatch_mode "$_dev" 2>/dev/null || echo normal)
        case "$_h" in
            ok)       _audit_ok "$_dev ($_type): health=ok mode=$_m" ;;
            degraded)
                if [ "$_m" = "cable_watch" ]; then
                    _audit_warn "$_dev ($_type): health=degraded mode=cable_watch (delta from baseline; fsck stays enabled)"
                else
                    _audit_warn "$_dev ($_type): health=degraded"
                fi
                ;;
            critical) _audit_crit "$_dev ($_type): health=critical" ;;
            *)        _audit_info "$_dev ($_type): health=$_h mode=$_m" ;;
        esac

        # SATA CRC detail when available
        if [ "$_type" = "ssd" ] || [ "$_type" = "hdd" ] || [ "$_type" = "sata" ]; then
            _crc=$(smart_sata_crc "$_dev" 2>/dev/null)
            _base=$(smart_read_baseline "$_dev" 2>/dev/null)
            [ -n "$_crc" ] && _audit_info "  $_dev CRC=$_crc baseline=${_base:-0}"
        fi
    done

    _fp=$(cablewatch_fsck_policy 2>/dev/null || echo unknown)
    [ "$_fp" = "never_disabled" ] && _audit_ok "fsck policy: never_disabled" || _audit_crit "fsck policy violated: $_fp"

    if type btrfs_is_root_btrfs >/dev/null 2>&1 && btrfs_is_root_btrfs 2>/dev/null; then
        _n=$(btrfs_subvolume_count / 2>/dev/null)
        _u=$(btrfs_unallocated_bytes / 2>/dev/null)
        _audit_info "btrfs root: subvols=${_n:-?} unallocated_bytes=${_u:-?}"
    fi
}

diag_check_session() {
    _audit_section "SESSION / RUNTIME"
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        _audit_info "fixture mode: session checks skipped"
        return 0
    fi
    [ -n "${XDG_RUNTIME_DIR:-}" ] && _audit_ok "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" || _audit_warn "XDG_RUNTIME_DIR unset"
    if command -v pgrep >/dev/null 2>&1; then
        pgrep -x niri >/dev/null 2>&1 && _audit_ok "niri running" || _audit_info "niri not running"
        pgrep -x noctalia >/dev/null 2>&1 && _audit_ok "noctalia running" || _audit_info "noctalia not running"
        pgrep -x pipewire >/dev/null 2>&1 && _audit_ok "pipewire running" || _audit_info "pipewire not running"
    fi
}

diag_run_all() {
    OMNI_AUDIT_SEVERITY=0
    printf 'Universal Omni-Master Audit\n'
    printf 'sysroot=%s severity_start=0\n' "${OMNI_SYSROOT:-/}"

    diag_check_platform
    diag_check_hardware
    diag_check_services
    diag_check_boot
    diag_check_gpu
    diag_check_storage
    diag_check_session

    _audit_section "SUMMARY"
    case "$OMNI_AUDIT_SEVERITY" in
        0) _audit_ok "overall: OK"; echo "exit_code=0" ;;
        1) _audit_warn "overall: WARNINGS present"; echo "exit_code=1" ;;
        2) _audit_crit "overall: CRITICAL issues present"; echo "exit_code=2" ;;
    esac
    return "$OMNI_AUDIT_SEVERITY"
}
