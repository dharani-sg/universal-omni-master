#!/bin/sh
# src/fleet/swarm.sh — M15: swarm policy enforcement + event propagation.

swarm_policy_get() {
    _mf="$1"; _key="$2"
    [ -f "$_mf" ] || return 1
    grep "^${_key}=" "$_mf" | head -n 1 | cut -d= -f2-
}

swarm_policy_lines() {
    _mf="$1"
    [ -f "$_mf" ] || return 0
    grep -v '^[[:space:]]*#' "$_mf" | grep '=' | grep -v '^[[:space:]]*$'
}

swarm_apply() {
    _fleet_guard || return $?
    _mf="${1:?swarm_apply: manifest file required}"
    _group="${2:-}"
    [ -f "$_mf" ] || { printf 'swarm_apply: manifest not found: %s\n' "$_mf" >&2; return 1; }

    swarm_policy_lines "$_mf" | while IFS='=' read -r _key _val; do
        [ -z "$_key" ] && continue
        case "$_key" in
            daily_snapshot)
                if [ "$_val" = "enabled" ]; then
                    _remote_cmd='command -v omni-snapshot >/dev/null 2>&1 && omni-snapshot periodic || echo "no-omni-snapshot"'
                else
                    _remote_cmd='echo "daily_snapshot=disabled: no-op"'
                fi
                ;;
            healer_watch)
                _remote_cmd="printf 'HEALER_WATCH_SERVICES=\"%s\"\n' '$_val' >/tmp/omni-fleet-healer-watch.hint 2>/dev/null || true; echo applied"
                ;;
            *)
                fleet_emit "policy" "swarm_apply" "skipped" "unknown key: $_key"
                continue
                ;;
        esac
        fleet_parallel_exec "$_remote_cmd" "$_group"
        fleet_emit "policy" "swarm_apply" "applied" "key=$_key val=$_val group=${_group:-all}"
    done
}

_swarm_event_matches() {
    printf '%s' "$1" | grep -q "\"event\":\"$2\""
}

swarm_propagate_event() {
    _fleet_guard || return $?
    _event_line="${1:?event json line required}"
    _pattern="${2:?trigger pattern required}"
    _target_group="${3:?target group required}"
    _remote_cmd="${4:?remote command required}"

    if _swarm_event_matches "$_event_line" "$_pattern"; then
        fleet_emit "swarm" "propagate" "triggered" "pattern=$_pattern -> group=$_target_group"
        fleet_parallel_exec "$_remote_cmd" "$_target_group"
        return 0
    fi
    return 1
}
