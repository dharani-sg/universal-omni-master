#!/bin/sh
# src/snapshot/common.sh — Btrfs snapshot lifecycle core.
# OMNI_SYSROOT mutation guard (M2 pattern): exit 126 if set.
# Non-Btrfs graceful skip (R5): always no-op, never hard-fail.

OMNI_SNAP_CONF="${OMNI_SNAP_CONF:-/etc/omni-snapshot.conf}"

# Defaults (overridable via /etc/omni-snapshot.conf)
SNAPSHOT_PERIODIC="${SNAPSHOT_PERIODIC:-1}"
SNAPSHOT_PRETXN="${SNAPSHOT_PRETXN:-1}"
SNAPSHOT_RETAIN_HOURLY="${SNAPSHOT_RETAIN_HOURLY:-24}"
SNAPSHOT_RETAIN_DAILY="${SNAPSHOT_RETAIN_DAILY:-7}"
SNAPSHOT_RETAIN_WEEKLY="${SNAPSHOT_RETAIN_WEEKLY:-4}"
SNAPSHOT_RETAIN_PRETXN="${SNAPSHOT_RETAIN_PRETXN:-10}"
SNAPSHOT_MIN_FREE_GB="${SNAPSHOT_MIN_FREE_GB:-5}"
SNAPSHOT_ROOT_SUBVOL="${SNAPSHOT_ROOT_SUBVOL:-@root}"
SNAPSHOT_MOUNT="${SNAPSHOT_MOUNT:-/.snapshots}"

snap_load_conf() {
    [ -f "$OMNI_SNAP_CONF" ] && . "$OMNI_SNAP_CONF"
    :
}

# ── Mutation guard (M2 pattern) ───────────────────────────────────────────────
_snap_guard_mutation() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        printf '[fixture] REFUSING snapshot mutation: OMNI_SYSROOT is set.\n' >&2
        return 126
    fi
    return 0
}

# ── Btrfs detection — graceful skip, never hard error (R5 fix) ───────────────
# Returns 0 if Btrfs, 1 if not (caller decides whether to skip or warn).
_snap_is_btrfs() {
    _mp="${1:-/}"
    mount 2>/dev/null | grep -q " on ${_mp} type btrfs"
}

# Non-Btrfs warning: log and return 0 (skip) so hooks never abort txns (R5+R11)
_snap_require_btrfs() {
    _mp="${1:-/}"
    if ! _snap_is_btrfs "$_mp"; then
        printf 'omni-snapshot: %s is not Btrfs — snapshot skipped.\n' "$_mp" >&2
        return 1
    fi
    return 0
}

# ── Free-space guard (R4 fix) ─────────────────────────────────────────────────
# Aborts snapshot if available space is below SNAPSHOT_MIN_FREE_GB.
_snap_check_free_space() {
    _mp="${1:-/}"
    _min_kb=$(( SNAPSHOT_MIN_FREE_GB * 1024 * 1024 ))
    _avail_kb=$(df -Pk "$_mp" 2>/dev/null | awk 'NR==2{print $4}')
    if [ -z "$_avail_kb" ] || [ "$_avail_kb" -lt "$_min_kb" ]; then
        printf 'omni-snapshot: insufficient free space on %s (need %dGB, have %dkB) — skipped.\n' \
            "$_mp" "$SNAPSHOT_MIN_FREE_GB" "${_avail_kb:-0}" >&2
        return 1
    fi
    return 0
}

# ── Naming convention ─────────────────────────────────────────────────────────
# Format: @auto_YYYYMMDD-HHMMSS_<category>_<reason>
# Category: hourly | daily | weekly | pretxn | manual | emergency
_snap_gen_name() {
    _category="${1:-manual}"
    _reason="${2:-}"
    _ts=$(date +%Y%m%d-%H%M%S)
    if [ -n "$_reason" ]; then
        printf '@auto_%s_%s_%s' "$_ts" "$_category" "$_reason"
    else
        printf '@auto_%s_%s' "$_ts" "$_category"
    fi
}

# ── Btrfs subvol path resolution (R2 fix) ────────────────────────────────────
# btrfs subvolume list outputs paths relative to the Btrfs filesystem root.
# We need to map those to absolute paths via the mount point of the filesystem.
# Strategy: use the mount point of SNAPSHOT_MOUNT's filesystem as the prefix.
_snap_btrfs_root() {
    _mp="${SNAPSHOT_MOUNT:-/.snapshots}"
    # Walk up to find the Btrfs mountpoint
    df -P "$_mp" 2>/dev/null | awk 'NR==2{print $6}'
}

# List bare snapshot names managed by omni-snapshot (sorted oldest first).
# Only returns the final path component name (the subvol name itself).
snap_list_names() {
    _broot=$(_snap_btrfs_root)
    btrfs subvolume list -ro "${_broot:-.}" 2>/dev/null \
        | awk '{print $NF}' \
        | sed 's|.*/||' \
        | grep '^@auto_' \
        | sort
}

# List with absolute paths (for delete operations)
snap_list_paths() {
    _broot=$(_snap_btrfs_root)
    btrfs subvolume list -ro "${_broot:-.}" 2>/dev/null \
        | awk '{print $NF}' \
        | grep '/@auto_\|^@auto_' \
        | sort \
        | while read -r _rel; do
            # Prefix with the Btrfs root mount to get an accessible path
            printf '%s/%s\n' "$_broot" "$_rel"
        done
}

# ── Core create ───────────────────────────────────────────────────────────────
# Usage: snap_create <category> [reason]
# category: pretxn | hourly | daily | weekly | manual | emergency
snap_create() {
    _category="${1:-manual}"
    _reason="${2:-}"

    _snap_guard_mutation || return $?
    _snap_require_btrfs / || return 0   # non-Btrfs: skip silently (R5)
    _snap_check_free_space / || return 1

    _name=$(_snap_gen_name "$_category" "$_reason")
    _dest="${SNAPSHOT_MOUNT}/${_name}"

    # Ensure snapshot subvol mountpoint exists
    # /.snapshots must be a mounted Btrfs subvol (R9 documentation)
    if [ ! -d "$SNAPSHOT_MOUNT" ]; then
        printf 'omni-snapshot: %s does not exist — cannot create snapshot.\n' "$SNAPSHOT_MOUNT" >&2
        printf 'Hint: Create and mount a Btrfs subvol at %s first.\n' "$SNAPSHOT_MOUNT" >&2
        return 1
    fi

    if btrfs subvolume snapshot -r / "$_dest" >/dev/null 2>&1; then
        printf 'omni-snapshot: created %s\n' "$_dest"
        return 0
    else
        printf 'omni-snapshot: ERROR — btrfs snapshot failed for %s\n' "$_dest" >&2
        return 1
    fi
}

# Convenience wrappers for CLI --reason flag (R1 fix)
snap_create_pretxn()   { snap_create pretxn   "$1"; }
snap_create_hourly()   { snap_create hourly   ""; }
snap_create_daily()    { snap_create daily    ""; }
snap_create_weekly()   { snap_create weekly   ""; }
snap_create_manual()   { snap_create manual   "${1:-}"; }
snap_create_emergency(){ snap_create emergency "${1:-}"; }
