#!/bin/sh
# filesystem.sh — filesystem detection, reporting, and configuration guidance.
# POSIX sh, BusyBox ash safe, OMNI_SYSROOT fixture-testable.

# ── Detection ────────────────────────────────────────────────────────────────

# Detect the filesystem type of a mountpoint.
# Uses /proc/mounts as the primary source (works in both live and fixture mode
# because _sysfile prefixes OMNI_SYSROOT automatically).
fs_detect_type() {
    _mnt="${1:-/}"

    # Primary: parse /proc/mounts (sysroot-aware via _sysfile)
    _mf="$(_sysfile /proc/mounts)"
    if [ -r "$_mf" ]; then
        _result=$(awk -v m="$_mnt" '$2==m {print $3; exit}' "$_mf")
        [ -n "$_result" ] && { printf '%s' "$_result"; return 0; }
    fi

    # Fallback for fixture mode: explicit type marker file
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        # Handle / specially (basename of / is empty)
        _base="${_mnt##*/}"
        [ -z "$_base" ] && _base="root"
        _f="$(_sysfile "/omni_fixture_fs/${_base}.type")"
        [ -r "$_f" ] && { cat "$_f"; return 0; }
    fi

    echo unknown
}

# Detect filesystem of a block device
fs_device_type() {
    _dev="${1##*/}"
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        _f="$(_sysfile "/omni_fixture_fs/${_dev}.type")"
        [ -r "$_f" ] && { cat "$_f"; return 0; }
    fi
    # Check /proc/mounts for device → fs mapping
    _mf="$(_sysfile /proc/mounts)"
    [ -r "$_mf" ] && awk -v d="/dev/$_dev" '$1==d {print $3; exit}' "$_mf" 2>/dev/null || echo unknown
}

# Enumerate all mounted filesystems with types
fs_detect_all() {
    _mf="$(_sysfile /proc/mounts)"
    [ -r "$_mf" ] && awk '{print $2 "|" $3}' "$_mf" | sort -u || true
}

# Root filesystem type
fs_root_type() {
    fs_detect_type /
}

# Is root Btrfs?
fs_root_is_btrfs() {
    [ "$(fs_root_type)" = "btrfs" ]
}

# ── Configuration guidance ────────────────────────────────────────────────────

fs_fstab_guide() {
    _fs="$1"
    _dev="${2:-/dev/sdX}"
    _mnt="${3:-/}"

    case "$_fs" in
        ext4)
            printf 'UUID=<uuid> %s ext4 defaults,noatime,errors=remount-ro 0 1\n' "$_mnt"
            ;;
        btrfs)
            printf '# Btrfs recommended — subvolume layout:\n'
            printf 'UUID=<uuid> %s btrfs defaults,noatime,compress=zstd:1,discard=async,space_cache=v2,subvol=@ 0 0\n' "$_mnt"
            printf 'UUID=<uuid> /home btrfs defaults,noatime,compress=zstd:1,discard=async,space_cache=v2,subvol=@home 0 0\n'
            printf 'UUID=<uuid> /.snapshots btrfs defaults,noatime,subvol=@snapshots 0 0\n'
            ;;
        xfs)
            printf 'UUID=<uuid> %s xfs defaults,noatime,logbsize=256k 0 1\n' "$_mnt"
            ;;
        f2fs)
            printf 'UUID=<uuid> %s f2fs defaults,noatime,compress_algorithm=lz4 0 1\n' "$_mnt"
            ;;
        *)
            printf '# Unknown filesystem %s — consult distro documentation\n' "$_fs"
            ;;
    esac
}

fs_btrfs_subvol_guide() {
    _dev="${1:-/dev/sdX}"
    printf '# Btrfs standard subvolume setup:\n'
    printf 'mount %s /mnt\n' "$_dev"
    printf 'btrfs subvolume create /mnt/@\n'
    printf 'btrfs subvolume create /mnt/@home\n'
    printf 'btrfs subvolume create /mnt/@snapshots\n'
    printf 'btrfs subvolume create /mnt/@var_log\n'
    printf 'umount /mnt\n'
    printf '# Then mount with: mount -o subvol=@ %s /\n' "$_dev"
}

# ── User profile ──────────────────────────────────────────────────────────────

FS_PROFILE_PATH="${OMNI_SYSROOT:-}/var/lib/omni-master/fs-profile.conf"

fs_set_preference() {
    _storage_guard_mutation || return $?
    _fs="$1"
    case "$_fs" in
        ext4|btrfs|xfs|f2fs|auto) : ;;
        *) log_error "unsupported filesystem: $_fs (supported: ext4 btrfs xfs f2fs auto)"; return 1 ;;
    esac
    run_as_root mkdir -p "$(dirname "$FS_PROFILE_PATH")"
    printf 'FS_PREFERENCE=%s\n' "$_fs" | run_as_root tee "$FS_PROFILE_PATH" >/dev/null
    log_info "filesystem preference set to: $_fs"
}

fs_get_preference() {
    [ -r "$FS_PROFILE_PATH" ] && \
        awk -F= '/^FS_PREFERENCE=/{print $2; exit}' "$FS_PROFILE_PATH" || echo auto
}
