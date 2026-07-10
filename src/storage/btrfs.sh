#!/bin/sh
# storage/btrfs.sh — Btrfs subvolume and headroom telemetry.

btrfs_is_root_btrfs() {
    _fs=$(storage_fs_type / 2>/dev/null)
    [ "$_fs" = "btrfs" ]
}

btrfs_list_subvolumes() {
    _mnt="${1:-/}"

    if [ -n "${OMNI_SYSROOT:-}" ]; then
        _f="$(_sysfile /omni_fixture_btrfs/subvolumes.txt)"
        [ -r "$_f" ] && cat "$_f"
        return 0
    fi

    command -v btrfs >/dev/null 2>&1 || return 1
    run_as_root btrfs subvolume list "$_mnt" 2>/dev/null |
        awk '{print $NF}'
}

btrfs_subvolume_count() {
    btrfs_list_subvolumes "${1:-/}" 2>/dev/null | grep -c .
}

btrfs_has_subvolume() {
    _sub="$1"
    _mnt="${2:-/}"
    btrfs_list_subvolumes "$_mnt" 2>/dev/null | grep -qx "$_sub"
}

# True unallocated bytes. This is the correct Btrfs headroom metric,
# not used-of-allocated percentage.
btrfs_unallocated_bytes() {
    _mnt="${1:-/}"

    if [ -n "${OMNI_SYSROOT:-}" ]; then
        _f="$(_sysfile /omni_fixture_btrfs/unallocated_bytes.txt)"
        [ -r "$_f" ] && cat "$_f" || echo 0
        return 0
    fi

    command -v btrfs >/dev/null 2>&1 || { echo 0; return 1; }

    run_as_root btrfs filesystem usage -b "$_mnt" 2>/dev/null |
        awk '
            /Device unallocated:/ {print $3; found=1; exit}
            /^Unallocated:/ {getline; print $2; found=1; exit}
            END {if(!found) print 0}
        ' |
        tr -d ','
}
