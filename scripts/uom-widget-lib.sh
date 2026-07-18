#!/bin/sh
# uom-widget-lib.sh — Shared helper for UOM Termux:Widget scripts
# Source this file: . "${HOME}/bin/uom-widget-lib.sh"
# POSIX sh. No bashisms. Minimal environment safe.

# ── Environment hardening ──────────────────────────────────────────────
export PATH="/data/data/com.termux/files/usr/bin:${PATH}"
export HOME="${HOME:-/data/data/com.termux/files/home}"

# ── Constants ───────────────────────────────────────────────────────────
UOM_QEMU_LAUNCHER="${HOME}/bin/uom-qemu-phone"
UOM_GUEST_PORT="2222"
UOM_GUEST_USER="uom"
UOM_SSH_OPTS="-p ${UOM_GUEST_PORT} -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null"

# ── Logging ─────────────────────────────────────────────────────────────
_uom_ts() { date +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || echo "unknown"; }
_uom_log() { printf '[%s] [widget] %s\n' "$(_uom_ts)" "$*" >&2; }

# ── QEMU state detection ───────────────────────────────────────────────
# Returns 0 if QEMU is running (any tier), 1 if stopped.
# Sets: UOM_QEMU_PID, UOM_QEMU_TIER, UOM_QEMU_ADOPTED
uom_qemu_running() {
    UOM_QEMU_PID=""
    UOM_QEMU_TIER=""
    UOM_QEMU_ADOPTED="no"

    # Use the launcher's 3-tier detection
    _status_out=$("${UOM_QEMU_LAUNCHER}" status 2>/dev/null || true)
    if echo "$_status_out" | grep -q "RUNNING"; then
        # Extract PID from status output
        UOM_QEMU_PID=$(echo "$_status_out" | grep "RUNNING" | sed -n 's/.*pid=\([^ ,]*\).*/\1/p' || true)
        UOM_QEMU_TIER="launcher"
        # Check if adopted
        if echo "$_status_out" | grep -q "Adopted: YES"; then
            UOM_QEMU_ADOPTED="yes"
        fi
        return 0
    fi
    return 1
}

# ── Ensure QEMU is running (start if not) ──────────────────────────────
# Returns 0 if running (started or already), 1 on failure.
uom_ensure_qemu() {
    if uom_qemu_running; then
        return 0
    fi
    _uom_log "QEMU not running. Starting..."
    "${UOM_QEMU_LAUNCHER}" start 2>&1 || {
        _uom_log "ERROR: QEMU start failed"
        # Print the last 5 lines of launcher log for debugging
        _logfile="${HOME}/uom-vm/logs/uom-phone-launcher.log"
        if [ -f "$_logfile" ]; then
            _uom_log "--- Launcher log (last 5 lines) ---"
            tail -5 "$_logfile" 2>/dev/null
        fi
        return 1
    }
    # Wait for SSH
    _uom_log "Waiting for guest SSH..."
    _count=0
    while [ "$_count" -lt 60 ]; do
        if uom_guest_ssh 'echo OK' 2>/dev/null | grep -q "OK"; then
            _uom_log "Guest SSH ready after ${_count}s"
            return 0
        fi
        sleep 3
        _count=$((_count + 3))
    done
    _uom_log "ERROR: Guest SSH timeout after 60s"
    return 1
}

# ── Guest SSH wrapper ───────────────────────────────────────────────────
# Usage: uom_guest_ssh 'command'
# Returns: stdout of the remote command
uom_guest_ssh() {
    ssh ${UOM_SSH_OPTS} ${UOM_GUEST_USER}@127.0.0.1 "$@"
}
