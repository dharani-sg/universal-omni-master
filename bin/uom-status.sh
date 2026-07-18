#!/bin/sh
# uom-status.sh — UOM status checker with tunnel management
UOM_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HYB_DIR="${HOME}/.uom-termux-user"
STATE_FILE="${UOM_DIR}/.uom-agent/state.json"
LOG_FILE="${HYB_DIR}/omni-orchestrator.log"
TUNNEL_LOG="${HYB_DIR}/tunnel.log"
MONITOR_DIR="${UOM_DIR}/bin"

# Colors
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m"

_status_summary() {
    _ts=$(date)
    echo "═══ UOM ORCHESTRATOR STATUS ═══"
    echo "TIMESTAMP: ${_ts}"
    echo "────────────────────"

    if [ -f "${STATE_FILE}" ]; then
        _state=$(cat "${STATE_FILE}")
        _mode=$(echo "${_state}" | jq -r '.active_agent // "dual"' 2>/dev/null || echo "dual")
        _active_agent=$(echo "${_state}" | jq -r '.active_agent // "unknown"' 2>/dev/null || echo "unknown")
        _task_status=$(echo "${_state}" | jq -r '.task_status // "idle"' 2>/dev/null || echo "idle")
        _task_id=$(echo "${_state}" | jq -r '.current_task_id // "none"' 2>/dev/null || echo "none")
        _takeover_count=$(echo "${_state}" | jq -r '.takeover_count // 0' 2>/dev/null || echo "0")
        _queue_len=$(jq -r 'length' "${UOM_DIR}/.uom-agent/queue.json" 2>/dev/null || echo "0")

        _failed_count=$(jq -r '[.[] | select(.status == "failed")] | length' "${UOM_DIR}/.uom-agent/queue.json" 2>/dev/null || echo "0")

        echo "STATE FILE: ${GREEN}✓ OK${NC}"
        echo "  Hybrid Mode: ${_mode}"
        echo "  Active Agent: ${_active_agent}"
        echo "  Task Status: ${_task_status}"
        echo "  Current Task ID: ${_task_id}"
        echo "  Takeover Count: ${_takeover_count}"
        echo "  Pending Tasks: ${_queue_len}"
        if [ "${_failed_count}" -gt 0 ]; then
            echo "  ⚠️  FAILED TASKS: ${RED}${_failed_count}${NC}"
        fi
    else
        echo "STATE FILE: ${RED}✗ NOT FOUND${NC}"
    fi

    echo "────────────────────"
    echo "PROCESSES:"

    _check_proc() {
        ps -ef 2>/dev/null | grep -v grep | grep -q "$1"
    }

    for _proc in uom-orch-laptop uom-orch-phone uom-solo-orchestrator; do
        _label=$(echo "$_proc" | sed 's/uom-//' | sed 's/-/ /g' | tr '[:lower:]' '[:upper:]')
        if _check_proc "$_proc"; then
            echo "  ${_label}: ${GREEN}✓ RUNNING${NC}"
        else
            echo "  ${_label}: ${RED}✗ NOT RUNNING${NC}"
        fi
    done

    echo "────────────────────"
    # Detect tunnel by checking the process first, then the port
    if pgrep -f 'autossh.*-R.*31415' >/dev/null 2>&1 || pgrep -f 'ssh.*-R.*31415' >/dev/null 2>&1; then
        echo "REVERSE TUNNEL: ${GREEN}✓ UP (autossh)${NC}"
    elif ssh -F ~/.ssh/config -o ConnectTimeout=2 -o BatchMode=yes uom-phone-rev true 2>/dev/null; then
        echo "REVERSE TUNNEL: ${GREEN}✓ UP (port 31415)${NC}"
    else
        echo "REVERSE TUNNEL: ${RED}✗ DOWN${NC}"
    fi

    if [ -f "${HYB_DIR}/tunnel.pid" ]; then
        _pid=$(cat "${HYB_DIR}/tunnel.pid" 2>/dev/null)
        if ps -p "$_pid" >/dev/null 2>&1; then
            echo "  Tunnel Process: ${GREEN}✓ RUNNING (PID $_pid)${NC}"
        else
            echo "  Tunnel Process: ${RED}✗ NOT RUNNING${NC}"
        fi
    fi

    if [ -f "${TUNNEL_LOG}" ]; then
        _recent_log=$(grep "\[uom-rev\\]" "${TUNNEL_LOG}" 2>/dev/null | tail -5 | tail -1)
        if [ -n "$_recent_log" ]; then
            echo "  Last Tunnel Log: $_recent_log"
        fi
    fi

    echo "────────────────────"
    echo "QUEUE STATUS:"
    if [ -f "${UOM_DIR}/.uom-agent/queue.json" ]; then
        _pending=$(jq -r '[.[] | select(.status=="pending")] | length' "${UOM_DIR}/.uom-agent/queue.json" 2>/dev/null || echo "0")
        echo "  Pending Tasks: ${_pending}"
        _failed_count=$(jq -r '[.[] | select(.status == "failed")] | length' "${UOM_DIR}/.uom-agent/queue.json" 2>/dev/null || echo "0")
        if [ "${_failed_count}" -gt 0 ]; then
            echo "  Failed Tasks: ${RED}${_failed_count}${NC}"
        fi
    fi

    if [ -f "${LOG_FILE}" ]; then
        echo "────────────────────"
        echo "LATEST LOGS:"
        echo "  Omni Orchestrator: $(tail -n 3 "${LOG_FILE}" 2>/dev/null | tail -1 || echo "none")"
    fi

    echo "\n"
}

