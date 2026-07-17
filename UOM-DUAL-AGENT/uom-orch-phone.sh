#!/bin/sh
# tools/uom-orch-phone.sh — Phone watchdog + fallback orchestrator
# Xiaomi Mi 8 / Termux / Android 15 / POSIX sh / BusyBox ash safe
# Auto-started via ~/.termux/boot/start-uom.sh

set -u
export OMNI_ROOT="${OMNI_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
. "$OMNI_ROOT/tools/uom-orch-state.sh"

AGENT="phone"
LOOP_SLEEP=60
WATCHDOG_SLEEP=120
OPENCODE_TIMEOUT=2400
TAKEOVER_GRACE=300

_log() { printf '[%s] [PHONE] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

_net_ok() {
    ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 || \
    ping -c 1 -W 5 github.com >/dev/null 2>&1
}

_laptop_reachable() {
    _laptop_ip=$(cat "$OMNI_ROOT/.uom-agent/laptop.ip" 2>/dev/null)
    [ -z "$_laptop_ip" ] && return 1
    ping -c 1 -W 3 "$_laptop_ip" >/dev/null 2>&1
}

_announce_phone_ip() {
    _my_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '/src/{print $7; exit}')
    [ -z "$_my_ip" ] && return
    echo "$_my_ip" > "$OMNI_ROOT/.uom-agent/phone.ip"
}

_update_phone_heartbeat() {
    _now=$(date -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
    state_set "phone_heartbeat" "$_now"
}

_run_opencode() {
    _task_id="$1"; _task_desc="$2"; _context="$3"
    _prompt="UOM project — PHONE FALLBACK AGENT (Xiaomi Mi 8 / Termux)
Task ID: $_task_id
Task: $_task_desc

POSIX-ONLY (non-negotiable): #!/bin/sh, zero bashisms, zero eval, BusyBox ash-safe.

${_context}

Implement the task. Output complete file paths and contents."

    printf '%s\n' "$_prompt" | timeout "$OPENCODE_TIMEOUT" opencode 2>&1
}

main() {
    _log "Phone Watchdog starting. OMNI_ROOT=$OMNI_ROOT"
    state_init
    _mode="watchdog"

    while true; do
        if ! _net_ok; then
            _log "Offline. Waiting..."; sleep "$WATCHDOG_SLEEP"; continue
        fi

        state_git_pull
        _announce_phone_ip
        _update_phone_heartbeat

        if [ "$_mode" = "watchdog" ]; then
            if state_laptop_stale; then
                _log "Laptop stale. Grace ${TAKEOVER_GRACE}s..."
                sleep "$TAKEOVER_GRACE"
                state_git_pull
                if state_laptop_stale; then
                    _log "TAKEOVER: laptop offline confirmed. Phone → PRIMARY."
                    _mode="active"
                    _c=$(state_get "takeover_count"); _c=$(( ${_c:-0} + 1 ))
                    state_set "takeover_count" "$_c"
                    state_git_sync "takeover: phone primary (count=$_c)"
                else
                    _log "Laptop returned during grace. Staying watchdog."
                fi
            else
                _log "Watchdog: laptop OK."
                state_git_sync "heartbeat: phone watchdog $(date -Iseconds)"
                sleep "$WATCHDOG_SLEEP"
            fi
            continue
        fi

        if [ "$_mode" = "active" ]; then
            if ! state_laptop_stale && _laptop_reachable; then
                _log "Laptop returned! Switching to handback."
                _mode="handback"; continue
            fi

            _task_id=$(state_next_task)
            if [ -z "$_task_id" ]; then
                _log "No tasks. Phone idle."; sleep "$LOOP_SLEEP"; continue
            fi

            _task_desc=$(state_task_desc "$_task_id")
            _context=$(state_task_context "$_task_id")
            _log "Phone taking: $_task_id"
            state_mark_task "$_task_id" "in_progress"
            state_set "current_task_id" "$_task_id"
            state_set "task_status" "in_progress"
            state_set "active_agent" "$AGENT"
            state_git_sync "start: $_task_id [$AGENT fallback]"

            _out="${TMPDIR:-/tmp}/uom-oc-phone-$$.txt"
            if _run_opencode "$_task_id" "$_task_desc" "$_context" > "$_out" 2>&1; then
                _log "Phone done: $_task_id"
                cp "$_out" "$OMNI_ROOT/.uom-agent/context/${_task_id}-output.md" 2>/dev/null
                state_mark_task "$_task_id" "done"
                state_set "task_status" "done"
                state_git_sync "done: $_task_id [$AGENT fallback]"
            else
                _rc=$?
                _log "Phone failed: $_task_id (rc=$_rc)"
                state_mark_task "$_task_id" "failed"
                state_set "task_status" "failed"
                state_git_sync "failed: $_task_id [$AGENT] rc=$_rc"
            fi
            rm -f "$_out"; sleep 5
        fi

        if [ "$_mode" = "handback" ]; then
            _log "Handback: waiting for laptop heartbeat..."
            state_git_pull
            if ! state_laptop_stale; then
                _log "Laptop confirmed via heartbeat. Phone → WATCHDOG."
                state_set "active_agent" "laptop"
                state_git_sync "handback: phone returned control to laptop"
                _mode="watchdog"
            else
                _log "Laptop still stale. Staying active."
                _mode="active"
            fi
            sleep "$LOOP_SLEEP"
        fi
    done
}

main "$@"
