#!/bin/sh
# bin/uom-deploy-phone.sh — Deploy opencode config + fixes to phone via SSH
# Usage: sh bin/uom-deploy-phone.sh [phone_ip] [phone_user]
# Prerequisites: phone must have sshd running on port 8022

set -u

UOM_DIR="${HOME}/src/universal-omni-master"
PHONE_IP="${1:-$(cat "${UOM_DIR}/.uom-agent/phone.ip" 2>/dev/null || echo "192.168.40.207")}"
PHONE_USER="${2:-u0_a608}"
PHONE_SSH="ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -p 8022 ${PHONE_USER}@${PHONE_IP}"
DEPLOY_DIR="${UOM_DIR}/config/phone"

_log() { printf '[deploy] %s\n' "$*"; }

_check_phone() {
    _log "Checking phone at ${PHONE_IP}:8022..."
    if ! ${PHONE_SSH} "echo OK" 2>/dev/null; then
        _log "ERROR: Phone not reachable at ${PHONE_IP}:8022"
        _log "Ensure sshd is running on phone: sshd"
        return 1
    fi
    _log "Phone reachable"
    return 0
}

_deploy_opencode_config() {
    _log "Deploying opencode.json to phone..."
    ${PHONE_SSH} "mkdir -p ~/.config/opencode"
    scp -P 8022 "${DEPLOY_DIR}/opencode.json" "${PHONE_USER}@${PHONE_IP}:~/.config/opencode/opencode.json"
    _log "opencode.json deployed"
}

_deploy_network_policy() {
    _log "Deploying NETWORK_CODE_POLICY.md to phone..."
    scp -P 8022 "${UOM_DIR}/NETWORK_CODE_POLICY.md" "${PHONE_USER}@${PHONE_IP}:~/src/universal-omni-master/NETWORK_CODE_POLICY.md"
    _log "NETWORK_CODE_POLICY.md deployed"
}

_deploy_api_wrapper() {
    _log "Deploying api_wrapper.py to phone..."
    scp -P 8022 "${UOM_DIR}/api_wrapper.py" "${PHONE_USER}@${PHONE_IP}:~/src/universal-omni-master/api_wrapper.py"
    _log "api_wrapper.py deployed"
}

_deploy_tunnel_script() {
    _log "Deploying uom-reverse-ssh.sh to phone..."
    ${PHONE_SSH} "mkdir -p ~/bin"
    scp -P 8022 "${UOM_DIR}/bin/uom-reverse-ssh.sh" "${PHONE_USER}@${PHONE_IP}:~/bin/uom-reverse-ssh.sh"
    ${PHONE_SSH} "chmod +x ~/bin/uom-reverse-ssh.sh"
    _log "uom-reverse-ssh.sh deployed to ~/bin/"
}

_start_tunnel() {
    _log "Starting reverse tunnel from phone..."
    ${PHONE_SSH} "nohup sh ~/bin/uom-reverse-ssh.sh > /dev/null 2>&1 &"
    sleep 5
    if ssh -o ConnectTimeout=3 -o BatchMode=yes -p 18022 127.0.0.1 true 2>/dev/null; then
        _log "Reverse tunnel UP"
    else
        _log "Tunnel not yet established (may take a few seconds)"
    fi
}

_verify_deployment() {
    _log "Verifying deployment..."
    ${PHONE_SSH} "
        echo '--- opencode ---'
        which opencode 2>/dev/null || echo 'NOT INSTALLED'
        opencode --version 2>/dev/null || echo 'NO VERSION'
        echo '--- config ---'
        cat ~/.config/opencode/opencode.json 2>/dev/null | head -5 || echo 'NO CONFIG'
        echo '--- tmux ---'
        tmux list-sessions 2>/dev/null || echo 'NO TMUX'
        echo '--- sshd ---'
        ps aux 2>/dev/null | grep sshd | grep -v grep || echo 'NO SSHD'
    "
}

main() {
    _log "=== UOM Phone Deployment ==="
    _check_phone || exit 1
    _deploy_opencode_config
    _deploy_network_policy
    _deploy_api_wrapper
    _deploy_tunnel_script
    _start_tunnel
    _verify_deployment
    _log "=== Deployment Complete ==="
}

main "$@"
