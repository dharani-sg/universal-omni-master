#!/bin/sh
# storage/common.sh — Storage EAL: block enumeration, type inference, LUKS, free space.

_storage_guard_mutation() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        log_error "REFUSING storage mutation: OMNI_SYSROOT is set (fixture/offline mode)."
        return 126
    fi
    return 0
}

# Fallback inference from device name when /sys/block data is incomplete.
_storage_type_from_name() {
    case "$1" in
        nvme*) echo nvme ;;
        sd*|vd*|xvd*) echo sata ;;
        mmcblk*) echo emmc ;;
        *) echo unknown ;;
    esac
}

# Enumerate top-level block devices.
# Emits: <name>|<type> where type is nvme|ssd|hdd|sata|emmc|unknown.
storage_enumerate() {
    _base="$(_sysfile /sys/block)"
    [ -d "$_base" ] || return 1

    for _d in "$_base"/*; do
        [ -d "$_d" ] || continue
        _n=$(basename "$_d")
        case "$_n" in
            loop*|ram*|zram*|sr*|dm-*) continue ;;
        esac

        _rot=""
        [ -r "$_d/queue/rotational" ] && _rot=$(cat "$_d/queue/rotational" 2>/dev/null)

        case "$_n" in
            nvme*) _t=nvme ;;
            mmcblk*) _t=emmc ;;
            *)
                if [ "$_rot" = "0" ]; then
                    _t=ssd
                elif [ "$_rot" = "1" ]; then
                    _t=hdd
                else
                    _t=$(_storage_type_from_name "$_n")
                fi
                ;;
        esac

        printf '%s|%s\n' "$_n" "$_t"
    done
}

storage_device_type() {
    _dev="${1##*/}"
    _t=$(storage_enumerate 2>/dev/null | awk -F'|' -v d="$_dev" '$1==d {print $2; exit}')
    [ -n "$_t" ] && { echo "$_t"; return 0; }
    _storage_type_from_name "$_dev"
}

storage_fs_type() {
    _mnt="$1"
    _mounts="$(_sysfile /proc/mounts)"
    [ -r "$_mounts" ] || return 1
    awk -v m="$_mnt" '$2==m {print $3; exit}' "$_mounts"
}

storage_is_luks() {
    _dev="${1##*/}"

    if [ -n "${OMNI_SYSROOT:-}" ]; then
        _have "/omni_fixture_luks/$_dev" && return 0
        return 1
    fi

    if command -v cryptsetup >/dev/null 2>&1; then
        cryptsetup isLuks "/dev/$_dev" 2>/dev/null && return 0
    fi

    # Read-only fallback: LUKS magic at start of device.
    # LUKS1/2 both begin with "LUKS\xba\xbe".
    dd if="/dev/$_dev" bs=6 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n' |
        grep -qi '^4c554b53babe'
}

storage_free_bytes() {
    _mnt="$1"
    df -Pk "$_mnt" 2>/dev/null | awk 'NR==2{print $4*1024}'
}