case "${1:-}" in
    status|--status|--s|--print)
        _status_summary
        ;;
    full|--full|--all)
        _status_summary
        echo "═══ DETAILED LOGS ═══"
        if [ -f "${LOG_FILE}" ]; then
            echo "═══ Omni Orchestrator Log (last 30 lines) ═══"
            tail -n 30 "${LOG_FILE}"
        fi
        if [ -f "${TUNNEL_LOG}" ]; then
            echo "═══ Tunnel Log (last 30 lines) ═══"
            tail -n 30 "${TUNNEL_LOG}"
        fi
        ;;
    tunnel|--tunnel|ssh)
        if pgrep -f 'autossh.*-R.*31415' >/dev/null 2>&1; then
            echo "REVERSE TUNNEL STATUS: ${GREEN}✓ UP (autossh)${NC}"
        elif ssh -F ~/.ssh/config -o ConnectTimeout=3 -o BatchMode=yes uom-phone-rev true 2>/dev/null; then
            echo "REVERSE TUNNEL STATUS: ${GREEN}✓ UP (port 31415)${NC}"
        else
            echo "REVERSE TUNNEL STATUS: ${RED}✗ DOWN${NC}"
            echo "  Start tunnel: nohup sh /uom-reverse-ssh.sh >/dev/null 2>&1 &"
        fi
        ;;
    current|--current|--c)
        if [ -f "${STATE_FILE}" ]; then
            _mode=$(jq -r '.active_agent // "dual"' "${STATE_FILE}" 2>/dev/null)
            _active=$(jq -r '.active_agent // "unknown"' "${STATE_FILE}" 2>/dev/null)
            _task=$(jq -r '.current_task_id // "none"' "${STATE_FILE}" 2>/dev/null)
            echo "Current Mode: ${_mode}"
            echo "Active Agent: ${_active}"
            echo "Current Task ID: ${_task}"
        fi
        ;;
    *)
        _status_summary
        echo "─────────────────────────────────────"
        echo "Quick Reference:"
        echo "  omni-project-status          - Show current status"
        echo "  omni-project-status --full    - Show status + logs"
        echo "  omni-project-status tunnel    - Check reverse tunnel"
        echo "  omni-project-status current   - Show current mode"
        ;;
esac
