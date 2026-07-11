#!/bin/sh
# deploy/verify.sh — post-install verification before reboot.

deploy_verify() {
    _target="${1:-$DEPLOY_TARGET}"
    _fail=0

    log_info "═══ POST-INSTALL VERIFICATION ═══"

    # 1. Root filesystem is mounted
    if mountpoint -q "$_target" 2>/dev/null; then
        log_info "PASS: target mounted at $_target"
    else
        log_error "FAIL: target not mounted at $_target"
        _fail=1
    fi

    # 2. Essential directories exist
    for _d in etc bin sbin usr var; do
        if [ -d "$_target/$_d" ]; then
            log_info "PASS: $_target/$_d exists"
        else
            log_error "FAIL: $_target/$_d missing"
            _fail=1
        fi
    done

    # 3. fstab exists
    if [ -f "$_target/etc/fstab" ]; then
        log_info "PASS: fstab present"
    else
        log_warn "WARN: no fstab — system may not mount correctly"
    fi

    # 4. Bootloader configuration
    if [ -f "$_target/boot/grub/grub.cfg" ] || [ -d "$_target/boot/loader" ]; then
        log_info "PASS: bootloader configuration found"
    else
        log_warn "WARN: no bootloader config detected in target"
    fi

    # 5. Kernel image
    _kern=$(ls "$_target"/boot/vmlinuz* "$_target"/boot/vmlinuz 2>/dev/null | head -1)
    if [ -n "$_kern" ]; then
        log_info "PASS: kernel image found: $(basename "$_kern")"
    else
        log_warn "WARN: no kernel image in $_target/boot/"
    fi

    [ "$_fail" -ne 0 ] && { log_error "Verification FAILED"; return 1; }
    log_info "Verification PASSED — safe to reboot"
    return 0
}
