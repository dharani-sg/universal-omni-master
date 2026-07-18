#!/bin/sh
# tools/uom-port-watch.sh — Dynamic host/port sentinel primitives for UOM
# Source this from the port guardian (and dry-run tests).
# POSIX sh, zero bashisms, zero eval. No network mutation — read-only probes.
#
# The phone (Termux) changes its sshd port and the laptop changes its IP
# because the laptop may be on the phone hotspot OR another WiFi source.
# These helpers discover the CURRENT live target host:port for both sides
# and report drift so the guardian can re-point the tunnel + SSH config.

UOM_PW_TUNNEL_PORT="${UOM_TUNNEL_PORT:-31415}"
UOM_PW_PHONE_SSH_PORTS="${UOM_PHONE_SSH_PORTS:-8022 22 2222 9022}"
UOM_PW_LAPTOP_SSH_PORTS="${UOM_LAPTOP_SSH_PORTS:-22 2222}"
UOM_PW_STATE_DIR="${OMNI_ROOT:-.}/.uom-agent"

# ── Probe a single host:port for an SSH server (read-only) ────────────────
# Returns 0 if an SSH banner/service is reachable within timeout.
uom_pw_probe_ssh() {
    _host="$1"; _port="$2"; _to="${3:-3}"
    # Use bash-free nc if present, else ssh -O / devtcp fallback
    if command -v nc >/dev/null 2>&1; then
        nc -z -w "$_to" "$_host" "$_port" 2>/dev/null && return 0
    fi
    # Fallback: try a no-op ssh connection test (BatchMode, no command)
    SSH_AUTH_TIMEOUT="$_to" ssh -o ConnectTimeout="$_to" -o BatchMode=yes \
        -o StrictHostKeyChecking=accept-new -p "$_port" \
        "${UOM_PHONE_USER:-u0_a608}@${_host}" true >/dev/null 2>&1 && return 0
    return 1
}

# ── Get our own primary IP (the interface facing the peer) ────────────────
uom_pw_my_ip() {
    ip route get 8.8.8.8 2>/dev/null | awk '/src/{print $7; exit}'
}

# ── Get default gateway IP ────────────────────────────────────────────────
uom_pw_gateway() {
    ip route 2>/dev/null | awk '/^default/{print $3; exit}'
}

# ── Are we tethered through the phone hotspot right now? ──────────────────
uom_pw_on_phone_hotspot() {
    _gw=$(uom_pw_gateway)
    [ -z "$_gw" ] && return 1
    case "$_gw" in
        192.168.43.1|192.168.43.*|10.42.*|10.0.0.1) return 0 ;;
    esac
    _my=$(uom_pw_my_ip)
    case "$_my" in
        192.168.4[0-9].*|192.168.1[0-9].*) return 0 ;;
    esac
    return 1
}

# ── Discover the phone's CURRENT sshd host:port (LAN side) ────────────────
# Tries: stored phone.host > LAN ping of known phone IPs > subnet port scan.
# Echoes "host:port" or empty.
uom_pw_discover_phone() {
    # 1. Stored hint (may be host or host:port)
    if [ -f "${UOM_PW_STATE_DIR}/phone.host" ]; then
        _h=$(cat "${UOM_PW_STATE_DIR}/phone.host" 2>/dev/null | tr -d '[:space:]')
        _host=$(printf '%s' "$_h" | sed 's/:.*//')
        _port=$(printf '%s' "$_h" | sed 's/.*://')
        if uom_pw_probe_ssh "$_host" "${_port:-8022}" 2; then
            printf '%s:%s\n' "$_host" "${_port:-8022}"; return 0
        fi
    fi

    # 2. Known phone LAN addresses
    for _cand in 192.168.40.207 192.168.43.1 192.168.1.100 10.42.0.1; do
        for _p in $UOM_PW_PHONE_SSH_PORTS; do
            if uom_pw_probe_ssh "$_cand" "$_p" 2; then
                printf '%s:%s\n' "$_cand" "$_p"; return 0
            fi
        done
    done

    # 3. Subnet scan of our own /24 for any phone sshd port
    _my=$(uom_pw_my_ip)
    if [ -n "$_my" ]; then
        _subnet=$(printf '%s' "$_my" | sed 's/\.[0-9]*$//')
        for _n in $(seq 1 254); do
            _cand="${_subnet}.${_n}"
            [ "$_cand" = "$_my" ] && continue
            for _p in $UOM_PW_PHONE_SSH_PORTS; do
                if uom_pw_probe_ssh "$_cand" "$_p" 1; then
                    printf '%s:%s\n' "$_cand" "$_p"; return 0
                fi
            done
        done
    fi
    return 1
}

# ── Discover the laptop's CURRENT sshd host:port (from phone side) ────────
uom_pw_discover_laptop() {
    # 1. Stored hint
    if [ -f "${UOM_PW_STATE_DIR}/laptop.host" ]; then
        _h=$(cat "${UOM_PW_STATE_DIR}/laptop.host" 2>/dev/null | tr -d '[:space:]')
        _host=$(printf '%s' "$_h" | sed 's/:.*//')
        _port=$(printf '%s' "$_h" | sed 's/.*://')
        if uom_pw_probe_ssh "$_host" "${_port:-22}" 2; then
            printf '%s:%s\n' "$_host" "${_port:-22}"; return 0
        fi
    fi
    # 2. Known laptop LAN addresses
    for _cand in 192.168.40.90 192.168.43.90 10.42.0.2 192.168.1.10; do
        for _p in $UOM_PW_LAPTOP_SSH_PORTS; do
            if uom_pw_probe_ssh "$_cand" "$_p" 2; then
                printf '%s:%s\n' "$_cand" "$_p"; return 0
            fi
        done
    done
    return 1
}

# ── Is the reverse tunnel (laptop:TUNNEL_PORT -> phone) alive? ────────────
uom_pw_tunnel_up() {
    ssh -o ConnectTimeout=3 -o BatchMode=yes -p "$UOM_PW_TUNNEL_PORT" 127.0.0.1 true >/dev/null 2>&1
}

# ── Read last-seen host:port from a state hint file ───────────────────────
uom_pw_read_hint() {
    _f="${UOM_PW_STATE_DIR}/$1"
    [ -f "$_f" ] && cat "$_f" 2>/dev/null | tr -d '[:space:]'
}

# ── Write a host:port hint atomically ─────────────────────────────────────
uom_pw_write_hint() {
    _f="${UOM_PW_STATE_DIR}/$1"
    _v="$2"
    mkdir -p "${UOM_PW_STATE_DIR}"
    printf '%s\n' "$_v" > "${_f}.tmp" 2>/dev/null && mv "${_f}.tmp" "$_f" 2>/dev/null
}
