#!/bin/sh
# src/snapshot/boot_entry.sh — M11-A: generate bootloader entries for Btrfs snapshots.
# Supports systemd-boot (BLS type1 entries) and GRUB (grub-mkconfig snippets).
# Namespace: all entries use "omni-snap-" prefix to avoid colliding with
# dual-boot OS entries or user-created entries.

SNAP_BOOT_PREFIX="omni-snap"

# ── Detect active bootloader ──────────────────────────────────────────────────
_snap_detect_bootloader() {
    if [ -d /boot/loader/entries ] && command -v bootctl >/dev/null 2>&1; then
        printf 'systemd-boot'
    elif [ -d /boot/grub ] || [ -d /boot/grub2 ]; then
        printf 'grub'
    else
        printf 'unknown'
    fi
}

# ── systemd-boot BLS entry ────────────────────────────────────────────────────
# Path: /boot/loader/entries/omni-snap-<snapname>.conf
_snap_boot_entry_sdboot() {
    _snap_name="$1"
    _snap_subvol="$2"       # e.g., @snapshots/@auto_20250710-123456_pretxn_pacman
    _root_uuid="$3"
    _entry_dir="/boot/loader/entries"
    _entry_file="${_entry_dir}/${SNAP_BOOT_PREFIX}-${_snap_name}.conf"

    [ -d "$_entry_dir" ] || { printf 'boot_entry: %s not found\n' "$_entry_dir" >&2; return 1; }

    # Detect current kernel/initrd names from existing entry
    _kernel=$(ls /boot/vmlinuz-* 2>/dev/null | head -1 | sed 's|.*/||')
    _initrd=$(ls /boot/initramfs-*.img 2>/dev/null | head -1 | sed 's|.*/||')
    [ -z "$_kernel" ] && _kernel="vmlinuz-linux"
    [ -z "$_initrd" ] && _initrd="initramfs-linux.img"

    # Preserve existing kernel cmdline minus the subvol= flag
    _cmdline=""
    _default_entry=$(find "$_entry_dir" -name '*.conf' ! -name "${SNAP_BOOT_PREFIX}-*" | head -1)
    if [ -n "$_default_entry" ] && [ -f "$_default_entry" ]; then
        _cmdline=$(grep '^options ' "$_default_entry" | sed 's/^options //;s/subvol=[^ ]*//' | tr -s ' ')
    fi

    cat > "$_entry_file" << ENTRY
title   [SNAP] ${_snap_name}
linux   /${_kernel}
initrd  /${_initrd}
options root=UUID=${_root_uuid} rw rootflags=subvol=${_snap_subvol} ${_cmdline}
ENTRY

    printf 'boot_entry: created %s\n' "$_entry_file"
}

# ── GRUB custom entry ─────────────────────────────────────────────────────────
# Path: /etc/grub.d/45_omni-snap-<snapname>
_snap_boot_entry_grub() {
    _snap_name="$1"
    _snap_subvol="$2"
    _root_uuid="$3"
    _grub_d="/etc/grub.d"
    _entry_file="${_grub_d}/45_${SNAP_BOOT_PREFIX}-${_snap_name}"

    [ -d "$_grub_d" ] || { printf 'boot_entry: %s not found\n' "$_grub_d" >&2; return 1; }

    # Detect kernel
    _kernel=$(ls /boot/vmlinuz-* 2>/dev/null | head -1 | sed 's|.*/||')
    _initrd=$(ls /boot/initramfs-*.img /boot/initrd.img-* 2>/dev/null | head -1 | sed 's|.*/||')
    [ -z "$_kernel" ] && _kernel="vmlinuz-linux"
    [ -z "$_initrd" ] && _initrd="initramfs-linux.img"

    cat > "$_entry_file" << GRUBSCRIPT
#!/bin/sh
exec tail -n +3 \$0
menuentry "[SNAP] ${_snap_name}" {
    search --no-floppy --fs-uuid --set=root ${_root_uuid}
    linux /${_kernel} root=UUID=${_root_uuid} rw rootflags=subvol=${_snap_subvol}
    initrd /${_initrd}
}
GRUBSCRIPT
    chmod +x "$_entry_file"
    printf 'boot_entry: created %s (run grub-mkconfig to activate)\n' "$_entry_file"
}

# ── Public API ────────────────────────────────────────────────────────────────

# Add a boot entry for a snapshot.
# Usage: snap_boot_entry_add <snapshot_name> [subvol_path]
snap_boot_entry_add() {
    _snap_guard_mutation || return $?
    _snap_require_btrfs / || return 0

    _name="$1"
    _subvol="${2:-${SNAPSHOT_ROOT_SUBVOL:-@root}/../@snapshots/${_name}}"
    _root_uuid=$(blkid -s UUID -o value "$(findmnt -no SOURCE /)" 2>/dev/null || echo "<UUID>")

    _bl=$(_snap_detect_bootloader)
    case "$_bl" in
        systemd-boot) _snap_boot_entry_sdboot "$_name" "$_subvol" "$_root_uuid" ;;
        grub)         _snap_boot_entry_grub "$_name" "$_subvol" "$_root_uuid" ;;
        *)            printf 'boot_entry: unknown bootloader — cannot create entry\n' >&2; return 1 ;;
    esac
}

# List all omni-snap boot entries
snap_boot_entry_list() {
    _bl=$(_snap_detect_bootloader)
    case "$_bl" in
        systemd-boot) ls /boot/loader/entries/${SNAP_BOOT_PREFIX}-*.conf 2>/dev/null | sed "s|.*/||;s|\.conf$||;s|^${SNAP_BOOT_PREFIX}-||" ;;
        grub)         ls /etc/grub.d/45_${SNAP_BOOT_PREFIX}-* 2>/dev/null | sed "s|.*/45_${SNAP_BOOT_PREFIX}-||" ;;
        *)            printf 'boot_entry: unknown bootloader\n' >&2 ;;
    esac
}

# Remove a boot entry for a snapshot
snap_boot_entry_remove() {
    _snap_guard_mutation || return $?
    _name="$1"
    _bl=$(_snap_detect_bootloader)
    case "$_bl" in
        systemd-boot) rm -f "/boot/loader/entries/${SNAP_BOOT_PREFIX}-${_name}.conf" ;;
        grub)         rm -f "/etc/grub.d/45_${SNAP_BOOT_PREFIX}-${_name}" ;;
    esac
    printf 'boot_entry: removed entry for %s\n' "$_name"
}

# Sync: remove boot entries whose snapshots no longer exist
snap_boot_entry_sync() {
    _snap_guard_mutation || return $?
    _existing=$(snap_list_names)
    for _entry_name in $(snap_boot_entry_list); do
        if ! printf '%s\n' "$_existing" | grep -qF "$_entry_name"; then
            printf 'boot_entry_sync: snapshot %s gone — removing stale entry\n' "$_entry_name"
            snap_boot_entry_remove "$_entry_name"
        fi
    done
}
