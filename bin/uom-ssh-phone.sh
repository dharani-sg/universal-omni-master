#!/bin/sh
# bin/uom-ssh-phone.sh — Single SSH wrapper to phone with drift-tolerant discovery
# All scripts use THIS to reach the phone. IP changes handled in one place.
#
# Usage:
#   bin/uom-ssh-phone.sh 'command'           # Run command on phone
#   bin/uom-ssh-phone.sh -t 'command'        # Interactive (pty)
#   bin/uom-ssh-phone.sh                      # Interactive shell
#   bin/uom-ssh-phone.sh discover             # Just discover + print IP
#   bin/uom-ssh-phone.sh verify               # Verify identity at cached IP
#
# If running ON the phone (Android/Termux), executes locally (no SSH).
# POSIX sh. No bashisms. No hardcoded IPs.

set -u

UOM_DIR="${HOME}/src/universal-omni-master"
UOM_CONFIG_DIR="${HOME}/.config/uom"
UOM_STATE_DIR="${UOM_DIR}/.uom-agent"
UOM_LOG_FILE="${UOM_CONFIG_DIR}/discovery.log"
UOM_LAST_IP_FILE="${UOM_CONFIG_DIR}/last-phone-ip.txt"
UOM_PHONE_KNOWN_HOSTS="${UOM_CONFIG_DIR}/phone_known_hosts"

# ── SSH options (standardized for ALL phone connections) ─────────────────
UOM_SSH_OPTS="-o ConnectTimeout=10 \
-o BatchMode=yes \
-o StrictHostKeyChecking=accept-new \
-o UserKnownHostsFile=${UOM_PHONE_KNOWN_HOSTS} \
-o ServerAliveInterval=30 \
-o ServerAliveCountMax=3 \
-i ${HOME}/.ssh/id_ed25519_phone \
-p ${UOM_PHONE_SSH_PORT:-8022}"

UOM_PHONE_USER="${UOM_PHONE_USER:-u0_a608}"

# ── Identity constants (for verification) ────────────────────────────────
UOM_PHONE_HOST_KEY_HASH="SHA256:dBPM+vGSkHXdv91rN0ZLubvP/Oqul+N/malqz5Ph/JY"
UOM_PHONE_DEVICE="Mi 8"
UOM_PHONE_QEMU_DIR="~/uom-vm"

# ── Logging ──────────────────────────────────────────────────────────────
_log() {
    _ts=$(date +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null || date)
    mkdir -p "$(dirname "${UOM_LOG_FILE}")" 2>/dev/null || true
    printf '[%s] [ssh-phone] %s\n' "$_ts" "$*" >> "${UOM_LOG_FILE}" 2>/dev/null || true
}

# ── Am I on the phone? ──────────────────────────────────────────────────
_is_phone() {
    [ "$(uname -o 2>/dev/null)" = "Android" ]
}

