#!/bin/sh
# bin/uom-orchestrator.sh — Unified hybrid orchestrator with dynamic mode switching
# This script maintains a hybrid dual-agent system that switches between modes automatically
# Starts dual-agent orchestration and transitions to solo when laptop becomes unavailable

UOM_DIR="${HOME}/src/universal-omni-master"
HYB_DIR="${HOME}/.uom-termux-user"
STATE_FILE="${UOM_DIR}/.uom-agent/state.json"
LOG_FILE="${HYB_DIR}/omni-orchestrator.log"
HYB_PID="${HYB_DIR}/omni-orchestrator.pid"

mkdir -p "$(dirname "${LOG_FILE}")" "$(dirname "${HYB_PID}")"

_log() {
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)
    printf '[orchestrator] %s %s\n' "${_ts}" "$*" | tee -a "${LOG_FILE}" >&2
}

# Initialize state if not exists
if [ ! -f "${STATE_FILE}" ]; then
    _log "Initializing state file"
    printf '{"schema":1,"active_agent":"laptop","laptop_heartbeat":"","phone_heartbeat":"","current_task_id":"","task_status":"idle","takeover_count":0,"hybrid_mode":"dual"}\n' > "${STATE_FILE}"
fi

# Main orchestration loop
main() {
    _log "Unified hybrid orchestrator starting"
    _mode="dual"  # Start in dual-agent mode

    while true; do
        _sync_state "${_mode}"

        if [ "$_mode" = "dual" ]; then
            _log "MODE: DUAL (laptop + phone agents running)"
            _run_dual_agents

            # Check if laptop is reachable, if not switch to solo
            if ! _check_laptop_reachable; then
                _mode="solo"
                _log "MODE: switched to solo (laptop unreachable)"
                _sync_state "${_mode}"
            fi
        else
            _log "MODE: SOLO (phone only agent running)"
            _run_solo_agent

            # Check if laptop has returned, if yes switch back to dual
            if _check_laptop_reachable; then
                _mode="dual"
                _log "MODE: switched to dual (laptop returned)"
                _sync_state "${_mode}"
            fi
        fi

        sleep 30
    done
}

_sync_state() {
    _mode="$1"
    jq ".hybrid_mode=\"${_mode}\"" "${STATE_FILE}" > /tmp/state_tmp.json && mv /tmp/state_tmp.json "${STATE_FILE}" 2>/dev/null || true
    _log "State saved: hybrid_mode set to ${_mode}"
}

_check_laptop_reachable() {
    # Use the reverse tunnel (laptop is reachable if we can connect to phone via 127.0.0.1:18022)
    ssh -o ConnectTimeout=3 -o BatchMode=yes -p 18022 127.0.0.1 true 2>/dev/null
}

_run_dual_agents() {
    _log "Starting dual-agent orchestrators"

    # Start laptop orchestrator in background
    if [ -f "${UOM_DIR}/tools/uom-orch-laptop.sh" ]; then
        sh "${UOM_DIR}/tools/uom-orch-laptop.sh" --daemon >/dev/null 2>&1 &
        _laptop_pid=$!
        _log "Laptop orchestrator started (PID ${_laptop_pid})"
    else
        _log "ERROR: Laptop orchestrator script not found: ${UOM_DIR}/tools/uom-orch-laptop.sh"
        return 1
    fi

    # Give laptop orchestrator time to initialize
    sleep 3

    # Check if laptop orchestrator is still running
    if ! ps -p "${_laptop_pid}" >/dev/null 2>&1; then
        _log "ERROR: Laptop orchestrator failed to start"
        return 1
    fi

    # Start phone orchestrator in background if available
    if [ -f "${UOM_DIR}/bin/uom-orch-phone.sh" ]; then
        _log "Starting phone orchestrator"
        # Note: Phone orchestrator should already be running from previous deployments
        # If not, we can start it here
    else
        _log "WARNING: Phone orchestrator not found at ${UOM_DIR}/bin/uom-orch-phone.sh"
    fi

    # Monitor for 60 seconds to allow both orchestrators to stabilize
    _watch_start=$(date +%s)
    _done=0

    while [ "${_done}" -eq 0 ]; do
        _now=$(date +%s)
        _elapsed=$((_now - _watch_start))

        # Check if laptop orchestrator is still running
        if ! ps -p "${_laptop_pid}" >/dev/null 2>&1; then
            _log "ERROR: Laptop orchestrator died. Cannot proceed with dual mode."
            return 1
        fi

        # Check if laptop is still reachable via reverse tunnel
        if ! _check_laptop_reachable; then
            _log "ERROR: Laptop became unreachable. Exiting dual mode."
            return 1
        fi

        # If we've been running for 60 seconds, we're done with the check
        if [ "${_elapsed}" -gt 60 ]; then
            _done=1
            _log "Dual-agent setup validated after ${_elapsed}s"
        fi

        sleep 5
    done

    # Keep the main orchestration loop running
    # The orchestrators are running in background and will stay running
    _log "Dual-mode orchestrators are running in background"
    _log "Main orchestrator will continue monitoring..."
}

_run_solo_agent() {
    _log "Starting solo orchestrator (phone only)"

    # Check if we have a solo orchestrator script available
    if [ -f "${UOM_DIR}/orchestrators/uom-solo-orchestrator.sh" ]; then
        # Check if the solo orchestrator is already running
        if ps -ef | grep -v grep | grep -q "uom-solo-orchestrator.sh"; then
            _log "Solo orchestrator is already running"
            return 0
        fi

        # Start solo orchestrator
        sh "${UOM_DIR}/orchestrators/uom-solo-orchestrator.sh" >/dev/null 2>&1 &
        _solo_pid=$!
        _log "Solo orchestrator started (PID ${_solo_pid})"

        # Wait briefly to ensure it started
        sleep 2
        if ps -p "${_solo_pid}" >/dev/null 2>&1; then
            _log "Solo orchestrator running successfully (PID ${_solo_pid})"
        else
            _log "WARNING: Solo orchestrator failed to start, but continuing..."
        fi
    else
        _log "WARNING: Solo orchestrator script not found at ${UOM_DIR}/orchestrators/uom-solo-orchestrator.sh"
        _log "NOTE: Solo mode can still function for basic tasks without orchestrator"
    fi
}

# Handle monitor mode (--daemon flag)
if [ "${1:-}" = "--monitor" ]; then
    _log "Starting monitor session"
    _session="omni-monitor"
    tmux kill-session -t "${_session}" 2>/dev/null || true
    tmux new-session -d -s "${_session}" -x 120 -y 40

    # Main status display
    tmux new-window -t "${_session}" -n "status"
    tmux send-keys -t "${_session}:0" "while true; do echo '=== UOM Omni Status ===' > >(tee -a ${LOG_FILE}); echo 'TIMESTAMP: $(date)' >> ${LOG_FILE}; echo 'STATE:' >> ${LOG_FILE}; cat ${STATE_FILE} 2>/dev/null >> ${LOG_FILE} 2>&1; echo '---' >> ${LOG_FILE}; sleep 10; done" ""

    # State file monitor
    tmux new-window -t "${_session}" -n "state"
    tmux send-keys -t "${_session}:1" "watch -n5 'cat ${STATE_FILE} 2>/dev/null || echo waiting'" ""

    # Log monitor
    tmux new-window -t "${_session}" -n "log"
    tmux send-keys -t "${_session}:2" "tail -f ${LOG_FILE}" ""

    tmux select-window -t "${_session}:0"
    echo "Monitor session '${_session}' started. Attach: tmux attach -t omni-monitor"
    exit 0
fi

# Main entry point
main "$@"
