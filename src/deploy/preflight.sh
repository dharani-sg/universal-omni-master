#!/bin/sh
# deploy/preflight.sh — comprehensive pre-installation checks.

preflight_check() {
    log_info "═══ PREFLIGHT CHECK ═══"

    deploy_require_root || return 1
    deploy_guard        || return $?

    _fail=0

    # 1. Architecture
    _arch=$(detect_arch)
    log_info "Architecture: $_arch"
    case "$_arch" in
        x86_64|aarch64|riscv64) : ;;
        *) log_warn "untested architecture: $_arch" ;;
    esac

    # 2. UEFI vs Legacy
    if [ -d /sys/firmware/efi ]; then
        log_info "Firmware: UEFI"
        _firmware=uefi
    else
        log_info "Firmware: Legacy BIOS"
        _firmware=bios
    fi

    # 3. Target device exists
    _tgt_dev="${DEPLOY_DISK:-}"
    if [ -n "$_tgt_dev" ] && [ -b "/dev/$_tgt_dev" ]; then
        log_info "Target disk: /dev/$_tgt_dev"
        _tgt_type=$(storage_device_type "$_tgt_dev")
        log_info "Disk type: $_tgt_type"

        # SATA cable health
        if [ "$_tgt_type" = "ssd" ] || [ "$_tgt_type" = "hdd" ] || [ "$_tgt_type" = "sata" ]; then
            _crc=$(smart_sata_crc "$_tgt_dev" 2>/dev/null || echo "")
            if [ -n "$_crc" ]; then
                _base=$(smart_read_baseline "$_tgt_dev" 2>/dev/null || echo 0)
                if [ "$_crc" -gt "$_base" ] 2>/dev/null; then
                    log_warn "SATA CRC delta: $_crc > baseline $_base (cable degraded)"
                    log_warn "Installing on a degraded SATA link is risky"
                else
                    log_info "SATA CRC: $_crc (at or below baseline $_base)"
                fi
            fi
        fi
    else
        [ -n "$_tgt_dev" ] && log_error "target disk /dev/$_tgt_dev not found" && _fail=1
    fi

    # 4. Required tools check
    for _tool in awk sed grep mount umount mkfs.ext4; do
        command -v "$_tool" >/dev/null 2>&1 \
            || { log_error "missing required tool: $_tool"; _fail=1; }
    done

    # 5. RAM check (minimum 1 GB for installation)
    _ram_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
    _ram_mb=$(( _ram_kb / 1024 ))
    log_info "RAM: ${_ram_mb} MB"
    [ "$_ram_mb" -lt 1024 ] && { log_warn "less than 1 GB RAM — installation may be slow"; }
    [ "$_ram_mb" -lt 512 ]  && { log_error "less than 512 MB RAM — insufficient"; _fail=1; }

    # 6. GPU topology (for post-install policy planning)
    _gpu_hybrid=$(gpu_hybrid 2>/dev/null || echo no)
    [ "$_gpu_hybrid" = "yes" ] && log_info "GPU: hybrid detected — dGPU deferral will be configured"

    # 7. Network connectivity (needed for package downloads)
    if command -v getent >/dev/null 2>&1; then
        if getent hosts voidlinux.org >/dev/null 2>&1; then
            log_info "Network: connected (DNS resolves)"
        else
            log_warn "Network: DNS resolution failed — packages may not download"
        fi
    fi

    [ "$_fail" -ne 0 ] && { log_error "Preflight FAILED"; return 1; }
    log_info "Preflight PASSED"
    printf 'firmware=%s\n' "$_firmware"
    return 0
}
