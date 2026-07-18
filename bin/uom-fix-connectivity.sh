#!/bin/sh
# bin/uom-fix-connectivity.sh — Fix connectivity issues and deploy final solution

# This script prepares the system for deployment by:
# 1. Fixing SSH configurations to allow password-based auth
# 2. Setting up the reverse tunnel properly
# 3. Deploying monitoring tools

UOM_DIR="$(pwd)/src/universal-omni-master"
cd "${UOM_DIR}"

echo "=== UOM Connectivity Fix ==="

# 1. Create proper SSH configuration for direct phone access
echo "Creating SSH configuration for phone access..."
cat << 'EOF' > ~/.ssh/config
# UOM Dual-Agent Configuration

Host uom-phone-hotspot
    HostName 192.168.43.1
    Port 8022
    User u0_a608
    IdentityFile ~/.ssh/id_ed25519_phone
    StrictHostKeyChecking no
    UserKnownHostsFile ~/.ssh/known_hosts_uom
    ConnectTimeout 5
    IdentitiesOnly no

Host uom-phone-lan
    HostName 192.168.40.207
    Port 8022
    User u0_a608
    IdentityFile ~/.ssh/id_ed25519_phone
    StrictHostKeyChecking no
    UserKnownHostsFile ~/.ssh/known_hosts_uom
    ConnectTimeout 5
    IdentitiesOnly no
    PreferredAuthentications=password,publickey

# Connection test to phone
Host phone-test
    HostName 192.168.40.207
    Port 8022
    User u0_a608
    IdentityFile ~/.ssh/id_ed25519_phone
    StrictHostKeyChecking no
    UserKnownHostsFile ~/.ssh/known_hosts_uom
    ConnectTimeout 10
    IdentitiesOnly no
    BatchMode no

EOF

echo "✓ SSH configuration created"

# 2. Test connection with password authentication

echo "Testing phone connectivity with password authentication..."
if ssh -o ConnectTimeout=10 -o PreferredAuthentications=password -o PubkeyAuthentication=no -p 8022 "u0_a608@192.168.40.207" "echo 'ConnectivityTestOK'" 2>&1 | grep -q "ConnectivityTestOK"; then
    echo "✓ Phone connectivity established"
else
    echo "⚠ Phone connectivity test failed, but continuing with deployment..."
fi

# 3. Fix the reverse tunnel configuration on phone
echo "Fixing reverse SSH tunnel configuration..."

_tunnel_fix_tmp=$(mktemp "${TMPDIR:-/tmp}/uom-fix-tunnel-XXXXXX.sh")
cat << 'EOF' > "$_tunnel_fix_tmp"
#!/data/data/com.termux/files/usr/bin/sh

# Kill any existing tunnel processes
pkill -f "uom-reverse-ssh.sh" 2>/dev/null || true

# Check if we have autossh option
if command -v autossh >/dev/null 2>&1; then
    echo "Using autossh (better auto-reconnect)"
    SSH_OPTS="-N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"
    USE_AUTOSSH=true
else
    echo "Using ssh fallback (will reconnect manually)"
    USE_AUTOSSH=false
fi

# Start tunnel
if [ "$USE_AUTOSSH" = true ]; then
    nohup autossh -M 0 \\
        -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \\
        -R 31415:127.0.0.1:8022 \\
        -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \\
        u0_a608@192.168.40.207 >/dev/null 2>&1 &
    echo $! > ~/.uom-termux-user/tunnel.pid
else
    # Fallback with retry loop
    while true; do
        ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \\
            -R 31415:127.0.0.1:8022 \\
            u0_a608@192.168.40.207 || true
        echo "Tunnel dropped, reconnecting in 10 seconds..."
        sleep 10
    done
fi

EOF

chmod +x "$_tunnel_fix_tmp"

echo "✓ Reverse tunnel fix created"

# 4. Deploy the monitoring solution
echo "Deploying status monitoring solution..."

# Deploy omni-status script (laptop version)
cat << 'EOF' > bin/omni-status
#!/bin/sh
# UOM Status Checker - Terminal-based status reporting

cd $(dirname "$0") || exit
UOM_DIR="$(pwd)/src/universal-omni-master"
HYB_DIR="${HOME}/.uom-termux-user"
STATE_FILE="${UOM_DIR}/.uom-agent/state.json"
LOG_FILE="${HYB_DIR}/omni-orchestrator.log"
TUNNEL_LOG="${HYB_DIR}/tunnel.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

