#!/bin/sh
# storage/common.sh — storage EAL: block enumeration, type inference, LUKS, free space.
# POSIX sh, BusyBox ash safe, OMNI_SYSROOT fixture-testable.

_storage_guard_mutation() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        log_error "REFUSING storage mutation: OMNI_SYSROOT is set (fixture/offline mode)."
        return 126
    fi
    return 0
}

# Infer storage type from device name alone (fallback when sysfs is absent/incomplete)
_storage_type_from_name() {
    case "$1" in
        nvme*)   echo nvme   ;;
        mmcblk*) echo emmc   ;;
        sd*|vd*|xvd*|hd*) echo sata ;;
        *)       echo unknown ;;
    esac
}

# Enumerate top-level block devices (excludes loop/ram/zram/dm/sr).
# Emits: <name>|<type>   type = nvme | ssd | hdd | sata | emmc | unknown
storage_enumerate() {
    _base="$(_sysfile /sys/block)"
    [ -d "$_base" ] || return 1

    for _d in "$_base"/*; do
        [ -d "$_d" ] || continue
        _n=$(basename "$_d")

        # Skip virtual/removable
        case "$_n" in
            loop*|ram*|zram*|sr*|dm-*|fd*) continue ;;
        esac

        # Determine type
        case "$_n" in
            nvme*)   _t=nvme; printf '%s|%s\n' "$_n" "$_t"; continue ;;
            mmcblk*) _t=emmc; printf '%s|%s\n' "$_n" "$_t"; continue ;;
        esac

        _rot_f="$_d/queue/rotational"
        if [ -r "$_rot_f" ]; then
            _rot=$(cat "$_rot_f" 2>/dev/null)
            case "$_rot" in
                0) _t=ssd ;;
                1) _t=hdd ;;
                *) _t=$(_storage_type_from_name "$_n") ;;
            esac
        else
            _t=$(_storage_type_from_name "$_n")
        fi

        printf '%s|%s\n' "$_n" "$_t"
    done
}

# Return the type for a single named device
storage_device_type() {
    _dev="${1##*/}"
    _t=$(storage_enumerate 2>/dev/null | awk -F'|' -v d="$_dev" '$1==d {print $2; exit}')
    if [ -n "$_t" ]; then
        echo "$_t"
    else
        _storage_type_from_name "$_dev"
    fi
}

# Filesystem type of a mountpoint
storage_fs_type() {
    _mnt="$1"
    _mf="$(_sysfile /proc/mounts)"
    [ -r "$_mf" ] || return 1
    awk -v m="$_mnt" '$2==m {print $3; exit}' "$_mf"
}

# Detect LUKS container — read-only; no unlock, no passphrase
storage_is_luks() {
    _dev="${1##*/}"

    # Fixture mode: marker file under omni_fixture_luks/
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        _have "/omni_fixture_luks/$_dev" && return 0
        return 1
    fi

    # Try cryptsetup first (most reliable)
    if command -v cryptsetup >/dev/null 2>&1; then
        cryptsetup isLuks "/dev/$_dev" 2>/dev/null && return 0
    fi

    # Fallback: read first 6 bytes and compare to LUKS magic 4c554b53babe
    # POSIX: use dd + od. BusyBox od supports -An -tx1.
    _magic=$(dd if="/dev/$_dev" bs=1 count=6 2>/dev/null | od -An -tx1 | tr -d ' \n')
    case "$_magic" in
        4c554b53babe*) return 0 ;;
    esac

    return 1
}

storage_free_bytes() {
    _mnt="$1"
    df -Pk "$_mnt" 2>/dev/null | awk 'NR==2{print $4*1024}'
}
