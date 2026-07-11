#!/bin/sh
# deploy/configure.sh — post-bootstrap system configuration.
# Init-specific service enabling uses the correct OFFLINE paths per init system.

deploy_set_hostname() {
    _hostname="${1:-omni-linux}"
    _target="${2:-$DEPLOY_TARGET}"

    printf '%s\n' "$_hostname" > "$_target/etc/hostname"

    # OpenRC also needs /etc/conf.d/hostname
    if [ -d "$_target/etc/conf.d" ]; then
        printf 'hostname="%s"\n' "$_hostname" > "$_target/etc/conf.d/hostname"
    fi

    # Update /etc/hosts
    grep -q "127.0.1.1" "$_target/etc/hosts" 2>/dev/null || \
        printf '127.0.1.1\t%s\n' "$_hostname" >> "$_target/etc/hosts"

    log_info "hostname set: $_hostname"
}

deploy_copy_resolv() {
    _target="${1:-$DEPLOY_TARGET}"
    cp -L /etc/resolv.conf "$_target/etc/resolv.conf" 2>/dev/null || true
}

deploy_set_locale() {
    _locale="${DEPLOY_LOCALE:-en_US.UTF-8}"
    _target="${1:-$DEPLOY_TARGET}"
    _init="${2:-openrc}"

    case "$_init" in
        openrc|runit|dinit|s6)
            # musl/POSIX: simple locale.conf
            printf 'LANG=%s\nLC_ALL=%s\n' "$_locale" "$_locale" > "$_target/etc/locale.conf"
            ;;
        systemd)
            chroot_exec "$_target" locale-gen "$_locale" 2>/dev/null || true
            printf 'LANG=%s\n' "$_locale" > "$_target/etc/locale.conf"
            ;;
    esac
}

deploy_create_user() {
    _user="${DEPLOY_USER:-}"
    _target="${1:-$DEPLOY_TARGET}"
    [ -z "$_user" ] && return 0

    if chroot_exec "$_target" command -v useradd >/dev/null 2>&1; then
        chroot_exec "$_target" useradd -m -s /bin/bash -G wheel,audio,video "$_user" 2>/dev/null || true
    else
        chroot_exec "$_target" adduser -D -s /bin/sh "$_user" 2>/dev/null || true
        chroot_exec "$_target" adduser "$_user" wheel 2>/dev/null || true
    fi

    # Add to seat group for Wayland (required by seatd on non-systemd)
    chroot_exec "$_target" adduser "$_user" seat 2>/dev/null || \
        chroot_exec "$_target" usermod -aG seat "$_user" 2>/dev/null || true

    log_info "user created: $_user"
}

# ── Init-specific service enabling ────────────────────────────────────────────
# CRITICAL: Each init system has a different OFFLINE enabling mechanism.
# /var/service/ only works on a LIVE runit system; offline installs must use
# /etc/runit/runsvdir/default/ instead.

deploy_enable_services() {
    _target="${1:-$DEPLOY_TARGET}"
    _init="${2:-openrc}"
    shift 2
    _services="$*"

    log_info "Enabling services via $_init: $_services"

    case "$_init" in
        systemd)
            # systemd: preset-all applies default enablement from unit presets.
            # This is the correct approach (not manually enabling each service).
            # Empty machine-id signals systemd to generate one on first boot.
            : > "$_target/etc/machine-id"
            chroot_exec "$_target" systemctl preset-all 2>/dev/null || true
            for svc in $_services; do
                chroot_exec "$_target" systemctl enable "$svc" 2>/dev/null || \
                    log_warn "could not enable $svc (may not be installed)"
            done
            ;;

        openrc)
            for svc in $_services; do
                chroot_exec "$_target" rc-update add "$svc" default 2>/dev/null || \
                    log_warn "could not enable $svc via rc-update"
            done
            ;;

        runit)
            # OFFLINE runit: symlinks must go into /etc/runit/runsvdir/default/
            # NOT /var/service/ — that path only works on a running runit system.
            _runit_default="$_target/etc/runit/runsvdir/default"
            mkdir -p "$_runit_default"
            for svc in $_services; do
                if [ -d "$_target/etc/sv/$svc" ]; then
                    ln -sf "/etc/sv/$svc" "$_runit_default/$svc"
                    log_info "runit: enabled $svc -> $svc in runsvdir/default"
                else
                    log_warn "runit: service dir /etc/sv/$svc not found"
                fi
            done
            ;;

        dinit)
            # OFFLINE dinit: use --offline flag or create boot.d symlinks manually.
            # dinitctl without --offline requires the daemon running (it's not during install).
            _dinit_boot="$_target/etc/dinit.d/boot.d"
            mkdir -p "$_dinit_boot"
            for svc in $_services; do
                if [ -f "$_target/etc/dinit.d/$svc" ]; then
                    ln -sf "../$svc" "$_dinit_boot/$svc"
                    log_info "dinit: enabled $svc in boot.d"
                else
                    # Try dinitctl --offline as second option
                    dinitctl --offline --services-dir="$_target/etc/dinit.d" \
                        enable "$svc" 2>/dev/null || \
                        log_warn "dinit: could not enable $svc"
                fi
            done
            ;;

        s6)
            _s6_bundle="$_target/etc/s6-rc/source/bundle/default/contents"
            [ -f "$_s6_bundle" ] && {
                for svc in $_services; do
                    printf '%s\n' "$svc" >> "$_s6_bundle"
                done
            } || log_warn "s6-rc bundle file not found; enable services manually"
            ;;
    esac
}

# ── D-Bus machine ID and seatd setup ─────────────────────────────────────────
# Required for Wayland + non-systemd deployments.
deploy_setup_dbus() {
    _target="${1:-$DEPLOY_TARGET}"

    if chroot_exec "$_target" command -v dbus-uuidgen >/dev/null 2>&1; then
        chroot_exec "$_target" dbus-uuidgen --ensure=/etc/machine-id
        mkdir -p "$_target/var/lib/dbus"
        ln -sf /etc/machine-id "$_target/var/lib/dbus/machine-id" 2>/dev/null || true
        log_info "D-Bus machine-id generated"
    else
        # Fallback: write a simple UUID via random
        printf '%s\n' "$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' || echo 00000000000000000000000000000000)" \
            > "$_target/etc/machine-id"
        log_warn "dbus-uuidgen not found; generated basic machine-id"
    fi
}

# ── Initramfs rebuild ─────────────────────────────────────────────────────────
# Without this, the kernel cannot find storage drivers or decrypt LUKS on boot.
deploy_rebuild_initramfs() {
    _target="${1:-$DEPLOY_TARGET}"
    _distro="${2:-${DEPLOY_DISTRO:-unknown}}"

    log_info "Rebuilding initramfs for $_distro ..."

    case "$_distro" in
        arch|artix)
            chroot_exec "$_target" mkinitcpio -P
            ;;
        debian|ubuntu)
            chroot_exec "$_target" update-initramfs -u -k all
            ;;
        void)
            chroot_exec "$_target" dracut --regenerate-all --force
            ;;
        alpine)
            # Alpine uses mkinitfs
            chroot_exec "$_target" mkinitfs 2>/dev/null || log_warn "mkinitfs not available"
            ;;
        *)
            log_warn "Unknown distro $_distro — initramfs rebuild skipped (manual step required)"
            ;;
    esac
}
