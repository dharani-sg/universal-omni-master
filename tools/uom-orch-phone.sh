#!/bin/sh
# tools/uom-orch-phone.sh — Phone watchdog + fallback orchestrator (dynamic IPs)
# Xiaomi Mi 8 / Termux / Android 15 / POSIX sh / BusyBox ash safe
# Auto-started via ~/.termux/boot/start-uom.sh

set -u
export OMNI_ROOT="${OMNI_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
export PATH="$HOME/go/bin:$HOME/bin:/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets"
. "$OMNI_ROOT/tools/uom-orch-state.sh"
. "$OMNI_ROOT/tools/uom-ip-discover.sh"

AGENT="phone"
LOOP_SLEEP=60
WATCHDOG_SLEEP=120
OPENCODE_TIMEOUT=2400
TAKEOVER_GRACE=300

_log() { printf '[%s] [PHONE] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

_announce_phone_ip() {
    _my_ip=$(get_my_ip)
    [ -z "$_my_ip" ] && return
    echo "$_my_ip" > "$OMNI_ROOT/.uom-agent/phone.ip"
}

# ── Dynamic laptop SSH target ────────────────────────────────────────────
_laptop_ssh_cmd() {
    # Priority: mDNS > last-known > subnet scan

    # Method 1: mDNS
    _laptop_ip=$(discover_laptop_ip) && {
        _host=$(echo "$_laptop_ip" | sed 's/:.*//')
        if [ "$_laptop_ip" = "$_host" ]; then
            # Plain IP — need to figure out port
            printf '%s' "ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new ${UOM_LAPTOP_USER:-alpine}@${_host}"
        else
            # host:port string
            _host2=$(echo "$_laptop_ip" | sed 's/:.*//')
            _port2=$(echo "$_laptop_ip" | sed 's/.*://')
            printf '%s' "ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -p ${_port2} ${UOM_LAPTOP_USER:-alpine}@${_host2}"
        fi
        return 0
    }

    # Method 2: SSH config alias
    if ssh -o ConnectTimeout=3 -o BatchMode=yes -G uom-laptop >/dev/null 2>&1; then
        printf '%s' "ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new uom-laptop"
        return 0
    fi

    # Method 3: try gateway (phone hotspot → laptop is on same subnet)
    _gw=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
    if [ -n "$_gw" ]; then
        # Try .100-.110 range (common for laptops on phone hotspot)
        _gw_base=$(echo "$_gw" | sed 's/\.[0-9]*$//')
        for _suffix in 100 101 102 103 104 105 106 107 108 109 110; do
            _cand="${_gw_base}.${_suffix}"
            if ping -c 1 -W 1 "$_cand" >/dev/null 2>&1; then
                # Check if it has SSH
                if nc -z -w 2 "$_cand" 22 2>/dev/null; then
                    printf '%s' "ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new ${UOM_LAPTOP_USER:-alpine}@${_cand}"
                    return 0
                fi
            fi
        done
    fi

    return 1
}

# ── Check if laptop is reachable (any method) ────────────────────────────
_laptop_reachable() {
    # Try mDNS
    if ping -c 1 -W 2 hp-pavilion.local >/dev/null 2>&1; then
        return 0
    fi
    # Try last-known IP
    _lip=$(cat "$OMNI_ROOT/.uom-agent/laptop.ip" 2>/dev/null)
    if [ -n "$_lip" ] && ping -c 1 -W 2 "$_lip" >/dev/null 2>&1; then
        return 0
    fi
    # Try laptop SSH (reverse tunnel)
    if ssh -o ConnectTimeout=2 -o BatchMode=yes -p 22 127.0.0.1 true 2>/dev/null; then
        return 0
    fi
    return 1
}

_run_opencode() {
    _task_id="$1"; _task_desc="$2"; _context="$3"
    _prompt="UOM project — PHONE FALLBACK AGENT (Xiaomi Mi 8 / Termux)
Task ID: $_task_id
Task: $_task_desc

POSIX-ONLY (non-negotiable): #!/bin/sh, zero bashisms, zero eval, BusyBox ash-safe.

${_context}

Implement the task. Output complete file paths and contents."

    printf '%s\n' "$_prompt" | timeout "$OPENCODE_TIMEOUT" opencode 2>&1
}

main() {
    _log "Phone Watchdog starting. OMNI_ROOT=$OMNI_ROOT"
    state_init
    _mode="watchdog"

    while true; do
        if ! net_ok; then
            _log "Offline. Waiting..."; sleep "$WATCHDOG_SLEEP"; continue
        fi

        state_git_pull
        _announce_phone_ip
        # Update phone heartbeat directly (avoid function-in-function POSIX issue)
        _now=$(date -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
        state_set "phone_heartbeat" "$_now"

        if [ "$_mode" = "watchdog" ]; then
            if state_laptop_stale; then
                _log "Laptop stale. Grace ${TAKEOVER_GRACE}s..."
                sleep "$TAKEOVER_GRACE"
                state_git_pull
                if state_laptop_stale; then
                    _log "TAKEOVER: laptop offline confirmed. Phone → PRIMARY."
                    _mode="active"
                    _c=$(state_get "takeover_count"); _c=$(( ${_c:-0} + 1 ))
                    state_set "takeover_count" "$_c"
                    state_git_sync "takeover: phone primary (count=$_c)"
                else
                    _log "Laptop returned during grace. Staying watchdog."
                fi
            else
                _log "Watchdog: laptop OK."
                state_git_sync "heartbeat: phone watchdog $(date -Iseconds)"
                sleep "$WATCHDOG_SLEEP"
            fi
            continue
        fi

        if [ "$_mode" = "active" ]; then
            if ! state_laptop_stale && _laptop_reachable; then
                _log "Laptop returned! Switching to handback."
                _mode="handback"; continue
            fi

            _task_id=$(state_next_task)
            if [ -z "$_task_id" ]; then
                _log "No tasks. Phone idle."; sleep "$LOOP_SLEEP"; continue
            fi

            _task_desc=$(state_task_desc "$_task_id")
            _context=$(state_task_context "$_task_id")
            _log "Phone taking: $_task_id"
            state_mark_task "$_task_id" "in_progress"
            state_set "current_task_id" "$_task_id"
            state_set "task_status" "in_progress"
            state_set "active_agent" "$AGENT"
            state_git_sync "start: $_task_id [$AGENT fallback]"

            _out="${TMPDIR:-/tmp}/uom-oc-phone-$$.txt"
            if _run_opencode "$_task_id" "$_task_desc" "$_context" > "$_out" 2>&1; then
                _log "Phone done: $_task_id"
                cp "$_out" "$OMNI_ROOT/.uom-agent/context/${_task_id}-output.md" 2>/dev/null
                state_mark_task "$_task_id" "done"
                state_set "task_status" "done"
                state_git_sync "done: $_task_id [$AGENT fallback]"
            else
                _rc=$?
                _log "Phone failed: $_task_id (rc=$_rc)"
                state_mark_task "$_task_id" "failed"
                state_set "task_status" "failed"
                state_git_sync "failed: $_task_id [$AGENT] rc=$_rc"
            fi
            rm -f "$_out"; sleep 5
        fi

        if [ "$_mode" = "handback" ]; then
            _log "Handback: waiting for laptop heartbeat..."
            state_git_pull
            if ! state_laptop_stale; then
                _log "Laptop confirmed via heartbeat. Phone → WATCHDOG."
                state_set "active_agent" "laptop"
                state_git_sync "handback: phone returned control to laptop"
                _mode="watchdog"
            else
                _log "Laptop still stale. Staying active."
                _mode="active"
            fi
            sleep "$LOOP_SLEEP"
        fi
    done
}

main "$@"
