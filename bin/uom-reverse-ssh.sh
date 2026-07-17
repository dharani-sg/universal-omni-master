#!/data/data/com.termux/files/usr/bin/sh
# bin/uom-reverse-ssh.sh — Persistent reverse tunnel with autossh + auto-reconnect
# Deployed on phone: laptop:18022 -> phone:8022
# Can be invoked manually or via Termux:Boot

set -u

LAPTOP_USER="${UOM_LAPTOP_USER:-alpine}"
REV_PORT="${UOM_REV_PORT:-18022}"
PHONE_SSHD_PORT=8022
TUNNEL_DIR="${HOME}/.uom-termux-user"
TUNNEL_LOG="${TUNNEL_DIR}/tunnel.log"
TUNNEL_PID="${TUNNEL_DIR}/tunnel.pid"
SSH_OPTS="-N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

mkdir -p "${TUNNEL_DIR}"

_log() {
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)
    printf '[uom-rev] %s %s\n' "${_ts}" "$*" | tee -a "${TUNNEL_LOG}"
}

_discover_laptop() {
    if command -v avahi-resolve >/dev/null 2>&1; then
        _ip=$(avahi-resolve -n hp-pavilion.local 2>/dev/null | awk '{print $2}' | head -1)
        [ -n "$_ip" ] && [ "$_ip" != "0.0.0.0" ] && echo "$_ip" && return 0
    fi
    _gw=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
    if [ -n "$_gw" ]; then
        _base=$(echo "$_gw" | sed 's/\.[0-9]*$//')
        for _s in 100 101 102 103 104 105 106 107 108 109 110; do
            _c="${_base}.${_s}"
            if ping -c 1 -W 1 "$_c" >/dev/null 2>&1 && nc -z -w 2 "$_c" 22 2>/dev/null; then
                echo "$_c"; return 0
            fi
        done
    fi
    [ -f ~/src/universal-omni-master/.uom-agent/laptop.ip ] && \
        cat ~/src/universal-omni-master/.uom-agent/laptop.ip && return 0
    echo "${UOM_LAPTOP_IP:-192.168.43.1}"
}

# Ensure sshd is running
sshd 2>/dev/null || true

LAPTOP_IP=$(_discover_laptop)
_log "forwarding laptop:${REV_PORT} -> phone:${PHONE_SSHD_PORT} as ${LAPTOP_USER}@${LAPTOP_IP}"
printf '%s\n' "$(id -un)" > "${TUNNEL_DIR}/termux-user"

# Prefer autossh for auto-reconnect; fallback to ssh with retry loop
if command -v autossh >/dev/null 2>&1; then
    _log "using autossh (auto-reconnect enabled)"
    echo "$$" > "${TUNNEL_PID}"
    exec autossh -M 0 \
        ${SSH_OPTS} \
        -R "${REV_PORT}:127.0.0.1:${PHONE_SSHD_PORT}" \
        "${LAPTOP_USER}@${LAPTOP_IP}"
else
    _log "autossh not found, using ssh with retry loop"
    while true; do
        echo "$$" > "${TUNNEL_PID}"
        LAPTOP_IP=$(_discover_laptop)
        ssh ${SSH_OPTS} \
            -R "${REV_PORT}:127.0.0.1:${PHONE_SSHD_PORT}" \
            "${LAPTOP_USER}@${LAPTOP_IP}"
        _log "tunnel dropped — reconnecting in 10s"
        sleep 10
    done
fi
