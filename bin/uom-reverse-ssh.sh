#!/data/data/com.termux/files/usr/bin/sh
# bin/uom-reverse-ssh.sh — Persistent reverse tunnel with autossh + auto-reconnect
# Deployed on phone: laptop:18022 -> phone:8022
# Can be invoked manually or via Termux:Boot
#
# KEY LESSONS (from debugging M30):
# 1. OpenSSH 10.x reports false "remote port forwarding failed" for -R to
#    127.0.0.1 when GatewayPorts=no — the forward actually WORKS despite the
#    warning. NEVER use ExitOnForwardFailure=yes — it kills the tunnel.
# 2. fuser -k on laptop side kills the tunnel's OWN sshd-session process.
#    Only clean LOCAL stale processes; let autossh retry until laptop frees
#    the port naturally (max 90s via ServerAlive*).

set -u

LAPTOP_USER="${UOM_LAPTOP_USER:-alpine}"
REV_PORT="${UOM_REV_PORT:-18022}"
PHONE_SSHD_PORT=8022
TUNNEL_DIR="${HOME}/.uom-termux-user"
TUNNEL_LOG="${TUNNEL_DIR}/tunnel.log"
TUNNEL_PID="${TUNNEL_DIR}/tunnel.pid"
# ExitOnForwardFailure intentionally OMITTED — see KEY LESSONS above
SSH_OPTS="-N -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"
UOM_LAPTOP_IP="${UOM_LAPTOP_IP:-192.168.40.90}"

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
    echo "${UOM_LAPTOP_IP:-192.168.40.90}"
}

# Ensure sshd is running
sshd 2>/dev/null || true

LAPTOP_IP=$(_discover_laptop)
_log "forwarding laptop:${REV_PORT} -> phone:${PHONE_SSHD_PORT} as ${LAPTOP_USER}@${LAPTOP_IP}"
printf '%s\n' "$(id -un)" > "${TUNNEL_DIR}/termux-user"

# ── Clean ONLY local stale processes ──────────────────────────────────────
# Do NOT clean laptop side (fuser -k kills the tunnel's own sshd-session).
# If the old port forward persists, autossh retries until it's freed (max 90s).
_log "cleaning local stale SSH processes..."
pgrep -f "ssh.*-N.*-R.*${REV_PORT}" | grep -v "^$$\$" | while read _pid; do
    _cmd=$(ps -p "$_pid" -o args= 2>/dev/null || true)
    case "$_cmd" in
        *"${LAPTOP_USER}@${LAPTOP_IP}"*) kill "$_pid" 2>/dev/null || true ;;
    esac
done
sleep 1

# ── Prefer autossh for auto-reconnect ─────────────────────────────────────
if command -v autossh >/dev/null 2>&1; then
    _log "using autossh (auto-reconnect enabled, will retry until port free)"
    echo "$$" > "${TUNNEL_PID}"
    export AUTOSSH_LOGFILE="${TUNNEL_LOG}"
    export AUTOSSH_LOGLEVEL=7
    export AUTOSSH_POLL=10
    export AUTOSSH_GATETIME=0
    exec autossh -M 0 \
        ${SSH_OPTS} \
        -R "${REV_PORT}:127.0.0.1:${PHONE_SSHD_PORT}" \
        "${LAPTOP_USER}@${LAPTOP_IP}"
    _log "autossh exited (unexpected)."
else
    _log "autossh not found, using ssh with retry loop"
    while true; do
        echo "$$" > "${TUNNEL_PID}"
        LAPTOP_IP=$(_discover_laptop)
        # Local cleanup only
        pgrep -f "ssh.*-N.*-R.*${REV_PORT}.*" | grep -v "^$$\$" | while read _pid; do
            _cmd=$(ps -p "$_pid" -o args= 2>/dev/null || true)
            case "$_cmd" in *"${LAPTOP_USER}@${LAPTOP_IP}"*) kill "$_pid" 2>/dev/null || true ;; esac
        done
        sleep 2
        ssh ${SSH_OPTS} \
            -R "${REV_PORT}:127.0.0.1:${PHONE_SSHD_PORT}" \
            "${LAPTOP_USER}@${LAPTOP_IP}"
        _log "tunnel dropped — reconnecting in 10s"
        sleep 10
    done
fi

# ── Force cleanup only (run separately when needed) ───────────────────────
# If the tunnel won't come up due to stale port on laptop, run:
#   ssh alpine@192.168.40.90 "pkill -f 'sshd-session.*alpine'"
# This kills all user SSH sessions (including the stale forward).
# Autossh will immediately re-establish with a clean port.
# Add to ~/.ssh/authorized_keys with restrict,command="/usr/sbin/sshd -T" to
# limit this ability.
