#!/bin/sh
# src/snapshot/restore.sh — M11.1 staged restore + boot-once.
# NO set-default (M7 pins subvol=@root in cmdline; set-default is ignored).
# Strategy: safety snapshot -> RW clone -> boot entry -> manual reboot.

RESTORE_PENDING="${RESTORE_PENDING:-/var/lib/omni-master/snapshot-restore.pending}"

# Reject anything but safe subvol-name characters
_restore_valid_name() {
    case "$1" in
        ''|*[!A-Za-z0-9@._-]*) return 1 ;;
        *) return 0 ;;
    esac
}

_restore_warn_kernel_mismatch() {
    _snap_path="$1"
    _cur=$(uname -r 2>/dev/null)
    if [ -d "$_snap_path/usr/lib/modules" ] && \
       [ ! -d "$_snap_path/usr/lib/modules/$_cur" ]; then
        printf 'restore: WARNING — snapshot lacks modules for running kernel %s\n' "$_cur" >&2
        printf 'restore: prefer boot-once before a permanent restore\n' >&2
    fi
}

_restore_confirm() {
    printf 'This stages a ROOT restore effective on NEXT REBOOT (current system stays live).\n'
    printf 'Type "yes" to proceed: '
    read -r _ans
    [ "$_ans" = "yes" ]
}

# snap_restore <name> — stage a restore. Never reboots.
snap_restore() {
    _snap_guard_mutation || return $?
    _snap_require_btrfs / || return 1
    _name="${1:?snap_restore: snapshot name required}"

    _restore_valid_name "$_name" || {
        printf 'restore: invalid snapshot name: %s\n' "$_name" >&2; return 1; }

    # Exact-match existence check (no partial grep)
    if ! snap_list_names | grep -qxF "$_name"; then
        printf 'restore: snapshot not found: %s\n' "$_name" >&2; return 1
    fi

    _broot=$(_snap_btrfs_root)
    _src="${SNAPSHOT_MOUNT:-/.snapshots}/${_name}"
    [ -d "$_src" ] || { printf 'restore: missing %s\n' "$_src" >&2; return 1; }

    _restore_warn_kernel_mismatch "$_src"
    _restore_confirm || { printf 'restore: aborted.\n'; return 1; }

    # 1) Mandatory pre-restore safety snapshot (must succeed)
    printf 'restore: creating pre-restore safety snapshot...\n'
    if ! snap_create manual "pre-restore-${_name}"; then
        printf 'restore: ABORT — safety snapshot failed; no changes made\n' >&2
        return 1
    fi

    # 2) Unique RW clone (never overwrite @root)
    _stamp=$(date +%Y%m%d-%H%M%S)
    _rw="@restore_${_stamp}_$$"
    _rw_path="${SNAPSHOT_MOUNT:-/.snapshots}/${_rw}"
    printf 'restore: creating RW clone %s\n' "$_rw_path"
    if ! btrfs subvolume snapshot "$_src" "$_rw_path" >/dev/null 2>&1; then
        printf 'restore: ABORT — RW clone failed\n' >&2; return 1
    fi

    # 3) Boot entry targeting the RW clone (subvol path, never subvolid)
    if ! snap_boot_entry_add "$_rw" "@snapshots/${_rw}" 2>/dev/null; then
        printf 'restore: boot entry failed; removing staged clone\n' >&2
        btrfs subvolume delete "$_rw_path" >/dev/null 2>&1 || true
        return 1
    fi

    mkdir -p "$(dirname "$RESTORE_PENDING")" 2>/dev/null || true
    printf 'source=%s\nclone=%s\nstaged=%s\n' "$_name" "$_rw" "$_stamp" > "$RESTORE_PENDING"

    command -v healer_emit >/dev/null 2>&1 && \
        healer_emit "snapshot" "restore_staged" "staged $_name as $_rw; awaiting reboot"

    printf '\n✓ Restore staged: %s\n' "$_rw"
    printf '✓ Reboot and pick the [SNAP] entry. Undo: omni-snapshot restore-cancel\n\n'
}

# snap_restore_cancel — remove the staged clone + boot entry
snap_restore_cancel() {
    _snap_guard_mutation || return $?
    _snap_require_btrfs / || return 1

    [ -f "$RESTORE_PENDING" ] || { printf 'restore-cancel: nothing staged\n'; return 0; }
    _clone=$(awk -F= '/^clone=/{print $2}' "$RESTORE_PENDING")
    [ -n "$_clone" ] || { printf 'restore-cancel: corrupt pending file\n' >&2; return 1; }

    # Refuse if the staged clone is the currently mounted root
    _cur=$(findmnt -no SOURCE / 2>/dev/null | sed 's/.*\[\(.*\)\]/\1/')
    case "$_cur" in
        */"$_clone"|"$_clone"|*"@snapshots/$_clone")
            printf 'restore-cancel: staged clone is the running root — refusing\n' >&2
            return 1 ;;
    esac

    snap_boot_entry_remove "$_clone" 2>/dev/null || true
    _path="${SNAPSHOT_MOUNT:-/.snapshots}/${_clone}"
    btrfs subvolume delete "$_path" >/dev/null 2>&1 || true
    rm -f "$RESTORE_PENDING"
    printf 'restore-cancel: staged restore removed\n'
}

# snap_boot_once <name> — one-shot boot; auto-reverts
snap_boot_once() {
    _snap_guard_mutation || return $?
    _name="${1:?boot-once: snapshot name required}"
    _restore_valid_name "$_name" || {
        printf 'boot-once: invalid name: %s\n' "$_name" >&2; return 1; }

    snap_boot_entry_add "$_name" 2>/dev/null || return 1
    _bl=$(_snap_detect_bootloader)
    case "$_bl" in
        systemd-boot)
            if [ -d /sys/firmware/efi/efivars ] && \
               ! touch /sys/firmware/efi/efivars/.omni-test 2>/dev/null; then
                printf 'boot-once: EFI vars read-only — cannot set oneshot\n' >&2
                return 1
            fi
            rm -f /sys/firmware/efi/efivars/.omni-test 2>/dev/null
            bootctl set-oneshot "${SNAP_BOOT_PREFIX}-${_name}.conf" 2>/dev/null || {
                printf 'boot-once: bootctl set-oneshot failed\n' >&2; return 1; }
            printf 'boot-once: next boot -> %s (once only)\n' "$_name" ;;
        grub)
            [ -f /boot/grub/grubenv ] || grub-editenv /boot/grub/grubenv create 2>/dev/null
            grub-reboot "[SNAP] ${_name}" 2>/dev/null || {
                printf 'boot-once: grub-reboot failed\n' >&2; return 1; }
            printf 'boot-once: next boot -> [SNAP] %s (once only)\n' "$_name" ;;
        *)  printf 'boot-once: unsupported bootloader\n' >&2; return 1 ;;
    esac
    printf 'Reboot manually to activate.\n'
}
