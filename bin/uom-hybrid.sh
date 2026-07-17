#!/bin/sh
# bin/uom-hybrid.sh — UOM Hybrid Orchestrator: auto-switches dual/solo
# Detects laptop reachability, starts tunnel, runs appropriate orchestrator
# Usage: sh bin/uom-hybrid.sh [--daemon]
#   --daemon   Run in tmux session (detached)

set -u

UOM_DIR="${HOME}/src/universal-omni-master"
STATE_FILE="${UOM_DIR}/.uom-agent/state.json"
TUNNEL_PID="${HOME}/.uom-termux-user/tunnel.pid"
HYBRID_PID="${HOME}/.uom-termux-user/hybrid.pid"
LOG_FILE="${HOME}/.uom-termux-user/hybrid.log"
CHECK_INTERVAL=60
STALE_THRESHOLD=300

. "${UOM_DIR}/tools/uom-ip-discover.sh" 2>/dev/null || true

mkdir -p "$(dirname "${LOG_FILE}")" "$(dirname "${TUNNEL_PID}")"

_log() {
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)
    printf '[hybrid] %s %s\n' "${_ts}" "$*" >> "${LOG_FILE}"
    printf '[hybrid] %s\n' "$*"
}

_is_tunnel_up() {
    ssh -o ConnectTimeout=3 -o BatchMode=yes -p 18022 127.0.0.1 true 2>/dev/null
}

_start_tunnel() {
    _log "Starting reverse tunnel..."
    if [ -f "${TUNNEL_PID}" ] && kill -0 "$(cat "${TUNNEL_PID}")" 2>/dev/null; then
        _log "Tunnel already running (PID $(cat "${TUNNEL_PID}"))"
        return 0
    fi
    nohup sh "${UOM_DIR}/bin/uom-reverse-ssh.sh" >/dev/null 2>&1 &
    echo $! > "${TUNNEL_PID}"
    _log "Tunnel started (PID $!)"
    sleep 3
}

_stop_tunnel() {
    if [ -f "${TUNNEL_PID}" ]; then
        _pid=$(cat "${TUNNEL_PID}")
        kill "${_pid}" 2>/dev/null || true
        rm -f "${TUNNEL_PID}"
        _log "Tunnel stopped (PID ${_pid})"
    fi
}

_laptop_reachable() {
    discover_laptop_ip >/dev/null 2>&1 || _is_tunnel_up
}

_run_dual() {
    _log "MODE: Dual-agent (laptop reachable)"
    jq '.active_agent="laptop"' "${STATE_FILE}" > /tmp/state_tmp.json 2>/dev/null && mv /tmp/state_tmp.json "${STATE_FILE}"
    if [ -f "${UOM_DIR}/tools/uom-orch-laptop.sh" ]; then
        sh "${UOM_DIR}/tools/uom-orch-laptop.sh" &
        _orch_pid=$!
        _log "Laptop orchestrator started (PID ${_orch_pid})"
        wait "${_orch_pid}" 2>/dev/null
    fi
}

_run_solo() {
    _log "MODE: Phone-solo (laptop unreachable)"
    jq '.active_agent="phone-solo"' "${STATE_FILE}" > /tmp/state_tmp.json 2>/dev/null && mv /tmp/state_tmp.json "${STATE_FILE}"
    if [ -f "${UOM_DIR}/orchestrators/uom-solo-orchestrator.sh" ]; then
        sh "${UOM_DIR}/orchestrators/uom-solo-orchestrator.sh" &
        _solo_pid=$!
        _log "Solo orchestrator started (PID ${_solo_pid})"
        wait "${_solo_pid}" 2>/dev/null
    fi
}

_start_tmux_session() {
    _session="uom-hybrid"
    tmux kill-session -t "${_session}" 2>/dev/null || true
    tmux new-session -d -s "${_session}" -x 120 -y 40
    tmux rename-window -t "${_session}:0" "hybrid"
    tmux send-keys -t "${_session}:0" "sh ${UOM_DIR}/bin/uom-hybrid.sh" ""
    tmux new-window -t "${_session}" -n "monitor"
    tmux send-keys -t "${_session}:1" "watch -n10 'cat ${STATE_FILE} 2>/dev/null || echo waiting'" ""
    tmux new-window -t "${_session}" -n "log"
    tmux send-keys -t "${_session}:2" "tail -f ${LOG_FILE}" ""
    tmux select-window -t "${_session}:0"
    _log "Tmux session '${_session}' created"
}

main() {
    _mode="${1:-}"

    if [ "${_mode}" = "--daemon" ]; then
        _start_tmux_session
        echo "Session 'uom-hybrid' started. Attach: tmux attach -t uom-hybrid"
        exit 0
    fi

    _log "=== UOM Hybrid Orchestrator starting ==="
    echo "$$" > "${HYBRID_PID}"

    _start_tunnel

    _last_mode=""
    while true; do
        if _laptop_reachable; then
            if [ "${_last_mode}" != "dual" ]; then
                _log "Laptop reachable → dual mode"
                _last_mode="dual"
                jq '.active_agent="laptop"' "${STATE_FILE}" > /tmp/state_tmp.json 2>/dev/null && mv /tmp/state_tmp.json "${STATE_FILE}"
            fi
        else
            if [ "${_last_mode}" != "solo" ]; then
                _log "Laptop unreachable → solo mode"
                _last_mode="solo"
                jq '.active_agent="phone-solo"' "${STATE_FILE}" > /tmp/state_tmp.json 2>/dev/null && mv /tmp/state_tmp.json "${STATE_FILE}"
                _run_solo &
            fi
        fi
        sleep "${CHECK_INTERVAL}"
    done
}

main "$@"