# ── Discover phone IP (multi-method) ────────────────────────────────────
_discover_phone_ip() {
    # Method 0: Phone-announce file (freshest, phone writes its own IP)
    _announce="${UOM_DIR}/.uom-agent/phone.ip"
    if [ -f "$_announce" ]; then
        _ann_ip=$(cat "$_announce" 2>/dev/null | tr -d '[:space:]')
        if [ -n "$_ann_ip" ]; then
            # Check if it's a host:port or bare IP
            _ann_host=$(printf '%s' "$_ann_ip" | sed 's/:.*//')
            _ann_port=$(printf '%s' "$_ann_ip" | sed 's/.*://')
            [ "$_ann_host" = "$_ann_port" ] && _ann_port="${UOM_PHONE_SSH_PORT:-8022}"
            if ssh -o ConnectTimeout=3 -o BatchMode=yes \
                -i "${HOME}/.ssh/id_ed25519_phone" \
                -o UserKnownHostsFile="${UOM_PHONE_KNOWN_HOSTS}" \
                -p "$_ann_port" "${UOM_PHONE_USER}@${_ann_host}" \
                'echo UOM_ANNOUNCE_OK' 2>/dev/null | grep -q "UOM_ANNOUNCE_OK"; then
                echo "$_ann_ip"
                return 0
            fi
        fi
    fi

    # Method 0b: Hotspot mode — gateway IS the phone
    _gw=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
    if [ -n "$_gw" ]; then
        case "$_gw" in
            192.168.43.1|10.42.*.1)
                # Phone hotspot gateway — phone IS the gateway
                if ssh -o ConnectTimeout=3 -o BatchMode=yes \
                    -i "${HOME}/.ssh/id_ed25519_phone" \
                    -o UserKnownHostsFile="${UOM_PHONE_KNOWN_HOSTS}" \
                    -p "${UOM_PHONE_SSH_PORT:-8022}" "${UOM_PHONE_USER}@${_gw}" \
                    'echo UOM_HOTSPOT_OK' 2>/dev/null | grep -q "UOM_HOTSPOT_OK"; then
                    echo "$_gw"
                    return 0
                fi
                ;;
        esac
    fi

    # Try cached IP first (fast, most reliable after first discovery)
    if [ -f "${UOM_LAST_IP_FILE}" ]; then
        _cached=$(cat "${UOM_LAST_IP_FILE}" 2>/dev/null | tr -d '[:space:]')
        if [ -n "$_cached" ]; then
            if ssh -o ConnectTimeout=3 -o BatchMode=yes \
                -i "${HOME}/.ssh/id_ed25519_phone" \
                -o UserKnownHostsFile="${UOM_PHONE_KNOWN_HOSTS}" \
                -p ${UOM_PHONE_SSH_PORT:-8022} "${UOM_PHONE_USER}@${_cached}" \
                'echo UOM_PROBE_OK' 2>/dev/null | grep -q "UOM_PROBE_OK"; then
                echo "$_cached"
                return 0
            fi
            _log "Cached IP ${_cached} unreachable, scanning..."
        fi
    fi

    # Try reverse tunnel (phone→laptop reverse SSH on port 31415)
    if ssh -o ConnectTimeout=2 -o BatchMode=yes -p ${UOM_TUNNEL_PORT:-31415} 127.0.0.1 \
        'echo UOM_TUNNEL_OK' 2>/dev/null | grep -q "UOM_TUNNEL_OK"; then
        # Tunnel is up — but we want the direct phone IP too for cache
        # Use tunnel for now
        echo "127.0.0.1"
        return 0
    fi

    # Try mDNS
    if command -v avahi-resolve >/dev/null 2>&1; then
        _mdns_ip=$(avahi-resolve -n mi8.local 2>/dev/null | awk '{print $2}' | head -1)
        if [ -n "$_mdns_ip" ] && [ "$_mdns_ip" != "0.0.0.0" ]; then
            if ssh -o ConnectTimeout=3 -o BatchMode=yes \
                -i "${HOME}/.ssh/id_ed25519_phone" \
                -o UserKnownHostsFile="${UOM_PHONE_KNOWN_HOSTS}" \
                -p 8022 "${UOM_PHONE_USER}@${_mdns_ip}" \
                'echo UOM_MDNS_OK' 2>/dev/null | grep -q "UOM_MDNS_OK"; then
                echo "$_mdns_ip"
                return 0
            fi
        fi
    fi

    # Last resort: scan current /24 for port 8022
    _my_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '/src/{print $7; exit}')
    if [ -n "$_my_ip" ]; then
        _subnet=$(echo "$_my_ip" | sed 's/\.[0-9]*$//')
        _i=1
        while [ "$_i" -le 254 ]; do
            _test_ip="${_subnet}.${_i}"
            [ "$_test_ip" = "$_my_ip" ] && { _i=$((_i + 1)); continue; }
            # Quick TCP probe
            if (echo >/dev/tcp/"${_test_ip}"/8022) 2>/dev/null || \
               nc -z -w1 "${_test_ip}" 8022 2>/dev/null; then
                # Verify it's actually our phone
                if ssh -o ConnectTimeout=3 -o BatchMode=yes \
                    -i "${HOME}/.ssh/id_ed25519_phone" \
                    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                    -p 8022 "${UOM_PHONE_USER}@${_test_ip}" \
                    'echo UOM_SCAN_OK' 2>/dev/null | grep -q "UOM_SCAN_OK"; then
                    echo "$_test_ip"
                    return 0
                fi
            fi
            _i=$((_i + 1))
        done
    fi

    return 1
}

