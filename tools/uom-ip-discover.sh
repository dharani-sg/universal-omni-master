#!/bin/sh
# tools/uom-ip-discover.sh — Dynamic IP discovery for UOM dual-agent
# Finds the other device using multiple methods.
# Works on both Alpine (laptop) and Termux (phone).
# Source: . tools/uom-ip-discover.sh
# Usage: _discover_phone_ip / _discover_laptop_ip

# ── Helper: try SSH reverse tunnel (laptop only, from phone side) ────────
_try_reverse_tunnel() {
    # Phone→laptop reverse tunnel: phone listens on laptop:18022→phone:8022
    # From laptop perspective: can reach phone at 127.0.0.1:18022
    # From phone perspective: can reach laptop via reverse tunnel too
    ssh -o ConnectTimeout=2 -o BatchMode=yes -p 18022 127.0.0.1 true 2>/dev/null && { echo "127.0.0.1:18022"; return 0; }
    return 1
}

# ── Helper: try mDNS ─────────────────────────────────────────────────────
_try_mdns_host() {
    # $1 = hostname (mi8.local or hp-pavilion.local)
    _host="$1"
    if command -v avahi-resolve >/dev/null 2>&1; then
        _ip=$(avahi-resolve -n "$_host" 2>/dev/null | awk '{print $2}' | head -1)
        [ -n "$_ip" ] && [ "$_ip" != "0.0.0.0" ] && echo "$_ip" && return 0
    fi
    # Fallback: ping mDNS hostname directly (works if nsswitch is configured)
    if ping -c 1 -W 2 "$_host" >/dev/null 2>&1; then
        # Get IP from ping output
        _ip=$(ping -c 1 -W 2 "$_host" 2>/dev/null | head -1 | sed 's/.*(\(.*\)).*/\1/')
        [ -n "$_ip" ] && echo "$_ip" && return 0
    fi
    return 1
}

# ── Helper: try last-known IP from state file ────────────────────────────
_try_last_known() {
    # $1 = path to IP state file (e.g., .uom-agent/phone.ip)
    _file="$1"
    if [ -f "$_file" ]; then
        _ip=$(cat "$_file" 2>/dev/null | tr -d '[:space:]')
        if [ -n "$_ip" ]; then
            # Strip port if present (127.0.0.1:18022 → 127.0.0.1)
            _host=$(echo "$_ip" | sed 's/:.*//')
            if ping -c 1 -W 2 "$_host" >/dev/null 2>&1; then
                echo "$_ip"; return 0
            fi
        fi
    fi
    return 1
}

# ── Helper: same-subnet scan ─────────────────────────────────────────────
_try_subnet_scan() {
    # $1 = port to scan, $2 = our subnet prefix (e.g., 192.168.40)
    _port="$1"; _prefix="$2"
    if command -v nmap >/dev/null 2>&1; then
        _found=$(nmap -p "$_port" --open -T4 "${_prefix}.0/24" 2>/dev/null \
            | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | while read _ip; do
                # Skip our own IP
                _my=$(ip route get 8.8.8.8 2>/dev/null | awk '/src/{print $7; exit}')
                [ "$_ip" != "$_my" ] && echo "$_ip" && break
            done)
        [ -n "$_found" ] && echo "$_found" && return 0
    fi
    return 1
}

# ── Helper: check SSH config for matching host ───────────────────────────
_try_ssh_config() {
    # $1 = SSH Host alias
    _alias="$1"
    if grep -q "^Host $_alias\$" ~/.ssh/config 2>/dev/null; then
        # Check if reachable
        ssh -o ConnectTimeout=3 -o BatchMode=yes -G "$_alias" >/dev/null 2>&1 && \
            echo "$_alias" && return 0
    fi
    return 1
}

# ══════════════════════════════════════════════════════════════════════════
# PUBLIC FUNCTIONS (source these from orchestrators)
# ══════════════════════════════════════════════════════════════════════════

discover_phone_ip() {
    # Returns: IP address or "host:port" string, empty on failure
    # Priority: reverse tunnel > mDNS > last-known > subnet scan

    # Method 1: reverse tunnel (always works if tunnel is up)
    _try_reverse_tunnel && return 0

    # Method 2: mDNS
    _try_mdns_host "mi8.local" && return 0

    # Method 3: last-known IP
    _try_last_known "${OMNI_ROOT:-.}/.uom-agent/phone.ip" && return 0

    # Method 4: SSH config aliases (try each)
    for _alias in uom-phone-rev uom-phone-lan uom-phone-mdns; do
        _try_ssh_config "$_alias" && return 0
    done

    # Method 5: subnet scan (slow, last resort)
    _my_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '/src/{print $7; exit}')
    if [ -n "$_my_ip" ]; then
        _subnet=$(echo "$_my_ip" | sed 's/\.[0-9]*$//')
        _try_subnet_scan 8022 "$_subnet" && return 0
    fi

    return 1
}

discover_laptop_ip() {
    # Returns: IP address or SSH alias, empty on failure
    # Priority: reverse tunnel > mDNS > last-known > subnet scan

    # Method 1: check if laptop is reachable via its own announce file
    _try_last_known "${OMNI_ROOT:-.}/.uom-agent/laptop.ip" && return 0

    # Method 2: mDNS
    _try_mdns_host "hp-pavilion.local" && return 0

    # Method 3: SSH config
    _try_ssh_config "uom-phone-rev" && return 0

    # Method 4: subnet scan for port 22
    _my_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '/src/{print $7; exit}')
    if [ -n "$_my_ip" ]; then
        _subnet=$(echo "$_my_ip" | sed 's/\.[0-9]*$//')
        _try_subnet_scan 22 "$_subnet" && return 0
    fi

    return 1
}

# ── Detect if we're on a phone hotspot ───────────────────────────────────
is_phone_hotspot() {
    # Returns 0 (true) if our default gateway is a phone hotspot
    _gw=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
    [ -z "$_gw" ] && return 1

    case "$_gw" in
        192.168.43.1) return 0 ;;  # Standard Android hotspot
        10.42.*.1)    return 0 ;;  # Ubuntu tethering
    esac

    # Check if gateway .1 on a typical hotspot range
    _gw_last=$(echo "$_gw" | sed 's/.*\.//')
    if [ "$_gw_last" = "1" ]; then
        _my_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '/src/{print $7; exit}')
        case "$_my_ip" in
            192.168.4[0-9].*) return 0 ;;
            192.168.1[0-9].*) return 0 ;;
            10.0.0.*)         return 0 ;;
        esac
    fi
    return 1
}

# ── Get our own IP ───────────────────────────────────────────────────────
get_my_ip() {
    ip route get 8.8.8.8 2>/dev/null | awk '/src/{print $7; exit}'
}

# ── Check network connectivity ───────────────────────────────────────────
net_ok() {
    ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 || \
    ping -c 1 -W 3 github.com >/dev/null 2>&1
}
