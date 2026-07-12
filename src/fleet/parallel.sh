#!/bin/sh
# src/fleet/parallel.sh — M15: parallel SSH execution (POSIX batch).
# CRITICAL: Never pipe into a while-loop that backgrounds jobs.
# POSIX pipe creates a subshell; background jobs inside it are orphaned
# and the parent's `wait` cannot see them. Use a temp file redirect.

fleet_run_on_node() {
    _name="$1"; _target="$2"; _cmd="$3"
    _ssh="${OMNI_SSH_CMD:-ssh}"
    _opts="-o BatchMode=yes -o ConnectTimeout=${OMNI_FLEET_SSH_TIMEOUT:-10} ${OMNI_SSH_OPTS:-}"
    _start=$(date +%s)
    _output=$($_ssh $_opts "$_target" "$_cmd" 2>&1)
    _rc=$?
    _end=$(date +%s)
    _dur=$((_end - _start))
    if [ "$_rc" -eq 0 ]; then
        fleet_emit "$_name" "exec" "ok" "rc=$_rc dur=${_dur}s"
    else
        fleet_emit "$_name" "exec" "failed" "rc=$_rc dur=${_dur}s"
    fi
    return "$_rc"
}

fleet_parallel_exec() {
    _cmd="${1:?fleet_parallel_exec: remote command required}"
    _group="${2:-}"
    _max="${OMNI_FLEET_MAX_PARALLEL:-5}"
    _running=0
    _nodes_tmp="${TMPDIR:-/tmp}/omni-fleet-nodes.$$"

    fleet_list_nodes "$_group" > "$_nodes_tmp"

    while IFS=' ' read -r _name _target _grp _tags; do
        [ -z "$_name" ] && continue
        if ! fleet_valid_target "$_target"; then
            fleet_emit "$_name" "exec" "skipped" "invalid target: $_target"
            continue
        fi
        ( fleet_run_on_node "$_name" "$_target" "$_cmd" ) &
        _running=$((_running + 1))
        if [ "$_running" -ge "$_max" ]; then
            wait
            _running=0
        fi
    done < "$_nodes_tmp"

    rm -f "$_nodes_tmp"
    wait
    return 0
}
