#!/bin/sh
# uom-widget-lib.sh — Backward-compatible wrapper for UOM widget scripts
# Sources the consolidated uom-lib.sh library.
# POSIX sh. No bashisms. Minimal environment safe.

# ── Environment hardening ──────────────────────────────────────────────
export PATH="/data/data/com.termux/files/usr/bin:${PATH}"
export HOME="${HOME:-/data/data/com.termux/files/home}"

# ── Source consolidated library ─────────────────────────────────────────
_UOM_LIB="${HOME}/bin/uom-lib.sh"
if [ -f "$_UOM_LIB" ]; then
    . "$_UOM_LIB"
else
    # Fallback: minimal inline helpers if lib not deployed
    UOM_QEMU_LAUNCHER="${HOME}/bin/uom-qemu-phone"
    UOM_GUEST_PORT="2222"
    UOM_GUEST_USER="uom"
    UOM_SSH_OPTS="-p ${UOM_GUEST_PORT} -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null"
    _uom_ts() { date +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || echo "unknown"; }
    _uom_log() { printf '[%s] [widget] %s\n' "$(_uom_ts)" "$*" >&2; }
    uom_qemu_running() {
        UOM_QEMU_PID=""; UOM_QEMU_TIER=""; UOM_QEMU_ADOPTED="no"
        _status_out=$("${UOM_QEMU_LAUNCHER}" status 2>/dev/null || true)
        if echo "$_status_out" | grep -q "RUNNING"; then
            UOM_QEMU_PID=$(echo "$_status_out" | grep "RUNNING" | sed -n 's/.*pid=\([^ ,]*\).*/\1/p' || true)
            UOM_QEMU_TIER="launcher"
            return 0
        fi
        return 1
    }
    uom_ensure_qemu() {
        if uom_qemu_running; then return 0; fi
        _uom_log "QEMU not running. Starting..."
        "${UOM_QEMU_LAUNCHER}" start 2>&1 || { _uom_log "ERROR: start failed"; return 1; }
        _count=0; while [ "$_count" -lt 60 ]; do
            if uom_guest_ssh 'echo OK' 2>/dev/null | grep -q "OK"; then return 0; fi
            sleep 3; _count=$((_count + 3))
        done; _uom_log "ERROR: SSH timeout"; return 1
    }
    uom_guest_ssh() { ssh ${UOM_SSH_OPTS} ${UOM_GUEST_USER}@127.0.0.1 "$@"; }
fi
