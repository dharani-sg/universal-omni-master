#!/bin/sh
# tools/uom-orch-laptop.sh — Laptop-side UOM loop orchestrator
# HP Pavilion 15 / Alpine Linux / POSIX sh / BusyBox ash safe
# Usage: tmux new -s orch 'export OMNI_ROOT=~/src/universal-omni-master && sh tools/uom-orch-laptop.sh'

set -u
export OMNI_ROOT="${OMNI_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
. "$OMNI_ROOT/tools/uom-orch-state.sh"

AGENT="laptop"
LOOP_SLEEP=60
OPENCODE_TIMEOUT=1800

_log() { printf '[%s] [LAPTOP] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

_net_ok() {
    ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 || \
    ping -c 1 -W 3 github.com >/dev/null 2>&1
}

_announce_ip() {
    _my_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '/src/{print $7; exit}')
    [ -z "$_my_ip" ] && return
    echo "$_my_ip" > "$OMNI_ROOT/.uom-agent/laptop.ip"
}

_run_opencode() {
    _task_id="$1"; _task_desc="$2"; _context="$3"
    _prompt="You are working on the Universal Omni-Master (UOM) project.
Task ID: $_task_id
Task: $_task_desc

POSIX-ONLY RULES (non-negotiable):
- #!/bin/sh everywhere. Zero bashisms. Zero eval. Zero 'set --'.
- BusyBox ash-safe. All files pass: sh -n <file>
- Mutation guard: exit 126 when OMNI_SYSROOT is set.
- Reference OS: Alpine Linux 3.x (musl, OpenRC).

${_context}

Implement the task. Output complete file paths and full file contents."

    _log "Running opencode: $_task_id"
    printf '%s\n' "$_prompt" | timeout "$OPENCODE_TIMEOUT" opencode 2>&1
    return $?
}

main() {
    _log "UOM Laptop Orchestrator starting. OMNI_ROOT=$OMNI_ROOT"
    state_init

    while true; do
        if ! _net_ok; then
            _log "Offline. Waiting ${LOOP_SLEEP}s..."; sleep "$LOOP_SLEEP"; continue
        fi

        state_git_pull
        _announce_ip
        state_heartbeat "$AGENT"

        # Defer if phone is actively working
        _active=$(state_get "active_agent")
        _status=$(state_get "task_status")
        if [ "$_active" = "phone" ] && [ "$_status" = "in_progress" ]; then
            _log "Phone is working. Deferring."
            state_git_sync "heartbeat: laptop alive, deferring $(date -Iseconds)"
            sleep "$LOOP_SLEEP"; continue
        fi

        _task_id=$(state_next_task)
        if [ -z "$_task_id" ]; then
            _log "No pending tasks. Idle."
            state_git_sync "heartbeat: laptop idle $(date -Iseconds)"
            sleep "$LOOP_SLEEP"; continue
        fi

        _task_desc=$(state_task_desc "$_task_id")
        _context=$(state_task_context "$_task_id")

        _log "Starting: $_task_id — $_task_desc"
        state_mark_task "$_task_id" "in_progress"
        state_set "current_task_id" "$_task_id"
        state_set "task_status" "in_progress"
        state_git_sync "start: $_task_id [$AGENT]"

        _out="${TMPDIR:-/tmp}/uom-oc-laptop-$$.txt"
        if _run_opencode "$_task_id" "$_task_desc" "$_context" > "$_out" 2>&1; then
            _log "Completed: $_task_id"
            cp "$_out" "$OMNI_ROOT/.uom-agent/context/${_task_id}-output.md" 2>/dev/null
            state_mark_task "$_task_id" "done"
            state_set "task_status" "done"
            state_git_sync "done: $_task_id [$AGENT]"
        else
            _rc=$?
            _log "FAILED: $_task_id (exit $_rc)"
            cp "$_out" "$OMNI_ROOT/.uom-agent/context/${_task_id}-error.md" 2>/dev/null
            state_mark_task "$_task_id" "failed"
            state_set "task_status" "failed"
            state_git_sync "failed: $_task_id [$AGENT] rc=$_rc"
        fi
        rm -f "$_out"
        sleep 5
    done
}

main "$@"
