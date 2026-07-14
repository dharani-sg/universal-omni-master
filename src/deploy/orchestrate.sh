#!/bin/sh
# M17.2: connect M16 state tracking to the real installer.
#
# Abrupt interruption:
#   phase remains "running" and can be resumed.
# Handled command failure:
#   phase becomes "failed"; existing rollback policy remains in effect.

deploy_state_prepare()
{
    _dp_resume="${DEPLOY_RESUME:-0}"
    _dp_fresh="${DEPLOY_FRESH:-0}"

    if [ "$_dp_resume" -eq 1 ] && [ "$_dp_fresh" -eq 1 ]; then
        printf 'deploy: --resume and --fresh are mutually exclusive\n' >&2
        return 2
    fi

    if deploy_state_is_resumable; then
        if [ "$_dp_fresh" -eq 1 ]; then
            deploy_state_clear || return $?
            deploy_state_init "$DEPLOY_DISTRO" "$DEPLOY_DISK" "$DEPLOY_FS"
            return $?
        fi

        if [ "$_dp_resume" -ne 1 ]; then
            deploy_state_summary >&2
            printf 'deploy: interrupted state exists; use --resume or --fresh\n' >&2
            return 3
        fi

        _dp_old_distro=$(deploy_state_get_meta distro)
        _dp_old_disk=$(deploy_state_get_meta disk)
        _dp_old_fs=$(deploy_state_get_meta fs)

        if [ "$_dp_old_distro" != "$DEPLOY_DISTRO" ] ||
           [ "$_dp_old_disk" != "$DEPLOY_DISK" ] ||
           [ "$_dp_old_fs" != "$DEPLOY_FS" ]; then
            printf 'deploy: resume profile does not match saved state\n' >&2
            return 3
        fi

        log_info "resuming deployment at: $(deploy_state_resume)"
        return 0
    fi

    deploy_state_init "$DEPLOY_DISTRO" "$DEPLOY_DISK" "$DEPLOY_FS"
}

deploy_phase_validate()
{
    _dp_phase="$1"

    case "$_dp_phase" in
        partitioning)
            [ -b "${DEPLOY_ROOT_PART:-/dev/${DEPLOY_DISK}2}" ]
            ;;
        mounting)
            awk -v m="$DEPLOY_TARGET" '$2 == m { found=1 } END { exit !found }' \
                /proc/mounts 2>/dev/null
            ;;
        bootstrap)
            [ -x "$DEPLOY_TARGET/bin/sh" ] &&
                [ -f "$DEPLOY_TARGET/etc/os-release" ]
            ;;
        chroot_setup)
            awk -v m="$DEPLOY_TARGET/proc" \
                '$2 == m { found=1 } END { exit !found }' /proc/mounts 2>/dev/null
            ;;
        configure)
            [ -s "$DEPLOY_TARGET/etc/hostname" ]
            ;;
        policies)
            return 0
            ;;
        initramfs)
            [ -d "$DEPLOY_TARGET/boot" ] &&
                find "$DEPLOY_TARGET/boot" -type f 2>/dev/null |
                grep -q '/init'
            ;;
        bootloader)
            [ -s "$DEPLOY_TARGET/boot/grub/grub.cfg" ] ||
                [ -d "$DEPLOY_TARGET/boot/loader/entries" ] ||
                [ -d "$DEPLOY_TARGET/boot/efi/loader/entries" ]
            ;;
        verify)
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

deploy_phase_run()
{
    _dp_phase="$1"
    _dp_handler="$2"
    _dp_status=$(deploy_state_get "$_dp_phase" 2>/dev/null || printf pending)

    if [ "$_dp_status" = "done" ] || [ "$_dp_status" = "skipped" ]; then
        if deploy_phase_validate "$_dp_phase"; then
            log_info "resume: skipping validated phase $_dp_phase"
            return 0
        fi

        log_warn "resume: phase $_dp_phase marked done but validation failed; repairing"
        deploy_state_set "$_dp_phase" pending || return $?
    fi

    deploy_state_set "$_dp_phase" running || return $?

    "$_dp_handler"
    _dp_rc=$?

    if [ "$_dp_rc" -eq 0 ]; then
        deploy_state_set "$_dp_phase" done || return $?
        return 0
    fi

    deploy_state_fail "$_dp_phase" "handler=${_dp_handler} rc=${_dp_rc}" || true
    return "$_dp_rc"
}

