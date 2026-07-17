#!/data/data/com.termux/files/usr/bin/sh
# create_omni_status_alias.sh - Creates omni-project-status alias on phone
# Usage: sh create_omni_status_alias.sh

cd /src/universal-omni-master || exit
UOM_DIR="$(pwd)"

# Configuration
PHONE_IP="192.168.40.207"
PHONE_USER="u0_a608"
PHONE_PORT="8022"

# Validate SSH connection to phone
_log() {
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)
    echo "[create] ${_ts} $*"
}

_log "Checking phone connectivity..."

# Check if we can connect to phone SSH
if ! ssh -o ConnectTimeout=5 -o PreferredAuthentications=password -o PubkeyAuthentication=no -p "${PHONE_PORT}" "${PHONE_USER}@${PHONE_IP}" "echo 'SSH_OK'" 2>/dev/null; then
    echo "Error: Cannot connect to phone at ${PHONE_IP}:${PHONE_PORT}"
    echo "Please ensure your phone is reachable and has sshd running on port 8022"
    exit 1
fi

_log "SSH connectivity OK"

_log "Creating omni-project-status script on phone..."

# Create the monitor script on phone
cat << 'EOF' > /src/omni-project-status.sh
#!/data/data/com.termux/files/usr/bin/sh
# omni-project-status - Unified status monitor for UOM project
# Shows operational status across both laptop and phone agents

cd /src/universal-omni-master || exit
UOM_DIR="$(pwd)"
HYB_DIR="${HOME}/.uom-termux-user"
STATE_FILE="${UOM_DIR}/.uom-agent/state.json"
LOG_FILE="${HYB_DIR}/omni-orchestrator.log"
TUNNEL_LOG="${HYB_DIR}/tunnel.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

_status_summary() {
    _ts=$(date)
    echo "═══════════════════════════════════════════════════════════════════"
    echo "                     UOM ORCHESTRATOR STATUS MONITOR                     "
    echo "═══════════════════════════════════════════════════════════════════"
    echo "TIMESTAMP: ${_ts}"
    echo "───────────────────────────────────────────────────────────────────"

    if [ -f "${STATE_FILE}" ]; then
        _state=$(cat "${STATE_FILE}")
        _mode=$(echo "${_state}" | jq -r '.hybrid_mode // "dual"' 2>/dev/null || echo "dual")
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

    echo "───────────────────────────────────────────────────────────────────"
    echo "PROCESSES:"

    if _aptest() { ps -ef | grep -v grep | grep -q "$1"; }; then
        case "$1" in
            uom-orch-laptop) echo "  LAPTOP ORCHESTRATOR: ${GREEN}✓ RUNNING${NC}" ;;
            uom-orch-phone) echo "  PHONE ORCHESTRATOR: ${GREEN}✓ RUNNING${NC}" ;;
            uom-solo-orchestrator) echo "  SOLO ORCHESTRATOR: ${GREEN}✓ RUNNING${NC}" ;;
            *) echo "  UNKNOWN PROCESS: ${YELLOW}?${NC}" ;;
        esac
    else
        case "$1" in
            uom-orch-laptop) echo "  LAPTOP ORCHESTRATOR: ${RED}✗ NOT RUNNING${NC}" ;;
            uom-orch-phone) echo "  PHONE ORCHESTRATOR: ${RED}✗ NOT RUNNING${NC}" ;;
            uom-solo-orchestrator) echo "  SOLO ORCHESTRATOR: ${RED}✗ NOT RUNNING${NC}" ;;
            *) echo "  UNKNOWN PROCESS: ${YELLOW}?${NC}" ;;
        esac
    fi

    echo "───────────────────────────────────────────────────────────────────"
    echo "REVERSE TUNNEL: $(ssh -o ConnectTimeout=3 -o BatchMode=yes -p 18022 127.0.0.1 true 2>/dev/null && echo "${GREEN}✓ UP (port 18022)${NC}" || echo "${RED}✗ DOWN${NC}")"

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

    echo "───────────────────────────────────────────────────────────────────"
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
        echo "───────────────────────────────────────────────────────────────────"
        echo "LATEST LOGS:"
        echo "  Omni Orchestrator: $(tail -n 3 "${LOG_FILE}" 2>/dev/null | tail -1 || echo "none")"
    fi

    echo -e "\n"
}

