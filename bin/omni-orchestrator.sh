#!/bin/sh
# bin/omni-orchestrator.sh — Unified hybrid orchestrator with dynamic mode switching
# Tracks hybrid dual-agent status and runs appropriate orchestrator
# Usage: sh bin/omni-orchestrator.sh [--daemon]

UOM_DIR="${HOME}/src/universal-omni-master"
HYB_DIR="${HOME}/.uom-termux-user"
STATE_FILE="${UOM_DIR}/.uom-agent/state.json"
LOG_FILE="${HYB_DIR}/omni-orchestrator.log"
HYB_PID="${HYB_DIR}/omni-orchestrator.pid"
MONITOR_PID="${HYB_DIR}/monitor.pid"

mkdir -p "$(dirname "${LOG_FILE}")" "$(dirname "${HYB_PID}")"

_log() {
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)
    printf '[orchestrator] %s %s\n' "${_ts}" "$*" | tee -a "${LOG_FILE}"
    printf '[orchestrator] %s %s\n' "${_ts}" "$*" >&2
}

_log "Unified hybrid orchestrator starting"

echo "$$" > "${HYB_PID}"

# Main orchestration loop
main() {
    _mode="dual"  # Start in dual-agent mode

    while true; do
        _sync_state

        if [ "$_mode" = "dual" ]; then
            _log "MODE: DUAL (laptop + phone agents running)"
            _run_dual_agents &
            _dual_pid=$!
            wait ${_dual_pid}

            # Check if both should still be dual
            if ! _check_dual_feasible; then
                _mode="solo"
                _log "MODE: switched to solo (laptop unavailable)"
            fi
        else
            _log "MODE: SOLO (phone only agent running)"
            _run_solo_agent &
            _solo_pid=$!
            wait ${_solo_pid}

            if _check_laptop_reachable; then
                _mode="dual"
                _log "MODE: switched to dual (laptop returned)"
            fi
        fi

        sleep 30
    done
}

_sync_state() {
    # Sync current mode to state file
    jq ".hybrid_mode=\"${_mode}\"" "${STATE_FILE}" > "${STATE_FILE}.tmp.$$" && mv "${STATE_FILE}.tmp.$$" "${STATE_FILE}" 2>/dev/null || true
}

_check_dual_feasible() {
    _check_laptop_reachable
}

_check_laptop_reachable() {
    ssh -o ConnectTimeout=3 -o BatchMode=yes -p 31415 127.0.0.1 true 2>/dev/null
}

_run_dual_agents() {
    _log "Starting dual-agent orchestrators"

    # Start laptop orchestrator
    if [ -f "${UOM_DIR}/tools/uom-orch-laptop.sh" ]; then
        sh "${UOM_DIR}/tools/uom-orch-laptop.sh" --daemon &
        _laptop_pid=$!
        _log "Laptop orchestrator started (PID ${_laptop_pid})"
        sleep 5
    fi

    # Start phone orchestrator
    if [ -f "${UOM_DIR}/bin/uom-orch-phone.sh" ]; then
        sh "${UOM_DIR}/bin/uom-orch-phone.sh" &
        _phone_pid=$!
        _log "Phone orchestrator started (PID ${_phone_pid})"
        sleep 5
    fi

    # Monitor for 60s or until task completion
    _watch_start=$(date +%s)
    while true; do
        _now=$(date +%s)
        [ $((_now - _watch_start)) -gt 60 ] && break

        # Check if laptop is active
        _lp_status=$(jq -r '.task_status // "idle"' "${STATE_FILE}" 2>/dev/null || echo "idle")
        if [ "$_lp_status" = "in_progress" ]; then
            _log "Laptop has active task - dual mode valid"
            sleep 5
            continue
        fi

        # Check phone status
        _ph_status=$(grep -o "\[PHONE\] \[.*\]" "${LOG_FILE}" | tail -1)
        if echo "$_ph_status" | grep -q "Phone Watchdog starting"; then
            _log "Phone watchdog active - dual mode valid"
            sleep 5
            continue
        fi

        break
    done

    # Cleanup
    kill ${_laptop_pid:-1} 2>/dev/null || true
    kill ${_phone_pid:-1} 2>/dev/null || true
    wait ${_laptop_pid:-1} 2>/dev/null || true
    wait ${_phone_pid:-1} 2>/dev/null || true
    _log "Dual-agent orchestrators cleaned up"
}

_run_solo_agent() {
    _log "Starting solo orchestrator (phone only)"

    # Use the existing uom-solo-orchestrator.sh from orchestrators/
    if [ -f "${UOM_DIR}/orchestrators/uom-solo-orchestrator.sh" ]; then
        sh "${UOM_DIR}/orchestrators/uom-solo-orchestrator.sh" &
        _solo_pid=$!
        _log "Solo orchestrator started (PID ${_solo_pid})"
        wait ${_solo_pid}
    else
        _log "Solo orchestrator script not found"
        sleep 30
    fi
}

_start_monitor() {
    _log "Starting monitoring session"
    _session="omni-monitor"
    tmux kill-session -t "${_session}" 2>/dev/null || true
    tmux new-session -d -s "${_session}" -x 120 -y 40

    # Main status display
    tmux new-window -t "${_session}" -n "status"
    tmux send-keys -t "${_session}:0" "while true; do echo '=== UOM Omni Status ===' > >(tee -a ${LOG_FILE}); echo 'TIMESTAMP: '"'"'$(date)'"'"' >> ${LOG_FILE}; echo 'STATE:' >> ${LOG_FILE}; cat ${STATE_FILE} 2>/dev/null >> ${LOG_FILE} 2>&1; echo '---' >> ${LOG_FILE}; sleep 10; done" ""

    # State file monitor
    tmux new-window -t "${_session}" -n "state"
    tmux send-keys -t "${_session}:1" "watch -n5 'cat ${STATE_FILE} 2>/dev/null || echo waiting'" ""

    # Log monitor
    tmux new-window -t "${_session}" -n "log"
    tmux send-keys -t "${_session}:2" "tail -f ${LOG_FILE}" ""

    tmux select-window -t "${_session}:0"
    echo "Monitor session '${_session}' started"
}

# Handle --daemon flag
if [ "${1:-}" = "--daemon" ]; then
    _start_monitor
    echo "Session 'omni-monitor' started. Attach: tmux attach -t omni-monitor"
    exit 0
fi

main "$@"
