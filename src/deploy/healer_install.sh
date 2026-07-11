#!/bin/sh
# src/deploy/healer_install.sh — M9: install + configure + enable omni-healer
# in the target root. Three separable phases:
#   1. deploy_install_healer_files  — copy binary tree + libs + default config
#   2. deploy_install_healer_service — write init-specific service unit
#   3. deploy_enable_healer          — link into runlevels/wants/service dir
#
# Compatible with all five M2 init systems: systemd, openrc, runit, dinit, s6.
# Does NOT override M7's deploy_enable_services in configure.sh — this module
# only adds omni-healer-specific installers; the orchestrator dispatches.

# ── Phase 1: files ────────────────────────────────────────────────────────────
deploy_install_healer_files() {
    _target="${1:-$DEPLOY_TARGET}"
    _src_root="${2:-${_OMNI_ROOT:-$(pwd)}}"

    log_info "healer: installing files into $_target"

    mkdir -p "$_target/usr/bin"
    mkdir -p "$_target/usr/lib/omni-master/bin"
    mkdir -p "$_target/usr/lib/omni-master/src/healer"
    mkdir -p "$_target/usr/lib/omni-master/src/core"
    mkdir -p "$_target/usr/lib/omni-master/src/gpu"
    mkdir -p "$_target/etc"
    mkdir -p "$_target/var/log/omni-healer"

    # Binary + relative-source layout (matches omni-healer's own dirname/..)
    cp "$_src_root/bin/omni-healer" "$_target/usr/lib/omni-master/bin/omni-healer"
    chmod 755 "$_target/usr/lib/omni-master/bin/omni-healer"

    # Healer modules
    for _lib in common.sh gpu.sh storage.sh services.sh; do
        if [ -f "$_src_root/src/healer/$_lib" ]; then
            cp "$_src_root/src/healer/$_lib" "$_target/usr/lib/omni-master/src/healer/$_lib"
            chmod 644 "$_target/usr/lib/omni-master/src/healer/$_lib"
        fi
    done

    # Runtime deps (A5 fix — reference omitted logging.sh which crashes the daemon)
    for _core in logging.sh utils.sh; do
        [ -f "$_src_root/src/core/$_core" ] && \
            cp "$_src_root/src/core/$_core" "$_target/usr/lib/omni-master/src/core/$_core"
    done
    [ -f "$_src_root/src/gpu/interface.sh" ] && \
        cp "$_src_root/src/gpu/interface.sh" "$_target/usr/lib/omni-master/src/gpu/interface.sh"

    # Public symlink
    ln -sf /usr/lib/omni-master/bin/omni-healer "$_target/usr/bin/omni-healer"

    # Default config — non-destructive
    if [ ! -f "$_target/etc/omni-healer.conf" ]; then
        cat > "$_target/etc/omni-healer.conf" << 'CONF'
# /etc/omni-healer.conf — omni-healer watchdog configuration
HEALER_STORAGE_MONITOR=1
HEALER_SERVICE_MONITOR=1
HEALER_GPU_RESTORE=1
HEALER_INTERVAL_BASE=5
HEALER_INTERVAL_MAX=60
# BF-01 + BF-02 baseline services (D-Bus machine ID + seatd for Wayland)
HEALER_WATCH_SERVICES="dbus seatd"
HEALER_STORAGE_POLL_INTERVAL=15
CONF
        chmod 644 "$_target/etc/omni-healer.conf"
    fi
}

