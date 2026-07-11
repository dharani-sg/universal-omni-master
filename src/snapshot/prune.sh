#!/bin/sh
# src/snapshot/prune.sh — Category-aware retention policy + M8 orphan sweep.
# Fixes R2 (path resolution), R3 (per-category retention), R8 (orphan paths).

# ── Internal: delete oldest N beyond keep limit for a category ────────────────
_prune_category() {
    _cat="$1"     # category string to grep: 'pretxn' | 'hourly' | 'daily' | etc.
    _keep="$2"    # how many to keep

    _broot=$(_snap_btrfs_root)
    # Get paths for this category, sorted oldest first (sort on name = timestamp sort)
    _all=$(btrfs subvolume list -ro "$_broot" 2>/dev/null \
        | awk '{print $NF}' \
        | grep "@auto_.*_${_cat}" \
        | sort)

    _total=$(printf '%s\n' "$_all" | grep -c . 2>/dev/null || echo 0)
    _to_del=$(( _total - _keep ))

    if [ "$_to_del" -le 0 ]; then
        printf 'prune[%s]: %d/%d — nothing to delete\n' "$_cat" "$_total" "$_keep"
        return 0
    fi

    printf 'prune[%s]: %d total, keeping %d, deleting %d oldest\n' \
        "$_cat" "$_total" "$_keep" "$_to_del"

    _deleted=0
    printf '%s\n' "$_all" | head -n "$_to_del" | while read -r _rel; do
        [ -z "$_rel" ] && continue
        _abs="${_broot}/${_rel}"
        if btrfs subvolume delete "$_abs" >/dev/null 2>&1; then
            printf 'prune[%s]: deleted %s\n' "$_cat" "$_abs"
            _deleted=$(( _deleted + 1 ))
        else
            printf 'prune[%s]: WARNING — could not delete %s\n' "$_cat" "$_abs" >&2
        fi
    done
}

# ── Main prune: enforce all category retention limits ────────────────────────
snap_prune() {
    _snap_guard_mutation || return $?
    _snap_require_btrfs / || return 0

    _prune_category "pretxn"  "${SNAPSHOT_RETAIN_PRETXN:-10}"
    _prune_category "hourly"  "${SNAPSHOT_RETAIN_HOURLY:-24}"
    _prune_category "daily"   "${SNAPSHOT_RETAIN_DAILY:-7}"
    _prune_category "weekly"  "${SNAPSHOT_RETAIN_WEEKLY:-4}"
    _prune_category "manual"  "20"     # generous fixed limit for manual snaps
    printf 'prune: complete\n'
}

# ── Free-space emergency prune (call when _snap_check_free_space fails) ───────
snap_prune_emergency() {
    _snap_guard_mutation || return $?
    printf 'prune: EMERGENCY — pruning all categories to minimum to recover space\n' >&2
    _prune_category "pretxn"  "3"
    _prune_category "hourly"  "6"
    _prune_category "daily"   "2"
    _prune_category "weekly"  "1"
    _prune_category "manual"  "5"
}

# ── M8 orphan sweep (R8 fix) ─────────────────────────────────────────────────
# M8 healer_storage_loop creates /@backup_emergency_<epoch> at the Btrfs root.
# These are NOT in $SNAPSHOT_MOUNT — they live at the top-level of the filesystem.
# Path structure: <btrfs_root>/@backup_emergency_<epoch>
healer_snapshot_prune_orphans() {
    _snap_guard_mutation || return $?
    _snap_require_btrfs / || return 0

    _max_age_days="${1:-${SNAPSHOT_RETAIN_PRETXN:-10}}"
    _broot=$(_snap_btrfs_root)
    _now=$(date +%s)
    _count=0

    btrfs subvolume list -ro "$_broot" 2>/dev/null \
        | awk '{print $NF}' \
        | grep '@backup_emergency_' \
        | while read -r _rel; do
            # Extract epoch from @backup_emergency_<epoch> (final component)
            _base=$(printf '%s' "$_rel" | sed 's|.*/||')
            _ts=$(printf '%s' "$_base" | sed 's/^@backup_emergency_//')

            # Validate it's a numeric timestamp
            case "$_ts" in
                *[!0-9]*) continue ;;
            esac

            _age_days=$(( (_now - _ts) / 86400 ))
            if [ "$_age_days" -ge "$_max_age_days" ]; then
                _abs="${_broot}/${_rel}"
                if btrfs subvolume delete "$_abs" >/dev/null 2>&1; then
                    printf 'sweep: removed orphan %s (age %dd)\n' "$_abs" "$_age_days"
                    _count=$(( _count + 1 ))
                fi
            fi
        done
    printf 'sweep: done\n'
}
