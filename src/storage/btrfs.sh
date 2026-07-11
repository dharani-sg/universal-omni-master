#!/bin/sh
# storage/btrfs.sh — Btrfs subvolume, headroom, device stats, scrub status.

btrfs_is_root_btrfs() {
    _fs=$(storage_fs_type / 2>/dev/null)
    [ "$_fs" = "btrfs" ]
}

btrfs_list_subvolumes() {
    _mnt="${1:-/}"
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        _f="$(_sysfile /omni_fixture_btrfs/subvolumes.txt)"
        [ -r "$_f" ] && cat "$_f"; return 0
    fi
    command -v btrfs >/dev/null 2>&1 || return 1
    run_as_root btrfs subvolume list "$_mnt" 2>/dev/null | awk '{print $NF}'
}

btrfs_subvolume_count() {
    btrfs_list_subvolumes "${1:-/}" 2>/dev/null | grep -c .
}

btrfs_has_subvolume() {
    _sub="$1"; _mnt="${2:-/}"
    btrfs_list_subvolumes "$_mnt" 2>/dev/null | grep -qxF "$_sub"
}

btrfs_unallocated_bytes() {
    _mnt="${1:-/}"
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        _f="$(_sysfile /omni_fixture_btrfs/unallocated_bytes.txt)"
        [ -r "$_f" ] && { cat "$_f"; return 0; }; echo 0; return 0
    fi
    command -v btrfs >/dev/null 2>&1 || { echo 0; return 1; }
    run_as_root btrfs filesystem usage -b "$_mnt" 2>/dev/null |
        awk '/Device unallocated:/{gsub(/,/,"",$NF); print $NF+0; found=1; exit}
             END{if(!found) print 0}'
}

# Btrfs device stats — per-counter with severity classification.
btrfs_device_stats() {
    _mnt="${1:-/}"
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        _f="$(_sysfile /omni_fixture_btrfs/device_stats.txt)"
        [ -r "$_f" ] || return 0
        while IFS= read -r _line; do
            _key=$(printf '%s' "$_line" | sed 's/.*\.\([a-z_]*\).*/\1/')
            _val=$(printf '%s' "$_line" | awk '{print $NF}')
            [ -n "$_val" ] || continue
            case "$_key" in
                corruption_errs|generation_errs)
                    printf '%s %s %s\n' "$_key" "$_val" \
                        "$([ "${_val:-0}" -eq 0 ] && echo ok || echo critical)" ;;
                *_errs)
                    printf '%s %s %s\n' "$_key" "$_val" \
                        "$([ "${_val:-0}" -eq 0 ] && echo ok || echo fail)" ;;
            esac
        done < "$_f"
        return 0
    fi
    command -v btrfs >/dev/null 2>&1 || return 0
    run_as_root btrfs device stats "$_mnt" 2>/dev/null |
        while IFS= read -r _line; do
            _key=$(printf '%s' "$_line" | sed 's/.*\.\([a-z_]*\).*/\1/')
            _val=$(printf '%s' "$_line" | awk '{print $NF}')
            [ -n "$_val" ] || continue
            case "$_key" in
                corruption_errs|generation_errs)
                    printf '%s %s %s\n' "$_key" "$_val" \
                        "$([ "${_val:-0}" -eq 0 ] && echo ok || echo critical)" ;;
                *_errs)
                    printf '%s %s %s\n' "$_key" "$_val" \
                        "$([ "${_val:-0}" -eq 0 ] && echo ok || echo fail)" ;;
            esac
        done
}

# Overall Btrfs device health.
# FIX: temp file uses /tmp directly — NEVER _sysfile for runtime temp files.
btrfs_device_health() {
    _mnt="${1:-/}"
    # Use a real /tmp path, never sysroot-prefixed
    _tmp="/tmp/omni_btrfs_health_$$"
    echo ok > "$_tmp" 2>/dev/null || { echo unknown; return 1; }

    btrfs_device_stats "$_mnt" 2>/dev/null | while read -r _k _v _sev; do
        case "$_sev" in
            critical)
                echo critical > "$_tmp"
                ;;
            fail)
                _cur=$(cat "$_tmp" 2>/dev/null)
                [ "$_cur" != "critical" ] && echo fail > "$_tmp"
                ;;
        esac
    done

    cat "$_tmp" 2>/dev/null || echo ok
    rm -f "$_tmp"
}

# Btrfs scrub status: ok | running | errors | no_scrub | unknown
btrfs_scrub_last_status() {
    _mnt="${1:-/}"
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        _f="$(_sysfile /omni_fixture_btrfs/scrub_status.txt)"
        [ -r "$_f" ] && cat "$_f" || echo no_scrub
        return 0
    fi
    command -v btrfs >/dev/null 2>&1 || { echo unknown; return 1; }
    _out=$(run_as_root btrfs scrub status "$_mnt" 2>/dev/null)
    if printf '%s' "$_out" | grep -qi "no stats available"; then echo no_scrub; return 0; fi
    if printf '%s' "$_out" | grep -qi "running"; then echo running; return 0; fi
    if printf '%s' "$_out" | grep -qi "no errors found"; then echo ok; return 0; fi
    if printf '%s' "$_out" | grep -qiE "csum_errors|uncorrectable|error summary"; then echo errors; return 0; fi
    echo unknown
}
