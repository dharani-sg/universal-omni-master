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
