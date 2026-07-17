#!/bin/sh
# tools/uom-net-detect.sh — Dynamic network detection for UOM dual-agent
# Detects: hotspot | lan | external | offline
# Outputs shell-eval-safe KEY=VALUE lines (no hardcoded IPs)
# Source from orchestrators: eval "$(sh tools/uom-net-detect.sh)"

# ── Detect local IP and gateway ──────────────────────────────────────────
_gw=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
_my_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '/src/{print $7; exit}')

if [ -z "$_gw" ] || [ -z "$_my_ip" ]; then
    printf 'NET_MODE=offline\n'
    exit 0
fi

# ── Detect network segment from local IP ─────────────────────────────────
# Extract first 3 octets of our IP for subnet matching
_my_subnet=$(echo "$_my_ip" | sed 's/\.[0-9]*$//')

# ── Phone hotspot detection ──────────────────────────────────────────────
# Android hotspots use 192.168.43.x (default) or 192.168.x.1 patterns
# Gateway .1 with a /24 on a non-standard subnet = likely phone hotspot
_is_hotspot=0
case "$_gw" in
    192.168.43.1) _is_hotspot=1 ;;  # Standard Android hotspot
    10.42.*.1)    _is_hotspot=1 ;;  # Ubuntu tethering
esac
# Also check: if gateway is .1 and our IP is in a common hotspot range
if [ "$_is_hotspot" -eq 0 ]; then
    _gw_last=$(echo "$_gw" | sed 's/.*\.//')
    if [ "$_gw_last" = "1" ]; then
        # Check if we're in a typical phone tethering range
        case "$_my_ip" in
            192.168.4[0-9].*)  _is_hotspot=1 ;;
            192.168.1[0-9].*)  _is_hotspot=1 ;;
            10.0.0.*)          _is_hotspot=1 ;;
        esac
    fi
fi

# ── Discover phone IP via multiple methods ───────────────────────────────
_discover_phone_ip() {
    # Method 1: Gateway IS the phone (hotspot mode)
    if [ "$_is_hotspot" -eq 1 ]; then
        echo "$_gw"; return 0
    fi

    # Method 2: Reverse tunnel (always localhost:31415)
    if ssh -o ConnectTimeout=2 -o BatchMode=yes -p 31415 127.0.0.1 true 2>/dev/null; then
        echo "127.0.0.1:31415"; return 0
    fi

    # Method 3: mDNS resolution
    if command -v avahi-resolve >/dev/null 2>&1; then
        _mdns_ip=$(avahi-resolve -n mi8.local 2>/dev/null | awk '{print $2}' | head -1)
        [ -n "$_mdns_ip" ] && [ "$_mdns_ip" != "0.0.0.0" ] && echo "$_mdns_ip" && return 0
    fi

    # Method 4: Last known from .uom-agent state
    _repo="${OMNI_ROOT:-.}"
    if [ -f "$_repo/.uom-agent/phone.ip" ]; then
        _last_ip=$(cat "$_repo/.uom-agent/phone.ip" 2>/dev/null)
        if [ -n "$_last_ip" ] && ping -c 1 -W 2 "$_last_ip" >/dev/null 2>&1; then
            echo "$_last_ip"; return 0
        fi
    fi

    # Method 5: Same subnet scan for port 8022 (brute but reliable)
    if command -v nmap >/dev/null 2>&1; then
        _found=$(nmap -p 8022 --open -T4 "${_my_subnet}.0/24" 2>/dev/null \
            | grep -oP '\d+\.\d+\.\d+\.\d+(?=.8022)' | head -1)
        [ -n "$_found" ] && echo "$_found" && return 0
    fi

    # Method 6: Check SSH known_hosts for phone connections
    if [ -f ~/.ssh/known_hosts_uom ]; then
        _kh_ip=$(grep -oP '\d+\.\d+\.\d+\.\d+' ~/.ssh/known_hosts_uom 2>/dev/null | head -1)
        [ -n "$_kh_ip" ] && ping -c 1 -W 2 "$_kh_ip" >/dev/null 2>&1 && echo "$_kh_ip" && return 0
    fi

    return 1
}

# ── Discover laptop IP ───────────────────────────────────────────────────
_discover_laptop_ip() {
    # Method 1: Gateway IS the laptop (hotspot from phone → laptop is gateway... no)
    # Method 2: Last known
    _repo="${OMNI_ROOT:-.}"
    if [ -f "$_repo/.uom-agent/laptop.ip" ]; then
        _last_ip=$(cat "$_repo/.uom-agent/laptop.ip" 2>/dev/null)
        if [ -n "$_last_ip" ] && ping -c 1 -W 2 "$_last_ip" >/dev/null 2>&1; then
            echo "$_last_ip"; return 0
        fi
    fi

    # Method 3: mDNS
    if command -v avahi-resolve >/dev/null 2>&1; then
        _mdns_ip=$(avahi-resolve -n hp-pavilion.local 2>/dev/null | awk '{print $2}' | head -1)
        [ -n "$_mdns_ip" ] && [ "$_mdns_ip" != "0.0.0.0" ] && echo "$_mdns_ip" && return 0
    fi

    # Method 4: SSH config has the reverse tunnel entry
    # Laptop is always reachable via 127.0.0.1:22 if tunnel is up
    if ssh -o ConnectTimeout=2 -o BatchMode=yes -p 22 127.0.0.1 true 2>/dev/null; then
        echo "127.0.0.1"; return 0
    fi

    # Method 5: Same subnet scan for port 22
    if command -v nmap >/dev/null 2>&1; then
        _found=$(nmap -p 22 --open -T4 "${_my_subnet}.0/24" 2>/dev/null \
            | grep -oP '\d+\.\d+\.\d+\.\d+(?=.22)' | head -1)
        [ -n "$_found" ] && echo "$_found" && return 0
    fi

    return 1
}

# ── Determine mode and output ────────────────────────────────────────────
if [ "$_is_hotspot" -eq 1 ]; then
    _phone_ip="$_gw"
    _laptop_ip="$_my_ip"
    printf 'NET_MODE=hotspot\n'
    printf 'PHONE_IP=%s\n' "$_phone_ip"
    printf 'LAPTOP_IP=%s\n' "$_laptop_ip"
    printf 'LAPTOP_USER=%s\n' "${UOM_LAPTOP_USER:-alpine}"
else
    # Same subnet as laptop? Or different network?
    _phone_ip=$(_discover_phone_ip 2>/dev/null) || _phone_ip=""
    _laptop_ip=$(_discover_laptop_ip 2>/dev/null) || _laptop_ip=""

    if [ -n "$_laptop_ip" ] && [ -n "$_phone_ip" ]; then
        printf 'NET_MODE=lan\n'
    else
        printf 'NET_MODE=external\n'
    fi
    [ -n "$_phone_ip" ] && printf 'PHONE_IP=%s\n' "$_phone_ip"
    [ -n "$_laptop_ip" ] && printf 'LAPTOP_IP=%s\n' "$_laptop_ip"
    printf 'LAPTOP_USER=%s\n' "${UOM_LAPTOP_USER:-alpine}"
    printf 'GATEWAY=%s\n' "$_gw"
fi
