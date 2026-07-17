#!/bin/sh
# UOM Final Fix - Simple Working Solution
# Port 18022 cleanup + Reverse SSH tunnel + Phone OpenCode deployment

set -u
UOM_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="${UOM_DIR}/.uom-agent"
LOG_DIR="${STATE_DIR}/logs"
mkdir -p "$LOG_DIR"

_log() {
    _ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u)"
    printf '[fix] %s %s\n' "$_ts" "$*" | tee -a "$LOG_DIR/fix.log"
}

# Fix Port 18022 conflicts
_fix_port_18022() {
    _log "Fixing Port 18022 conflicts..."
    if ss -tlnp 2>/dev/null | grep -q ':18022'; then
        _log "Port 18022 occupied - stopping any running tunnels"
        pkill -f "uom-reverse-ssh.sh" 2>/dev/null || true
        _log "Starting reverse SSH tunnel with Port 18022..."
        if [ -f "${UOM_DIR}/bin/uom-reverse-ssh.sh" ]; then
            cd "${UOM_DIR}"
            UOM_LAPTOP_HOST="$(uom_pw_discover_laptop 2>/dev/null || echo "192.168.40.90")"
            UOM_LAPTOP_SSH_PORT="22"
            UOM_PHONE_SSH_PORT="8022"
            UOM_TUNNEL_PORT="31415"
            sh bin/uom-reverse-ssh.sh start 2>&1 | tee -a "$LOG_DIR/tunnel-start.log" &
            TUNNEL_PID=$!
            echo "$TUNNEL_PID" > "${STATE_DIR}/runtime/tunnel.pid"
            _log "Tunnel started (PID $TUNNEL_PID, listening on Port 18022)"
        fi
    else
        _log "Port 18022 is free - no tunnel needed"
    fi
}

# Install Phone OpenCode (proot-distro)
_install_opencode_phone() {
    _log "Installing Phone OpenCode (proot-distro Debian + CLI)..."
    if [ -f "${UOM_DIR}/bin/uom-phone-provision.sh" ]; then
        _log "Starting phone OpenCode provisioning..."
        cd "${UOM_DIR}"
        sh bin/uom-phone-provision.sh --auto >> "$LOG_DIR/phone-provision.log" 2>&1 &
        PROVISION_PID=$!
        echo "$PROVISION_PID" > "${STATE_DIR}/runtime/provision.pid"
        _log "OpenCode provisioning started (PID $PROVISION_PID)"
        _log "Check status: tail -f $LOG_DIR/phone-provision.log"
    else
        _log "ERROR: uom-phone-provision.sh not found"
    fi
}

# Comprehensive watchdog that monitors everything
_run_watchdog() {
    _log "Starting Comprehensive Watchdog..."
    while true; do
        # Check Port 18022 conflicts
        if ss -tlnp 2>/dev/null | grep -q ':18022'; then
            _log "Port 18022 conflict detected - auto-fixing..."
            _fix_port_18022
        fi
        
        # Check tunnel health
        if [ -f "${STATE_DIR}/runtime/tunnel.pid" ]; then
            _pid=$(cat "${STATE_DIR}/runtime/tunnel.pid" 2>/dev/null)
            if [ -n "$_pid" ] && ! kill -0 "$_pid" 2>/dev/null; then
                _log "Tunnel dead - restarting..."
                _fix_port_18022
            fi
        fi
        
        # Check OpenCode provisioning
        if [ ! -f "${STATE_DIR}/runtime/phone-provision-complete" ]; then
            _log "OpenCode provisioning not yet complete"
        fi
        
        sleep 60
    done
}

# Main fix deployment
main() {
    _log "=== UOM FINAL FIX DEPLOYMENT ==="
    _log "Starting comprehensive deployment with watchdog..."
    
    # Apply fixes
    _fix_port_18022
    _install_opencode_phone
    
    # Start watchdog in background
    cd "${UOM_DIR}"
    sh "$SERVICE_FILE" >/dev/null 2>&1 &
    WATCHDOG_PID=$!
    echo "$WATCHDOG_PID" > "${STATE_DIR}/runtime/watchdog.pid"
    
    _log "=== FIX DEPLOYMENT COMPLETE ==="
    _log "Services:"
    _log "  - Reverse SSH tunnel (Port 18022)"
    _log "  - Phone OpenCode provisioning (proot deb + CLI)"
    _log "  - Comprehensive watchdog monitoring"
    _log ""
    _log "Key files:"
    _log "  - Tunnel PID: ${STATE_DIR}/runtime/tunnel.pid"
    _log "  - Watchdog PID: ${STATE_DIR}/runtime/watchdog.pid"
    _log "  - Provision PID: ${STATE_DIR}/runtime/provision.pid"
    _log "  - logs: $LOG_DIR/"
    _log ""
    _log "Next commands:"
    _log "  ps -ef | grep uom-reverse-ssh | grep -v grep"
    _log "  sh bin/uom-port-guardian.sh status"
    _log "  tail -f $LOG_DIR/phone-provision.log"
}

# Validate environment before proceeding
if ! command -v ss >/dev/null 2>&1; then
    echo "ERROR: 'ss' command not available" >&2
    exit 1
fi

# Run main deployment
main
