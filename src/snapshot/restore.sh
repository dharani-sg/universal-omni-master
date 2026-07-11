#!/bin/sh
# src/snapshot/restore.sh — M11-B: atomic Btrfs restore from snapshot.
# Strategy: create a safety snapshot, then set-default the target snapshot's subvol.
# NO silent auto-reboot. User must confirm + reboot manually.

# Restore a snapshot as the new default root subvol.
# Usage: snap_restore <snapshot_name>
snap_restore() {
    _snap_guard_mutation || return $?
    _snap_require_btrfs / || return 1
    _name="${1:?snap_restore: snapshot name required}"

    # 1. Verify the snapshot exists
    _broot=$(_snap_btrfs_root)
    _snap_path=""
    _match=$(btrfs subvolume list -ro "$_broot" 2>/dev/null | awk '{print $NF}' | grep "$_name" | head -1)
    if [ -z "$_match" ]; then
        printf 'restore: snapshot %s not found\n' "$_name" >&2
        return 1
    fi
    _snap_path="${_broot}/${_match}"

    # M11.1 G8+G4+G5 guards
    _restore_warn_kernel_mismatch "$_snap_path"
    _restore_confirm || { printf 'restore: aborted by user\n'; return 1; }
    [ -d "${_broot}/${SNAPSHOT_ROOT_SUBVOL:-@root}.restore" ] && {
        printf 'restore: stale @root.restore exists — delete it first:\n' >&2
        printf '  btrfs subvolume delete %s/%s.restore\n' "$_broot" "${SNAPSHOT_ROOT_SUBVOL:-@root}" >&2
        return 1; }

    # 2. Safety snapshot before restore (pre-restore breadcrumb)
    printf 'restore: creating pre-restore safety snapshot ...\n'
    snap_create "emergency" "pre-restore-${_name}"

    # 3. Get the target snapshot's subvolume ID
    _snap_id=$(btrfs subvolume show "$_snap_path" 2>/dev/null | awk '/Subvolume ID:/{print $NF}')
    if [ -z "$_snap_id" ]; then
        printf 'restore: cannot determine subvolume ID for %s\n' "$_snap_path" >&2
        return 1
    fi

    # 4. Read-only snapshots cannot be set as default directly.
    # Create a read-write snapshot from the read-only one at the root subvol position.
    _rw_target="${_broot}/${SNAPSHOT_ROOT_SUBVOL:-@root}.restore"
    printf 'restore: creating RW snapshot from %s -> %s\n' "$_snap_path" "$_rw_target"
    btrfs subvolume snapshot "$_snap_path" "$_rw_target" 2>/dev/null || {
        printf 'restore: failed to create RW snapshot\n' >&2
        return 1
    }

    # 5. Get the new RW subvol ID
    _rw_id=$(btrfs subvolume show "$_rw_target" 2>/dev/null | awk '/Subvolume ID:/{print $NF}')

    # 6. Set default subvolume
    printf 'restore: setting default subvol to ID %s (%s)\n' "$_rw_id" "$_rw_target"
    btrfs subvolume set-default "$_rw_id" "$_broot" 2>/dev/null || {
        printf 'restore: set-default FAILED — system is unchanged\n' >&2
        return 1
    }

    # 7. Audit event
    if command -v healer_emit >/dev/null 2>&1; then
        healer_emit "snapshot" "restore" "Restored to $_name (subvolid=$_rw_id)"
    fi

    printf '\n══════════════════════════════════════════\n'
    printf '  RESTORE COMPLETE\n'
    printf '  Snapshot:  %s\n' "$_name"
    printf '  New root:  %s (subvolid %s)\n' "$_rw_target" "$_rw_id"
    printf '  Safety:    pre-restore snapshot created\n'
    printf '\n  Reboot now to activate.\n'
    printf '  The old root is preserved and can be\n'
    printf '  booted via boot-entry or re-restored.\n'
    printf '══════════════════════════════════════════\n'
}

# ── M11.1 additions ───────────────────────────────────────────────────────────

# G8: warn when snapshot's kernel modules don't match running kernel
_restore_warn_kernel_mismatch() {
    _snap_path="$1"
    _cur=$(uname -r 2>/dev/null)
    if [ -d "$_snap_path/usr/lib/modules" ] && \
       [ ! -d "$_snap_path/usr/lib/modules/$_cur" ]; then
        printf 'restore: WARNING — snapshot lacks modules for running kernel %s\n' "$_cur" >&2
        printf 'restore: booted snapshot may miss drivers; prefer boot-once first\n' >&2
    fi
}

# G4: confirmation gate — REQUIRED before any mutation
_restore_confirm() {
    printf 'This stages a ROOT SUBVOLUME CHANGE effective next reboot.\n'
    printf 'Type "yes" to proceed: '
    read -r _ans
    [ "$_ans" = "yes" ]
}

# G7 (M11-C): boot-once — boot into snapshot exactly once, auto-revert
snap_boot_once() {
    _snap_guard_mutation || return $?
    _name="${1:?boot-once: snapshot name required}"
    _bl=$(_snap_detect_bootloader)

    snap_boot_entry_add "$_name" || return 1

    case "$_bl" in
        systemd-boot)
            # Requires writable efivarfs
            if ! bootctl set-oneshot "${SNAP_BOOT_PREFIX}-${_name}.conf" 2>/dev/null; then
                printf 'boot-once: bootctl set-oneshot failed (efivars read-only?)\n' >&2
                return 1
            fi
            printf 'boot-once: next boot -> %s (one time only)\n' "$_name"
            ;;
        grub)
            [ -f /boot/grub/grubenv ] || grub-editenv /boot/grub/grubenv create 2>/dev/null
            grub-reboot "[SNAP] ${_name}" 2>/dev/null || {
                printf 'boot-once: grub-reboot failed\n' >&2; return 1; }
            printf 'boot-once: next boot -> [SNAP] %s (one time only)\n' "$_name"
            ;;
        *)  printf 'boot-once: unsupported bootloader\n' >&2; return 1 ;;
    esac
    printf 'Reboot manually to activate.\n'
}
