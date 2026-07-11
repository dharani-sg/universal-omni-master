#!/bin/sh
# deploy/rollback.sh — deployment rollback and partition recovery.

# Unmount in REVERSE order (deepest-nested first to prevent EBUSY errors)
rollback_unmount() {
    _target="${1:-$DEPLOY_TARGET}"
    log_info "Unmounting target (reverse order) ..."

    umount -lf "$_target/sys/firmware/efi/efivars" 2>/dev/null || true

    for _mp in \
        "$_target/dev/pts" \
        "$_target/dev" \
        "$_target/proc" \
        "$_target/sys" \
        "$_target/run" \
        "$_target/boot/efi" \
        "$_target/var/log" \
        "$_target/.snapshots" \
        "$_target/home" \
        "$_target"; do
        umount -lf "$_mp" 2>/dev/null || true
    done

    # ELF interpreter cleanup
    chroot_unfix_elf_interp 2>/dev/null || true

    log_info "Unmount complete"
}

# Delete Btrfs subvolumes safely (handles both old and new btrfs-progs)
rollback_btrfs_delete() {
    _dev="$1"
    _mnt_tmp="/tmp/omni-rollback-$$"

    log_info "Cleaning Btrfs subvolumes on /dev/$_dev ..."
    mkdir -p "$_mnt_tmp"

    # Mount top-level subvolume (subvolid=5) to see all subvols
    if mount -o subvolid=5 "/dev/$_dev" "$_mnt_tmp"; then
        # Delete from deepest path to shallowest (sort -r = reverse alphabetical)
        btrfs subvolume list -o "$_mnt_tmp" 2>/dev/null | \
            awk '{print $NF}' | sort -r | \
            while read -r _sv; do
                btrfs subvolume delete "$_mnt_tmp/$_sv" 2>/dev/null || true
            done

        # Delete top-level named subvols
        for _sv in @ @home @snapshots @var_log @xbps_cache; do
            [ -d "$_mnt_tmp/$_sv" ] && btrfs subvolume delete "$_mnt_tmp/$_sv" 2>/dev/null || true
        done

        umount "$_mnt_tmp"
    else
        log_warn "Could not mount top-level Btrfs — manual cleanup may be needed"
    fi

    rmdir "$_mnt_tmp" 2>/dev/null || true
    log_info "Btrfs cleanup complete"
}

# Backup partition table before any partitioning (call this first)
rollback_partition_backup() {
    _dev="$1"
    _backup_dir="${DEPLOY_STATE_DIR:-/var/lib/omni-master/deploy-state}"
    mkdir -p "$_backup_dir"
    sfdisk -d "/dev/$_dev" > "$_backup_dir/${_dev}.sfdisk" 2>/dev/null && \
        log_info "Partition table backed up to $_backup_dir/${_dev}.sfdisk" || \
        log_warn "Could not back up partition table for /dev/$_dev"
}

# Restore partition table from backup
rollback_partition_restore() {
    _dev="$1"
    _backup="${DEPLOY_STATE_DIR:-/var/lib/omni-master/deploy-state}/${_dev}.sfdisk"

    if [ ! -f "$_backup" ]; then
        log_error "No partition backup found at $_backup"
        return 1
    fi

    log_warn "Restoring partition table on /dev/$_dev from backup ..."
    sfdisk --force "/dev/$_dev" < "$_backup" && \
        udevadm settle && \
        log_info "Partition table restored" || \
        log_error "Partition restore failed"
}

# Full rollback: unmount → (optional Btrfs delete) → (optional partition restore)
rollback_full() {
    _target="${1:-$DEPLOY_TARGET}"
    _dev="${DEPLOY_DISK:-}"

    log_warn "=== ROLLBACK INITIATED ==="

    rollback_unmount "$_target"

    if [ -n "$_dev" ] && [ "${DEPLOY_FS:-}" = "btrfs" ]; then
        rollback_btrfs_delete "$_dev"
    fi

    # Only restore partition table if we backed it up AND user confirms
    if [ -n "$_dev" ] && \
       [ -f "${DEPLOY_STATE_DIR:-/var/lib/omni-master/deploy-state}/${_dev}.sfdisk" ]; then
        deploy_confirm "Restore original partition table on /dev/$_dev?" && \
            rollback_partition_restore "$_dev"
    fi

    log_info "Rollback complete. System restored to pre-install state."
}