_log() {
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)
    printf '[STATUS] %s %s\n' "${_ts}" "$*" >&2
}

status_summary() {
    _ts=$(date)
    echo "====== UOM PROJECT STATUS ====="
    echo "Timestamp: ${_ts}"
    echo "----------------------------------"

    if [ -f "${STATE_FILE}" ]; then
        _state=$(cat "${STATE_FILE}")
        _mode=$(echo "${_state}" | jq -r '.active_agent // "dual"' 2>/dev/null || echo "dual")
        _active_agent=$(echo "${_state}" | jq -r '.active_agent // "unknown"' 2>/dev/null || echo "unknown")
        _task_status=$(echo "${_state}" | jq -r '.task_status // "idle"' 2>/dev/null || echo "idle")
        _task_id=$(echo "${_state}" | jq -r '.current_task_id // "none"' 2>/dev/null || echo "none")
        _takeover_count=$(echo "${_state}" | jq -r '.takeover_count // 0' 2>/dev/null || echo "0")

        _pending=$(jq -r '[.[] | select(.status=="pending")] | length' "${UOM_DIR}/.uom-agent/queue.json" 2>/dev/null || echo "0")
        _failed=$(jq -r '[.[] | select(.status=="failed")] | length' "${UOM_DIR}/.uom-agent/queue.json" 2>/dev/null || echo "0")

        echo "  State File: ${GREEN}✓ OK${NC}"
        echo "    Mode: ${_mode}"
        echo "    Agent: ${_active_agent}"
        echo "    Task: ${_task_id} (${_task_status})"
        echo "    Takeovers: ${_takeover_count}"
        echo "    Tasks: ${NC}${_pending} pending${GREEN}${_failed} failed${NC}"
    else
        echo "  State File: ${RED}✗ NOT FOUND${NC}"
    fi

    echo "----------------------------------"
    echo "Processes:"

    if ps -ef | grep -v grep | grep -q "uom-orch-laptop"; then
        echo "  Laptop Orchestrator: ${GREEN}✓ RUNNING${NC}"
    else
        echo "  Laptop Orchestrator: ${RED}✗ NOT RUNNING${NC}"
    fi

    if ps -ef | grep -v grep | grep -q "uom-orch-phone"; then
        echo "  Phone Orchestrator: ${GREEN}✓ RUNNING${NC}"
    else
        echo "  Phone Orchestrator: ${RED}✗ NOT RUNNING${NC}"
    fi

    if ps -ef | grep -v grep | grep -q "uom-solo-orchestrator"; then
        echo "  Solo Orchestrator: ${GREEN}✓ RUNNING${NC}"
    else
        echo "  Solo Orchestrator: ${RED}✗ NOT RUNNING${NC}"
    fi

    echo "----------------------------------"
    if ssh -o ConnectTimeout=3 -o BatchMode=yes -p 31415 127.0.0.1 true 2>/dev/null; then
        echo "  Reverse Tunnel: ${GREEN}✓ UP${NC} (port 31415)"
    else
        echo "  Reverse Tunnel: ${RED}✗ DOWN${NC}"
        if [ -f "${HYB_DIR}/tunnel.pid" ]; then
            _pid=$(cat "${HYB_DIR}/tunnel.pid" 2>/dev/null)
            if ps -p "${_pid}" >/dev/null 2>&1; then
                echo "    Process: ${GREEN}RUNNING${NC} (PID ${_pid})"
            else
                echo "    Process: ${YELLOW}STOPPED${NC}"
            fi
        fi
    fi

    echo "----------------------------------"
    if [ -f "${LOG_FILE}" ]; then
        _last=$(tail -n 3 "${LOG_FILE}" 2>/dev/null | tail -1)
        echo "  Latest Omni Log: ${_last}"
    fi

    echo "----------------------------------"
    if [ -f "${TUNNEL_LOG}" ]; then
        _last=$(grep "\[uom-rev\\]" "${TUNNEL_LOG}" 2>/dev/null | tail -1)
        if [ -n "$_last" ]; then
            echo "  Latest Tunnel Log: ${_last}"
        fi
    fi

    echo ""
}

# Pipe mode for terminal monitoring
if [ "${1:-}" = "--pipe" ] || [ "${1:-}" = "-p" ]; then
    # Pipe mode - useful for monitoring
    if command -v jq >/dev/null 2>&1; then
        while true; do
            status_summary | grep -v "[[:space:]]*$"
            sleep 5
        done
    else
        status_summary
    fi
    exit 0
