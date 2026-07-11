#!/bin/sh
# src/deploy/snapshot_install.sh — M10-A: install omni-snapshot into target root.
# Wires hooks per package manager, installs config, and sets up /.snapshots subvol.

deploy_install_snapshot() {
    _target="${1:-$DEPLOY_TARGET}"
    _init="${2:-${DEPLOY_INIT:-openrc}}"
    _distro="${3:-${DEPLOY_DISTRO:-alpine}}"
    _src_root="${_OMNI_ROOT:?_OMNI_ROOT must be set}"

    log_info "snapshot: installing omni-snapshot into $_target (distro=$_distro)"

    # Binary + lib tree
    mkdir -p "$_target/usr/bin"
    mkdir -p "$_target/usr/lib/omni-master/src/snapshot"
    cp "$_src_root/bin/omni-snapshot" "$_target/usr/bin/omni-snapshot"
    chmod 755 "$_target/usr/bin/omni-snapshot"
    for _lib in common.sh prune.sh periodic.sh boot_entry.sh restore.sh; do
        [ -f "$_src_root/src/snapshot/$_lib" ] && \
            cp "$_src_root/src/snapshot/$_lib" "$_target/usr/lib/omni-master/src/snapshot/$_lib"
    done

    # Default config (non-destructive)
    if [ ! -f "$_target/etc/omni-snapshot.conf" ]; then
        cp "$_src_root/config/omni-snapshot.conf.example" "$_target/etc/omni-snapshot.conf"
        chmod 644 "$_target/etc/omni-snapshot.conf"
    fi

    # Create /.snapshots subvol and mount entry if Btrfs deploy
    # (R9 fix: must pre-exist or snapshot_create fails)
    if [ "${DEPLOY_FS:-btrfs}" = "btrfs" ]; then
        deploy_snapshot_create_subvol "$_target"
    fi

    # Package manager hooks
    deploy_snapshot_install_hooks "$_target" "$_distro"

    log_info "snapshot: install complete"
}

# Create the .snapshots Btrfs subvol inside the target (during deploy phase)
deploy_snapshot_create_subvol() {
    _target="${1:-$DEPLOY_TARGET}"
    _snap_subvol="${SNAPSHOT_MOUNT:-/.snapshots}"

    if [ ! -d "$_target/${_snap_subvol}" ]; then
        chroot_exec "$_target" btrfs subvolume create "$_snap_subvol" 2>/dev/null || \
            mkdir -p "$_target/${_snap_subvol}"
        log_info "snapshot: created Btrfs subvol $_snap_subvol"
    fi

    # Add fstab entry for /.snapshots subvol (idempotent)
    grep -q "$_snap_subvol" "$_target/etc/fstab" 2>/dev/null || {
        _root_uuid=$(blkid -s UUID -o value "${DEPLOY_ROOT_PART:-/dev/${DEPLOY_DISK:-sda}2}" 2>/dev/null || true)
        printf 'UUID=%s\t%s\tbtrfs\trw,noatime,subvol=@snapshots\t0\t0\n' \
            "$_root_uuid" "$_snap_subvol" >> "$_target/etc/fstab"
        log_info "snapshot: added $_snap_subvol fstab entry"
    }
}

# Install package manager hooks per distro
deploy_snapshot_install_hooks() {
    _target="${1:-$DEPLOY_TARGET}"
    _distro="${2:-alpine}"
    _assets="${_OMNI_ROOT:?}/src/snapshot/hooks"

    case "$_distro" in
        arch|artix)
            mkdir -p "$_target/etc/pacman.d/hooks"
            cp "$_assets/pacman.hook" "$_target/etc/pacman.d/hooks/00-omni-snapshot-pre.hook"
            log_info "snapshot: pacman hook installed"
            ;;
        debian|ubuntu)
            mkdir -p "$_target/etc/apt/apt.conf.d"
            cp "$_assets/apt.conf" "$_target/etc/apt/apt.conf.d/00omni-snapshot"
            log_info "snapshot: apt DPkg::Pre-Invoke hook installed"
            ;;
        alpine)
            mkdir -p "$_target/etc/apk/commit_hooks.d"
            cp "$_assets/apk-commit.sh" "$_target/etc/apk/commit_hooks.d/00-omni-snapshot"
            chmod +x "$_target/etc/apk/commit_hooks.d/00-omni-snapshot"
            log_info "snapshot: apk commit hook installed"
            ;;
        void)
            # Void: rename real xbps-install, install wrapper in /usr/local/bin
            # (R7 fix: wrapper only works if real binary is renamed)
            mkdir -p "$_target/usr/local/bin"
            cp "$_assets/xbps-wrapper.sh" "$_target/usr/local/bin/xbps-install"
            chmod 755 "$_target/usr/local/bin/xbps-install"
            # Rename real binary inside chroot if it exists
            if [ -x "$_target/usr/bin/xbps-install" ]; then
                cp "$_target/usr/bin/xbps-install" "$_target/usr/bin/xbps-install.real"
                chmod 755 "$_target/usr/bin/xbps-install.real"
                log_info "snapshot: xbps-install wrapper installed (real binary preserved as xbps-install.real)"
            else
                log_warn "snapshot: /usr/bin/xbps-install not found — xbps wrapper staged but may not activate"
            fi
            ;;
        *)
            log_warn "snapshot: unknown distro '$_distro' — no package manager hook installed"
            ;;
    esac
}

# Enable periodic snapshot via the target's init system
deploy_snapshot_enable_periodic() {
    _target="${1:-$DEPLOY_TARGET}"
    _init="${2:-${DEPLOY_INIT:-openrc}}"

    case "$_init" in
        systemd)
            cat > "$_target/usr/lib/systemd/system/omni-snapshot.timer" << 'TIMER'
[Unit]
Description=Omni-Snapshot periodic trigger
[Timer]
OnCalendar=hourly
Persistent=true
[Install]
WantedBy=timers.target
TIMER
            cat > "$_target/usr/lib/systemd/system/omni-snapshot.service" << 'SVC'
[Unit]
Description=Omni-Snapshot periodic run
[Service]
Type=oneshot
ExecStart=/usr/bin/omni-snapshot periodic
SVC
            mkdir -p "$_target/etc/systemd/system/timers.target.wants"
            ln -sf /usr/lib/systemd/system/omni-snapshot.timer \
                "$_target/etc/systemd/system/timers.target.wants/omni-snapshot.timer"
            log_info "snapshot: systemd timer enabled"
            ;;
        openrc)
            cat > "$_target/etc/periodic/hourly/omni-snapshot" << 'CRON'
#!/bin/sh
/usr/bin/omni-snapshot periodic
CRON
            chmod +x "$_target/etc/periodic/hourly/omni-snapshot"
            log_info "snapshot: OpenRC /etc/periodic/hourly entry created"
            ;;
        runit|s6|dinit)
            # Runit/s6/dinit: use crond from busybox or fcron
            mkdir -p "$_target/etc/cron.hourly"
            cat > "$_target/etc/cron.hourly/omni-snapshot" << 'CRON'
#!/bin/sh
/usr/bin/omni-snapshot periodic
CRON
            chmod +x "$_target/etc/cron.hourly/omni-snapshot"
            log_info "snapshot: /etc/cron.hourly entry created for $init"
            ;;
    esac
}
