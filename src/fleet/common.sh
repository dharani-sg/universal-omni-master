#!/bin/sh
# src/fleet/common.sh — M15: fleet coordination primitives.
OMNI_DATA="${OMNI_DATA:-/var/lib/omni-master}"
OMNI_FLEET_DIR="${OMNI_FLEET_DIR:-/etc/omni-master/fleet}"
OMNI_FLEET_INVENTORY="${OMNI_FLEET_INVENTORY:-$OMNI_FLEET_DIR/inventory.conf}"
OMNI_FLEET_STATE="${OMNI_FLEET_STATE:-$OMNI_DATA/fleet/fleet_state.ndjson}"
OMNI_FLEET_MAX_PARALLEL="${OMNI_FLEET_MAX_PARALLEL:-5}"
OMNI_FLEET_SSH_TIMEOUT="${OMNI_FLEET_SSH_TIMEOUT:-10}"

_fleet_guard() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        printf 'fleet: REFUSING mutation — OMNI_SYSROOT set\n' >&2
        return 126
    fi
    return 0
}

_fleet_json_escape() {
    printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' \
        | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' '
}

fleet_emit() {
    _node=$(_fleet_json_escape "$1")
    _event=$(_fleet_json_escape "$2")
    _status=$(_fleet_json_escape "$3")
    _msg=$(_fleet_json_escape "${4:-}")
    _epoch=$(date +%s)
    _iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    mkdir -p "$(dirname "$OMNI_FLEET_STATE")" 2>/dev/null || true
    printf '{"node":"%s","event":"%s","status":"%s","message":"%s","ts":"%s","epoch":%s}\n' \
        "$_node" "$_event" "$_status" "$_msg" "$_iso" "$_epoch" >> "$OMNI_FLEET_STATE" 2>/dev/null
}

fleet_prune_state() {
    _hours="${1:-24}"
    [ -f "$OMNI_FLEET_STATE" ] || return 0
    _cutoff=$(( $(date +%s) - _hours * 3600 ))
    _tmp="${OMNI_FLEET_STATE}.tmp.$$"
    awk -v cutoff="$_cutoff" '{e=$0; sub(/.*"epoch":/,"",e); sub(/[^0-9].*/,"",e); if((e+0)>=cutoff)print}' "$OMNI_FLEET_STATE" > "$_tmp"
    mv "$_tmp" "$OMNI_FLEET_STATE"
}

fleet_list_nodes() {
    _filter_group="${1:-}"
    [ -f "$OMNI_FLEET_INVENTORY" ] || return 0
    while IFS=' ' read -r _name _target _group _tags; do
        [ -z "$_name" ] && continue
        case "$_name" in \#*) continue ;; esac
        if [ -z "$_filter_group" ] || [ "$_group" = "$_filter_group" ]; then
            printf '%s %s %s %s\n' "$_name" "$_target" "$_group" "$_tags"
        fi
    done < "$OMNI_FLEET_INVENTORY"
}

fleet_valid_target() {
    case "$1" in
        ''|*[!A-Za-z0-9_.@:-]*) return 1 ;;
        *@*) return 0 ;;
        *) return 1 ;;
    esac
}