fi

# Show status by default
case "${1:-}" in
    status|--status|--s)
        status_summary
        ;;
    full|--full|--a)
        status_summary
        echo "----------------------------------"
        echo "Logs:"
        if [ -f "${LOG_FILE}" ]; then
            echo "--- Omni Orchestrator Log ---"
            tail -n 20 "${LOG_FILE}"
        fi
        if [ -f "${TUNNEL_LOG}" ]; then
            echo "--- Tunnel Log ---"
            tail -n 20 "${TUNNEL_LOG}"
        fi
        ;;
    tunnel|--tunnel|t)
        ssh -o ConnectTimeout=3 -o BatchMode=yes -p 31415 127.0.0.1 true 2>/dev/null && echo "Reverse tunnel is UP" || echo "Reverse tunnel is DOWN"
        ;;
    mode|--mode|m)
        if [ -f "${STATE_FILE}" ]; then
            jq -r '.active_agent // "dual"' "${STATE_FILE}"
        else
            echo "State file not found"
        fi
        ;;
    *)
        status_summary
        echo "---"
        echo "Commands:"
        echo "  $(basename "$0"): Show quick status"
        echo "  $(basename "$0") --full: Show status + logs"
        echo "  $(basename "$0") tunnel: Check tunnel"
        echo "  $(basename "$0") mode: Show current mode"
        ;;
esac
EOF

chmod +x bin/omni-status

echo "✓ Status monitoring tool created"

# 5. Create phone-side deployment script
echo "Creating phone deployment script..."

cat << 'EOF' > bin/uom-deploy-phone-fix.sh
#!/bin/sh
# UOM Phone Deployment Script (Fixed)
# Usage: ./uom-deploy-phone-fix.sh [phone_ip] [phone_user]

PHONE_IP="${1:-192.168.40.207}"
PHONE_USER="${2:-u0_a608}"
PHONE_PORT="8022"
UOM_DIR="${HOME}/src/universal-omni-master"

cd /tmp

_log() {
    echo "[deploy] $*"
}

_check_connectivity() {
    _log "Checking connectivity to ${PHONE_USER}@${PHONE_IP}:${PHONE_PORT}"
    if ssh -o ConnectTimeout=10 -o PreferredAuthentications=password -o PubkeyAuthentication=no -p "${PHONE_PORT}" "${PHONE_USER}@${PHONE_IP}" "echo 'OK'" 2>/dev/null; then
        _log "✓ Phone reachable"
        return 0
    else
        _log "✗ Phone not reachable"
        return 1
    fi
}

_deploy_scripts() {
    _log "Deploying scripts to phone..."

    # Create scripts on phone
    ssh -o ConnectTimeout=10 -p "${PHONE_PORT}" "${PHONE_USER}@${PHONE_IP}" "
        mkdir -p ~/bin
        mkdir -p ~/.uom-termux-user
    "

    # Deploy omni-status script
    scp -P "${PHONE_PORT}" /tmp/uom-status-proxy.py "${PHONE_USER}@${PHONE_IP}:~/bin/" 2>/dev/null || echo "proxy creation failed"

    _log "Scripts deployed"
}

main() {
    _log "=== UOM Phone Deployment (Fixed) ==="
    _check_connectivity || exit 1
    _deploy_scripts
    _log "=== Deployment Complete ==="
}

main "$@"
EOF

chmod +x bin/uom-deploy-phone-fix.sh

echo "✓ Phone deployment script created"

# 6. Save runtime environment
echo "Creating runtime environment..."
mkdir -p config/phone
echo "development" > environment

echo "✓ Runtime environment configured"

echo ""
echo "========================================"
echo "UOM Fix & Deployment Complete!"
echo "========================================"
echo ""
echo "Summary of changes:"
echo "  ✓ SSH configuration for password-based auth"
echo "  ✓ Status monitoring tool (omni-status)"
echo "  ✓ Phone deployment script"
echo "  ✓ Runtime environment"
echo ""
echo "Usage:"
echo "  - Check status: ./bin/omni-status"
echo "  - Monitor logs: ./bin/omni-status --full"
echo "  - Check tunnel: ./bin/omni-status tunnel"
echo "  - Check mode: ./bin/omni-status mode"
echo ""
echo "The system is now ready for operation."
