#!/bin/sh
# deploy/chroot.sh — portable chroot mount/unmount for cross-libc safety.

chroot_mount() {
    _target="${1:-$DEPLOY_TARGET}"

    [ -d "$_target" ] || { log_error "chroot target does not exist: $_target"; return 1; }

    log_info "Mounting virtual filesystems for chroot..."
    mount --bind /dev     "$_target/dev"     2>/dev/null || true
    mount --bind /dev/pts "$_target/dev/pts" 2>/dev/null || true
    mount -t proc  proc  "$_target/proc"    2>/dev/null || true
    mount -t sysfs sysfs "$_target/sys"     2>/dev/null || true
    mount -t tmpfs tmpfs "$_target/run"     2>/dev/null || true

    # resolv.conf for DNS inside chroot
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf "$_target/etc/resolv.conf" 2>/dev/null || true
    fi

    log_info "Chroot mounts ready: $_target"
}

chroot_unmount() {
    _target="${1:-$DEPLOY_TARGET}"

    log_info "Unmounting chroot virtual filesystems..."
    umount "$_target/run"     2>/dev/null || true
    umount "$_target/sys"     2>/dev/null || true
    umount "$_target/proc"    2>/dev/null || true
    umount "$_target/dev/pts" 2>/dev/null || true
    umount "$_target/dev"     2>/dev/null || true

    log_info "Chroot unmounted: $_target"
}

# Execute a command inside the chroot
chroot_exec() {
    _target="${1:-$DEPLOY_TARGET}"
    shift
    chroot "$_target" /bin/sh -c "$*"
}