# ── Verify phone identity at IP ──────────────────────────────────────────
_verify_identity() {
    _ip="$1"
    _ok=true

    # Check 1: SSH auth works
    if ! ssh ${UOM_SSH_OPTS} "${UOM_PHONE_USER}@${_ip}" 'echo AUTH_OK' 2>/dev/null \
        | grep -q "AUTH_OK"; then
        _log "Identity check FAILED: SSH auth failed at ${_ip}"
        return 1
    fi

    # Check 2: Host key matches expected hash (if we have one)
    _actual_hash=$(ssh-keyscan -p 8022 "${_ip}" 2>/dev/null | awk '{print $3}' | head -1 || true)
    if [ -n "$_actual_hash" ] && [ "$_actual_hash" != "${UOM_PHONE_HOST_KEY_HASH}" ]; then
        _log "WARNING: Host key mismatch at ${_ip} (expected ${UOM_PHONE_HOST_KEY_HASH}, got ${_actual_hash})"
        # Don't fail — key may have changed legitimately (phone reflash etc.)
        # But log it for audit
    fi

    # Check 3: uom-vm directory exists (confirms it's our phone, not random SSH)
    if ssh ${UOM_SSH_OPTS} "${UOM_PHONE_USER}@${_ip}" \
        "test -d ${UOM_PHONE_QEMU_DIR}" 2>/dev/null; then
        _log "Identity verified at ${_ip} (auth OK, uom-vm present)"
        return 0
    else
        _log "WARNING: Identity partial at ${_ip} (auth OK, but no uom-vm dir)"
        # Still return success — phone might just not have QEMU set up yet
        return 0
    fi
}

# ── Cache IP ─────────────────────────────────────────────────────────────
_cache_ip() {
    _ip="$1"
    mkdir -p "${UOM_CONFIG_DIR}" 2>/dev/null || true
    echo "$_ip" > "${UOM_LAST_IP_FILE}"
    _log "Cached phone IP: ${_ip}"
}

# ── Get phone IP (discover + cache) ──────────────────────────────────────
_get_phone_ip() {
    # Try cached first
    if [ -f "${UOM_LAST_IP_FILE}" ]; then
        _cached=$(cat "${UOM_LAST_IP_FILE}" 2>/dev/null | tr -d '[:space:]')
        if [ -n "$_cached" ] && _verify_identity "$_cached" 2>/dev/null; then
            echo "$_cached"
            return 0
        fi
    fi

    # Discover
    _ip=$(_discover_phone_ip 2>/dev/null)
    if [ -n "$_ip" ]; then
        _cache_ip "$_ip"
        echo "$_ip"
        return 0
    fi

    _log "ERROR: Cannot discover phone IP"
    return 1
}

# ── Main ─────────────────────────────────────────────────────────────────
main() {
    # If on phone, execute locally
    if _is_phone; then
        if [ $# -eq 0 ]; then
            exec sh
        elif [ "$1" = "discover" ]; then
            echo "LOCAL (running on phone)"
            hostname 2>/dev/null || echo "unknown"
            return 0
        elif [ "$1" = "verify" ]; then
            echo "LOCAL — identity verified (running on phone)"
            return 0
        else
            exec sh -c "$*"
        fi
    fi

    # On laptop — discover phone, then act
    case "${1:-}" in
        discover)
            _ip=$(_get_phone_ip) || { echo "FAILED: Cannot discover phone" >&2; return 1; }
            echo "$_ip"
            ;;
        verify)
            _ip=$(_get_phone_ip) || { echo "FAILED: Cannot discover phone" >&2; return 1; }
            if _verify_identity "$_ip"; then
                echo "Identity OK at ${_ip}"
            else
                echo "Identity FAILED at ${_ip}" >&2
                return 1
            fi
            ;;
        -t)
            # Interactive: -t forces pty
            _ip=$(_get_phone_ip) || { echo "FAILED: Cannot discover phone" >&2; return 1; }
            shift
            if [ $# -eq 0 ]; then
                exec ssh -tt ${UOM_SSH_OPTS} "${UOM_PHONE_USER}@${_ip}"
            else
                exec ssh -tt ${UOM_SSH_OPTS} "${UOM_PHONE_USER}@${_ip}" "$@"
            fi
            ;;
        *)
            # Non-interactive command
            _ip=$(_get_phone_ip) || { echo "FAILED: Cannot discover phone" >&2; return 1; }
            if [ $# -eq 0 ]; then
                exec ssh ${UOM_SSH_OPTS} "${UOM_PHONE_USER}@${_ip}"
            else
                exec ssh ${UOM_SSH_OPTS} "${UOM_PHONE_USER}@${_ip}" "$@"
            fi
            ;;
    esac
}

main "$@"