_deploy_phase_partitioning()
{
    _dp_backup_dir="${DEPLOY_STATE_DIR:-/var/lib/omni-master/deploy-state}"

    if [ ! -f "$_dp_backup_dir/${DEPLOY_DISK}.sfdisk" ]; then
        rollback_partition_backup "$DEPLOY_DISK" || return 1
    fi

    partition_format "$DEPLOY_DISK" "$DEPLOY_FS" || return 1

    if [ "$DEPLOY_FS" = "btrfs" ]; then
        partition_btrfs_subvols "$DEPLOY_DISK" || return 1
    fi
}

_deploy_phase_mounting()
{
    mkdir -p "$DEPLOY_TARGET" || return 1

    if ! awk -v m="$DEPLOY_TARGET" \
        '$2 == m { found=1 } END { exit !found }' /proc/mounts 2>/dev/null
    then
        mount "/dev/${DEPLOY_DISK}2" "$DEPLOY_TARGET" 2>/dev/null ||
            mount "/dev/$DEPLOY_DISK" "$DEPLOY_TARGET" ||
            return 1
    fi

    partition_generate_fstab "$DEPLOY_DISK" "$DEPLOY_FS"
}

_deploy_phase_bootstrap()
{
    bootstrap_install "$DEPLOY_DISTRO" "$DEPLOY_TARGET"
}

_deploy_phase_chroot_setup()
{
    chroot_unmount "$DEPLOY_TARGET" >/dev/null 2>&1 || true
    chroot_fix_elf_interp "$DEPLOY_TARGET" || return 1
    chroot_mount "$DEPLOY_TARGET" || return 1
    chroot_copy_resolv "$DEPLOY_TARGET"
}

_deploy_phase_configure()
{
    deploy_set_hostname "$DEPLOY_HOSTNAME" "$DEPLOY_TARGET" || return 1
    deploy_set_locale "$DEPLOY_TARGET" "$DEPLOY_INIT" || return 1

    if [ -n "$DEPLOY_USER" ]; then
        deploy_create_user "$DEPLOY_TARGET" || return 1
    fi

    if [ "$DEPLOY_INIT" != "systemd" ]; then
        deploy_setup_dbus "$DEPLOY_TARGET" || return 1
    fi

    deploy_install_healer "$DEPLOY_TARGET" "$DEPLOY_INIT" || return 1
    deploy_install_snapshot "$DEPLOY_TARGET" "$DEPLOY_INIT" "$DEPLOY_DISTRO" ||
        return 1
    deploy_snapshot_enable_periodic "$DEPLOY_TARGET" "$DEPLOY_INIT" || return 1
    deploy_enable_services "$DEPLOY_TARGET" "$DEPLOY_INIT" \
        NetworkManager dbus sshd
}

_deploy_phase_policies()
{
    deploy_install_gpu_policy 2>/dev/null || true
    deploy_install_nopm_policy 2>/dev/null || true
    deploy_install_dgpu_manager 2>/dev/null || true
    return 0
}

_deploy_phase_initramfs()
{
    deploy_rebuild_initramfs "$DEPLOY_TARGET" "$DEPLOY_DISTRO"
}

_deploy_phase_bootloader()
{
    deploy_install_bootloader
}

_deploy_phase_verify()
{
    chroot_unmount "$DEPLOY_TARGET"
    chroot_unfix_elf_interp
    deploy_verify "$DEPLOY_TARGET" || return 1

    # M18-B: durable checkpoint mirror — only after verified success.
    # A mirror failure aborts the phase: an unmirrorable target indicates
    # a filesystem too unhealthy to trust for crash-resume guarantees.
    deploy_checkpoint_mirror || return $?
}


