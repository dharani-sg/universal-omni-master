#!/bin/sh
# bin/omni-orchestrator-monitor.sh — Unified status monitor for UOM hybrid orchestrator
UOM_DIR="${HOME}/src/universal-omni-master"
HYB_DIR="${HOME}/.uom-termux-user"
STATE_FILE="${UOM_DIR}/.uom-agent/state.json"
LOG_FILE="${HYB_DIR}/omni-orchestrator.log"
TUNNEL_LOG="${HYB_DIR}/tunnel.log"

_log() {
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)
    printf '[monitor] %s %s\n' "${_ts}" "$*"
}

status_summary() {
    _ts=$(date)
    echo "=== UOM ORCHESTRATOR STATUS ==="
    echo "TIMESTAMP: ${_ts}"
    echo "----------------------------"

    if [ -f "${STATE_FILE}" ]; then
        _state=$(cat "${STATE_FILE}")
        _mode=$(echo "${_state}" | jq -r '.hybrid_mode // "dual"' 2>/dev/null || echo "dual")
        _active_agent=$(echo "${_state}" | jq -r '.active_agent // "unknown"' 2>/dev/null || echo "unknown")
        _task_status=$(echo "${_state}" | jq -r '.task_status // "idle"' 2>/dev/null || echo "idle")
        _task_id=$(echo "${_state}" | jq -r '.current_task_id // "none"' 2>/dev/null || echo "none")
        _takeover_count=$(echo "${_state}" | jq -r '.takeover_count // 0' 2>/dev/null || echo "0")

        echo "STATE FILE: OK"
        echo "  Hybrid Mode: ${_mode}"
        echo "  Active Agent: ${_active_agent}"
        echo "  Task Status: ${_task_status}"
        echo "  Current Task ID: ${_task_id}"
        echo "  Takeover Count: ${_takeover_count}"
    else
        echo "STATE FILE: NOT FOUND"
    fi

    if [ -d "${HYB_DIR}" ]; then
        if ssh -o ConnectTimeout=3 -o BatchMode=yes -p 18022 127.0.0.1 true 2>/dev/null; then
            echo "REVERSE TUNNEL: UP (port 18022)"
        else
            echo "REVERSE TUNNEL: DOWN"

            if [ -f "${HYB_DIR}/tunnel.pid" ]; then
                _pid=$(cat "${HYB_DIR}/tunnel.pid" 2>/dev/null)
                if ps -p "${_pid}" >/dev/null 2>&1; then
                    echo "  Tunnel Process: RUNNING (PID ${_pid})"
                else
                    echo "  Tunnel Process: NOT RUNNING"
                fi
            fi

            if [ -f "${TUNNEL_LOG}" ]; then
                _recent_log=$(grep "\[uom-rev\\]" "${TUNNEL_LOG}" | tail -5 | head -1)
                if [ -n "$_recent_log" ]; then
                    echo "  Last Tunnel Log: ${_recent_log}"
                fi
            fi
        fi
    else
        echo "REVERSE TUNNEL DIR: NOT FOUND"
    fi

    echo "PROCESSES:"
    if ps -ef | grep -v grep | grep -q "uom-orch-laptop"; then
        echo "  LAPTOP ORCHESTRATOR: RUNNING"
    else
        echo "  LAPTOP ORCHESTRATOR: NOT RUNNING"
    fi

    if ps -ef | grep -v grep | grep -q "uom-orch-phone"; then
        echo "  PHONE ORCHESTRATOR: RUNNING"
    else
        echo "  PHONE ORCHESTRATOR: NOT RUNNING"
    fi

    if ps -ef | grep -v grep | grep -q "uom-solo-orchestrator"; then
        echo "  SOLO ORCHESTRATOR: RUNNING"
    else
        echo "  SOLO ORCHESTRATOR: NOT RUNNING"
    fi

    if [ -f "${LOG_FILE}" ]; then
        echo "LOG FILES: AVAILABLE"
        echo "  Omni Orchestrator: $(tail -n 5 "${LOG_FILE}" 2>/dev/null | tail -1)"
    fi

    if [ -f "${TUNNEL_LOG}" ]; then
        echo "  Tunnel Log: $(tail -n 5 "${TUNNEL_LOG}" 2>/dev/null | tail -1)"
    fi

    if [ -f "${UOM_DIR}/.uom-agent/queue.json" ]; then
        echo "QUEUE:"
        _pending=$(jq -r '[.[] | select(.status=="pending")] | length' "${UOM_DIR}/.uom-agent/queue.json" 2>/dev/null || echo "0")
        echo "  Pending Tasks: ${_pending}"
    fi

    echo ""
}

case "${1:-}" in
    status|--status|--s|--print)
        status_summary
        ;;
    full|--full|--all)
        status_summary
        echo "=== DETAILED LOGS ==="
        if [ -f "${LOG_FILE}" ]; then
            echo "=== Omni Orchestrator Log (last 50 lines) ==="
            tail -n 50 "${LOG_FILE}"
        fi
        if [ -f "${TUNNEL_LOG}" ]; then
            echo "=== Tunnel Log (last 50 lines) ==="
            tail -n 50 "${TUNNEL_LOG}"
        fi
        ;;
    *)
        status_summary
        ;;
esac
