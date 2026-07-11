#!/bin/sh
# deploy/chroot.sh — portable chroot with cross-libc ELF interpreter compatibility.
# Handles musl host → glibc target correctly (Alpine → Arch/Debian/Void-glibc).

# Mount virtual filesystems into target. Order matters: most specific last.
chroot_mount() {
    _target="${1:-$DEPLOY_TARGET}"

    for _d in proc sys dev dev/pts; do
        mkdir -p "$_target/$_d"
        mount --bind "/$_d" "$_target/$_d" || {
            log_error "failed to bind mount /$_d into $_target"
            return 1
        }
    done

    # /run: needed for elogind, dbus, pipewire socket paths
    mkdir -p "$_target/run"
    mount --bind /run "$_target/run" || log_warn "could not bind /run (non-fatal)"

    # sys must be slave so that hot-plug events don't propagate into chroot
    mount --make-rslave "$_target/sys" 2>/dev/null || true

    # UEFI: efivarfs required for grub-install/bootctl NVRAM writes.
    # Without this: "EFI variables are not supported on this system"
    if [ -d /sys/firmware/efi ]; then
        mkdir -p "$_target/sys/firmware/efi/efivars"
        mountpoint -q "$_target/sys/firmware/efi/efivars" 2>/dev/null || \
            mount -t efivarfs efivarfs "$_target/sys/firmware/efi/efivars" 2>/dev/null || \
            log_warn "could not mount efivarfs (NVRAM boot entries unavailable)"
    fi

    log_info "virtual filesystems mounted in $_target"
}

# Unmount in REVERSE order — deepest-nested FIRST to avoid EBUSY.
# efivars is nested under sys, so it must go before sys (research unmount hierarchy [1]).
chroot_unmount() {
    _target="${1:-$DEPLOY_TARGET}"

    umount -lf "$_target/sys/firmware/efi/efivars" 2>/dev/null || true
    for _d in run dev/pts dev proc sys; do
        umount -lf "$_target/$_d" 2>/dev/null || true
    done

    log_info "virtual filesystems unmounted from $_target"
}

# Propagate host DNS into target
chroot_copy_resolv() {
    _target="${1:-$DEPLOY_TARGET}"
    cp -L /etc/resolv.conf "$_target/etc/resolv.conf" 2>/dev/null || true
}

# ── Cross-libc ELF interpreter compatibility ──────────────────────────────────
# glibc binaries hardcode their interpreter in the ELF .interp section:
#   x86_64:  /lib64/ld-linux-x86-64.so.2
#   aarch64: /lib/ld-linux-aarch64.so.1
# On a musl host neither exists → kernel returns ENOENT ("No such file or
# directory") even though the binary itself exists. The link NAME must match
# the target arch's hardcoded .interp path exactly.
chroot_fix_elf_interp() {
    _target="${1:-$DEPLOY_TARGET}"

    # Only needed on musl hosts
    [ -f /lib/ld-musl-x86_64.so.1 ] || [ -f /lib/ld-musl-aarch64.so.1 ] || return 0

    case "$(uname -m)" in
        x86_64)
            _interp_src="$_target/lib/ld-linux-x86-64.so.2"
            _interp_dst="/lib64/ld-linux-x86-64.so.2"
            mkdir -p /lib64 2>/dev/null || true
            ;;
        aarch64)
            _interp_src="$_target/lib/ld-linux-aarch64.so.1"
            _interp_dst="/lib/ld-linux-aarch64.so.1"
            ;;
        *)
            log_warn "cross-libc interp fix: unsupported arch $(uname -m)"
            return 0
            ;;
    esac

    if [ -f "$_interp_src" ]; then
        ln -sf "$_interp_src" "$_interp_dst" 2>/dev/null || true
        log_info "ELF interpreter linked: $_interp_dst -> $_interp_src"
    else
        log_warn "glibc linker not found at $_interp_src — chroot may fail for glibc distros"
    fi
}

# Clean up ELF interp fix after deployment (idempotent: safe if never applied)
chroot_unfix_elf_interp() {
    rm -f /lib64/ld-linux-x86-64.so.2 2>/dev/null || true
    rm -f /lib/ld-linux-aarch64.so.1 2>/dev/null || true
    rmdir /lib64 2>/dev/null || true
}

# Run a command inside the target chroot
chroot_exec() {
    _target="${1:-$DEPLOY_TARGET}"; shift
    chroot "$_target" "$@"
}

# Run a here-document script inside the chroot (avoids path issues)
chroot_script() {
    _target="${1:-$DEPLOY_TARGET}"
    _name="$2"
    _body="$3"

    _script="$_target/tmp/omni-chroot-${_name}-$$.sh"
    printf '#!/bin/sh\nset -eu\n%s\n' "$_body" > "$_script"
    chmod +x "$_script"
    chroot_exec "$_target" "/tmp/omni-chroot-${_name}-$$.sh"
    rm -f "$_script"
}