case "${1:-}" in
    status|--status|--s|--print)
        _status_summary
        ;;
    full|--full|--all)
        _status_summary
        echo "═══════════════════════════════════════════════════════════════════"
        echo "                      DETAILED LOGS                          "
        echo "═══════════════════════════════════════════════════════════════════"
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
        if ssh -o ConnectTimeout=3 -o BatchMode=yes -p 18022 127.0.0.1 true 2>/dev/null; then
            echo "REVERSE TUNNEL STATUS: ${GREEN}✓ UP${NC} (connect on laptop: ssh -p 18022 127.0.0.1)"
        else
            echo "REVERSE TUNNEL STATUS: ${RED}✗ DOWN${NC}"
            echo "  Check: ps -ef | grep uom-reverse-ssh.sh"
            echo "  Start tunnel: nohup sh /uom-reverse-ssh.sh >/dev/null 2>&1 &"
        fi
        ;;
    current|--current|--c)
        if [ -f "${STATE_FILE}" ]; then
            _mode=$(jq -r '.hybrid_mode // "dual"' "${STATE_FILE}" 2>/dev/null)
            _active=$(jq -r '.active_agent // "unknown"' "${STATE_FILE}" 2>/dev/null)
            _task=$(jq -r '.current_task_id // "none"' "${STATE_FILE}" 2>/dev/null)
            echo "Current Mode: ${_mode}"
            echo "Active Agent: ${_active}"
            echo "Current Task ID: ${_task}"
        fi
        ;;
    *)
        _status_summary
        echo "───────────────────────────────────────────────────────────────────"
        echo "Usage:")
        echo "  omni-project-status          Display current status"
        echo "  omni-project-status --full    Display status + logs"
        echo "  omni-project-status tunnel    Check reverse tunnel"
        echo "  omni-project-status current   Show current mode"
        ;;
esac
EOF

# Make the script executable on phone
ssh -o ConnectTimeout=5 -p "${PHONE_PORT}" "${PHONE_USER}@${PHONE_IP}" "chmod +x /src/omni-project-status.sh"

_log "omni-project-status script created on phone"

# Create a launcher script in ~/bin/ for easy access
_log "Creating alias launcher script in ~/bin/ for ${PHONE_USER}@${PHONE_IP}"

cat << 'EOF' > /tmp/phone_launcher.sh
#!/bin/sh
cd /src/universal-omni-master
./bin/omni-orchestrator-monitor.sh "$@"
EOF

chmod +x /tmp/phone_launcher.sh
ssh -o ConnectTimeout=5 -p "${PHONE_PORT}" "${PHONE_USER}@${PHONE_IP}" "
mkdir -p ~/bin
cat << 'ENDSCRIPT' > ~/bin/omni-project-status
#!/data/data/com.termux/files/usr/bin/sh
cd /src/universal-omni-master
./src/omni-project-status.sh \"\$@\"
ENDSCRIPT
chmod +x ~/bin/omni-project-status
"

_log "Launcher script created in ~/bin/"

# Create .bashrc alias entry
ssh -o ConnectTimeout=5 -p "${PHONE_PORT}" "${PHONE_USER}@${PHONE_IP}" "
if ! grep -q 'omni-project-status' ~/.bashrc 2>/dev/null; then
    echo '' >> ~/.bashrc
    echo '# UOM project status command alias' >> ~/.bashrc
    echo 'alias omni-project-status="/data/data/com.termux/files/usr/bin/sh ~/bin/omni-project-status.sh"' >> ~/.bashrc
    echo 'alias uom-status="/src/universal-omni-master/bin/omni-orchestrator-monitor.sh"' >> ~/.bashrc
fi
"

_log "Alias added to ~/.bashrc"

# Show completion message
_log "=== Deployment Complete ==="
_log ""
_log "Created the following on ${PHONE_USER}@${PHONE_IP}:"
_log "  1. /src/omni-project-status.sh - Main status monitoring script"
_log "  2. ~/bin/omni-project-status - Alias command to run monitor"
_log "  3. ~/bin/uom-status - UOM status shortcut"
_log ""
_log "Access status on laptop with:"
_log "  1. omni-project-status        - Quick status summary"
_log "  2. omni-project-status --full - Full status with logs"
_log "  3. omni-project-status tunnel  - Check tunnel status"
_log "  4. omni-project-status current - Show current mode"
_log ""
_log "To use the alias on phone: ssh -p ${PHONE_PORT} ${PHONE_USER}@${PHONE_IP}"
_log "Then run: omni-project-status"

# Return to script directory
cd /home/alpine/src/universal-omni-master

echo "=== UOM Status Alias Deployment Complete ==="
echo ""
echo "Created on phone ${PHONE_USER}@${PHONE_IP}:"
echo "  1. /src/omni-project-status.sh - Main status monitoring script"
echo "  2. ~/bin/omni-project-status - Alias command to run monitor"
echo "  3. ~/bin/uom-status - UOM status shortcut (also deployed)"
echo ""
echo "To check status on laptop:"
echo "  omni-project-status        - Quick status summary"
echo "  omni-project-status --full  - Full status with logs"
echo "  omni-project-status tunnel  - Check tunnel status"
echo ""
echo "To use the alias on phone:"
echo "  ssh -p ${PHONE_PORT} ${PHONE_USER}@${PHONE_IP}"
echo "  Then run: omni-project-status"