# ── Phase 2: service unit ─────────────────────────────────────────────────────
deploy_install_healer_service() {
    _target="${1:-$DEPLOY_TARGET}"
    _init="${2:-${DEPLOY_INIT:-openrc}}"
    _assets="${_OMNI_ROOT:?_OMNI_ROOT must be set}/src/healer/init"

    log_info "healer: installing service unit for $_init"

    case "$_init" in
        systemd)
            mkdir -p "$_target/usr/lib/systemd/system"
            cp "$_assets/systemd.service" "$_target/usr/lib/systemd/system/omni-healer.service"
            chmod 644 "$_target/usr/lib/systemd/system/omni-healer.service"
            ;;
        openrc)
            mkdir -p "$_target/etc/init.d"
            cp "$_assets/openrc.initd" "$_target/etc/init.d/omni-healer"
            chmod 755 "$_target/etc/init.d/omni-healer"
            ;;
        runit)
            mkdir -p "$_target/etc/sv/omni-healer/log"
            cp "$_assets/runit.run" "$_target/etc/sv/omni-healer/run"
            cp "$_assets/runit.log.run" "$_target/etc/sv/omni-healer/log/run"
            chmod 755 "$_target/etc/sv/omni-healer/run"
            chmod 755 "$_target/etc/sv/omni-healer/log/run"
            ;;
        dinit)
            mkdir -p "$_target/etc/dinit.d"
            cp "$_assets/dinit.service" "$_target/etc/dinit.d/omni-healer"
            chmod 644 "$_target/etc/dinit.d/omni-healer"
            ;;
        s6)
            _s6dir="$_target/etc/s6-rc/source/omni-healer"
            mkdir -p "$_s6dir"
            printf 'longrun\n' > "$_s6dir/type"
            cp "$_assets/s6.run" "$_s6dir/run"
            chmod 755 "$_s6dir/run"
            ;;
        *)
            log_warn "healer: unsupported init '$_init' — service unit not installed"
            return 1
            ;;
    esac
}

# ── Phase 3: enable (create the runlevel/wants/service link) ─────────────────
# A3 fix: my previous version installed the unit but never enabled it, so the
# healer would never start at boot. This is the enablement step.
deploy_enable_healer() {
    _target="${1:-$DEPLOY_TARGET}"
    _init="${2:-${DEPLOY_INIT:-openrc}}"

    log_info "healer: enabling for $_init"

    case "$_init" in
        systemd)
            mkdir -p "$_target/etc/systemd/system/multi-user.target.wants"
            ln -sf /usr/lib/systemd/system/omni-healer.service \
                "$_target/etc/systemd/system/multi-user.target.wants/omni-healer.service"
            ;;
        openrc)
            mkdir -p "$_target/etc/runlevels/default"
            ln -sf /etc/init.d/omni-healer \
                "$_target/etc/runlevels/default/omni-healer"
            ;;
        runit)
            # OFFLINE: /etc/runit/runsvdir/default/ (not /var/service/ — that's
            # a live-only symlink). Matches configure.sh runit convention.
            mkdir -p "$_target/etc/runit/runsvdir/default"
            ln -sf /etc/sv/omni-healer \
                "$_target/etc/runit/runsvdir/default/omni-healer"
            ;;
        dinit)
            mkdir -p "$_target/etc/dinit.d/boot.d"
            ln -sf ../omni-healer \
                "$_target/etc/dinit.d/boot.d/omni-healer"
            ;;
        s6)
            # A9: modern s6-rc uses contents.d/<name> touch file instead of
            # the legacy monolithic 'contents' file.
            mkdir -p "$_target/etc/s6-rc/source/default/contents.d"
            : > "$_target/etc/s6-rc/source/default/contents.d/omni-healer"
            ;;
        *)
            log_warn "healer: cannot enable — unsupported init '$_init'"
            return 1
            ;;
    esac
}

# Convenience: full install+enable in one call (used by bin/omni-deploy)
deploy_install_healer() {
    _target="${1:-$DEPLOY_TARGET}"
    _init="${2:-${DEPLOY_INIT:-openrc}}"
    _src_root="${_OMNI_ROOT:-$(pwd)}"

    deploy_install_healer_files   "$_target" "$_src_root" || return 1
    deploy_install_healer_service "$_target" "$_init"     || return 1
    deploy_enable_healer          "$_target" "$_init"     || return 1
    log_info "healer: fully installed and enabled for $_init"
}