_deploy_phase_desktop() {
    # M27-B: integrate omni-desktop. Opt-in via DEPLOY_DESKTOP.
    if [ -z "${DEPLOY_DESKTOP:-}" ]; then
        return 0
    fi

    if [ -z "${DEPLOY_DESKTOP_USER:-}" ]; then
        printf 'omni-deploy: --desktop requires --desktop-user\n' >&2
        return 2
    fi

    # Rule 4: never mutate under OMNI_SYSROOT.
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        case "${DEPLOY_TARGET:-}" in
            "${OMNI_SYSROOT}"|"${OMNI_SYSROOT}"/*)
                printf 'omni-deploy: refusing to mutate under OMNI_SYSROOT\n' >&2
                return 126
                ;;
        esac
    fi

    _dt="${OMNI_ROOT:-.}/bin/omni-desktop"

    if [ "${DEPLOY_ALLOW_EXPERIMENTAL_DESKTOP:-0}" = "1" ]; then
        "$_dt" install "$DEPLOY_DESKTOP" \
            --root "${DEPLOY_TARGET:-/mnt}" \
            --distro "${DEPLOY_DISTRO:-}" \
            --init "${DEPLOY_INIT:-}" \
            --user "$DEPLOY_DESKTOP_USER" \
            --login-manager "${DEPLOY_LOGIN_MANAGER:-auto}" \
            --allow-experimental \
            --apply
    else
        "$_dt" install "$DEPLOY_DESKTOP" \
            --root "${DEPLOY_TARGET:-/mnt}" \
            --distro "${DEPLOY_DISTRO:-}" \
            --init "${DEPLOY_INIT:-}" \
            --user "$DEPLOY_DESKTOP_USER" \
            --login-manager "${DEPLOY_LOGIN_MANAGER:-auto}" \
            --apply
    fi
}

deploy_install_execute()
{
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        printf 'deploy: REFUSING execute — OMNI_SYSROOT set\n' >&2
        return 126
    fi

    case "${DEPLOY_DISK:-}" in
        sda|sdb|sdc|nvme0n1|nvme1n1) : ;;
        '')
            printf 'deploy: DEPLOY_DISK is required\n' >&2
            return 2
            ;;
        *)
            printf 'deploy: unrecognized/unsafe disk name: %s\n' "$DEPLOY_DISK" >&2
            return 2
            ;;
    esac

    case "${DEPLOY_DISTRO:-}" in
        alpine|void|arch|debian|artix|chimera) : ;;
        *)
            printf 'deploy: unsupported distro: %s\n' "${DEPLOY_DISTRO:-}" >&2
            return 2
            ;;
    esac

    preflight_check || return 1
    deploy_state_prepare || return $?

    for _dp_phase in $OMNI_DEPLOY_STEPS; do
        case "$_dp_phase" in
            partitioning) _dp_handler=_deploy_phase_partitioning ;;
            mounting)     _dp_handler=_deploy_phase_mounting ;;
            bootstrap)    _dp_handler=_deploy_phase_bootstrap ;;
            chroot_setup) _dp_handler=_deploy_phase_chroot_setup ;;
            configure)    _dp_handler=_deploy_phase_configure ;;
            desktop)      _dp_handler=_deploy_phase_desktop ;;
            policies)     _dp_handler=_deploy_phase_policies ;;
            initramfs)    _dp_handler=_deploy_phase_initramfs ;;
            bootloader)   _dp_handler=_deploy_phase_bootloader ;;
            verify)       _dp_handler=_deploy_phase_verify ;;
            *)
                printf 'deploy: unknown state phase: %s\n' "$_dp_phase" >&2
                return 2
                ;;
        esac

        if ! deploy_phase_run "$_dp_phase" "$_dp_handler"; then
            _dp_rc=$?

            if [ "$_dp_phase" != "verify" ]; then
                rollback_full "$DEPLOY_TARGET"
                deploy_state_clear || true
            fi

            return "$_dp_rc"
        fi
    done

    deploy_state_clear || true

    printf '\n══ DEPLOYMENT COMPLETE ══\n'
    printf 'Target: %s\n' "$DEPLOY_TARGET"
    printf 'Reboot and select from your bootloader.\n\n'
    return 0
}
