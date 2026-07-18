#!/bin/sh
# NAME: uom-qemu-watchdog
# PURPOSE: Phone-side QEMU/guest health monitor and auto-repair
# VERSION: 2.1.0
# DEPENDS: uom-lib.sh, uom-qemu-phone, ps, awk, ssh, df
# SAFE: modifies-state (PID adoption, guest network repair only)
# TESTED: PASS 2026-07-18
#
# Runs in tmux window. Checks known failure patterns every 60 seconds.
# Exits when QEMU stops. Auto-repairs what it can, alerts on what it can't.
#
# Failure patterns detected:
#   P1: Stale PID file          → adopt correct PID
#   P2: Guest SSH failing       → check console, alert
#   P3: Guest network broken    → udhcpc repair
#   P4: Model API failing       → log, alert
#   P5: QEMU died               → restart or alert
#   P6: tmux session missing    → create recovery session
#   P7: Duplicate QEMU          → kill newest
#   P8: Memory pressure         → alert only
#   P9: Guest disk full         → alert only
#   P10: Model quota exhausted  → cooldown lockfile

# ── Configuration ───────────────────────────────────────────────────────
WATCHDOG_INTERVAL="${WATCHDOG_INTERVAL:-60}"
WATCHDOG_LOG="${HOME}/uom-vm/logs/watchdog.log"
COOLDOWN_FILE="${HOME}/uom-vm/locks/model-cooldown.lock"
AUTO_RESTART_QEMU="${AUTO_RESTART_QEMU:-0}"

# ── Source shared library ───────────────────────────────────────────────
_UOM_LIB="${HOME}/bin/uom-lib.sh"
if [ ! -f "$_UOM_LIB" ]; then
    echo "[watchdog] FATAL: uom-lib.sh not found at $_UOM_LIB" >&2
    exit 1
fi
. "$_UOM_LIB"
UOM_LOG_TAG="watchdog"

# ── Ensure directories ──────────────────────────────────────────────────
mkdir -p "${HOME}/uom-vm/logs" "${HOME}/uom-vm/locks" 2>/dev/null || true

# ── Singleton lock ──────────────────────────────────────────────────────
_LOCKDIR="${HOME}/uom-vm/locks/watchdog"
if ! mkdir "$_LOCKDIR" 2>/dev/null; then
    _old_pid=$(cat "$_LOCKDIR/pid" 2>/dev/null || echo "")
    if [ -n "$_old_pid" ] && kill -0 "$_old_pid" 2>/dev/null; then
        echo "[watchdog] Already running (PID $_old_pid)" >&2
        exit 0
    fi
    rm -rf "$_LOCKDIR" 2>/dev/null || true
    mkdir "$_LOCKDIR" 2>/dev/null || { echo "Cannot acquire lock"; exit 1; }
fi
echo $$ > "$_LOCKDIR/pid"
trap 'rm -rf "$_LOCKDIR"' EXIT INT TERM

# ── Logging ─────────────────────────────────────────────────────────────
_wd_log() {
    _ts=$(date +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || echo "unknown")
    printf '[%s] [watchdog] %s\n' "$_ts" "$*" | tee -a "$WATCHDOG_LOG" 2>/dev/null
}

# ── Notification (best-effort, Termux:API) ──────────────────────────────
_wd_notify() {
    _title="$1"
    _content="$2"
    if command -v termux-notification >/dev/null 2>&1; then
        termux-notification --title "$_title" --content "$_content" 2>/dev/null || true
    fi
}

# ── Main loop ───────────────────────────────────────────────────────────
_wd_log "WATCHDOG_START pid=$$ interval=${WATCHDOG_INTERVAL}s"

while true; do
    LOOP_START=$(date +%s 2>/dev/null || echo 0)

    # ── P5: QEMU died — check first, most critical ─────────────────────
    if ! uom_qemu_running; then
        _wd_log "P5: QEMU_DIED — process not found"
        CONSOLE_TAIL=$(tail -20 "${HOME}/uom-vm/logs/uom-phone-console.log" 2>/dev/null || echo "(no log)")
        _wd_log "CONSOLE_TAIL: $CONSOLE_TAIL"
        if [ "${AUTO_RESTART_QEMU}" = "1" ]; then
            _wd_log "AUTO_RESTART: waiting 30s then restarting"
            sleep 30
            "${UOM_QEMU_LAUNCHER}" start 2>&1 | while read -r _line; do
                _wd_log "RESTART: $_line"
            done
            if uom_wait_guest_ssh 60; then
                _wd_log "AUTO_RESTART: guest SSH ready"
            else
                _wd_log "AUTO_RESTART: guest SSH timeout"
            fi
        else
            _wd_log "AUTO_RESTART_DISABLED: manual restart required"
            _wd_notify "UOM: QEMU died" "QEMU stopped unexpectedly. Tap to open Termux."
        fi
        break
    fi

    # ── P1: Stale PID file — already handled by uom_qemu_running adoption
    # If we get here, PID file is current (adopted if needed)

    # ── P7: Duplicate QEMU ─────────────────────────────────────────────
    # Only count actual qemu-system-aarch64 processes (field 8 in ps -ef),
    # not tmux/bash wrappers that have qemu in their arguments.
    QEMU_COUNT=$(ps -ef 2>/dev/null | awk '$8 == "qemu-system-aarch64"' | grep -c "qemu-system-aarch64" || echo 0)
    if [ "$QEMU_COUNT" -gt 1 ]; then
        _wd_log "P7: DUPLICATE_QEMU count=$QEMU_COUNT"
        # Find the oldest actual QEMU process (the correct one to keep)
        OLDEST=$(ps -ef 2>/dev/null | awk '$8 == "qemu-system-aarch64" {print $2}' | sort -n | head -1)
        # Kill all except the oldest
        ps -ef 2>/dev/null | awk '$8 == "qemu-system-aarch64" {print $2}' | sort -n | tail -n +2 | while read _dup_pid; do
            if [ "$_dup_pid" != "$OLDEST" ]; then
                _wd_log "P7: killing duplicate PID=$_dup_pid keeping PID=$OLDEST"
                kill "$_dup_pid" 2>/dev/null || true
            fi
        done
    fi

    # ── P8: Memory pressure (phone host) ───────────────────────────────
    MEM_AVAIL=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null || echo 999999)
    if [ "$MEM_AVAIL" -lt 204800 ]; then
        _wd_log "P8: MEMORY_PRESSURE avail=${MEM_AVAIL}kB"
        _wd_notify "UOM: Low memory" "Phone RAM critical (${MEM_AVAIL}kB avail). Close other apps."
    fi

    # ── P2 + P3 + P9: Guest health (only if QEMU running) ─────────────
    if uom_qemu_running; then
        # P2: Guest SSH check
        if ! uom_guest_ssh_test 3 5; then
            _wd_log "P2: GUEST_SSH_FAILING — checking console"
            CONSOLE_TAIL=$(tail -10 "${HOME}/uom-vm/logs/uom-phone-console.log" 2>/dev/null || echo "(no log)")
            _wd_log "CONSOLE: $CONSOLE_TAIL"
            # Wait and retry — guest may be rebooting
            sleep 30
            if ! uom_guest_ssh_test 3 10; then
                _wd_log "P2: GUEST_SSH_DEAD after retry"
                _wd_notify "UOM: Guest SSH failed" "Guest unresponsive. Check 40-UOM-Host-Console."
            fi
        else
            # P3: Guest network
            GUEST_NET=$(uom_guest_ssh "ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 && echo OK || echo FAIL" 2>/dev/null || echo "FAIL")
            if [ "$GUEST_NET" = "FAIL" ]; then
                _wd_log "P3: GUEST_NETWORK_DOWN — attempting repair"
                uom_guest_ssh "ip link set eth0 up && udhcpc -i eth0 -t 10 -n 2>/dev/null || true" 2>/dev/null || true
                _wd_log "P3: network repair attempted"
            fi

            # P9: Guest disk usage
            DISK_USE=$(uom_guest_ssh "df / | awk 'NR==2{print \$5}' | tr -d '%'" 2>/dev/null || echo "")
            if [ -n "$DISK_USE" ] && [ "$DISK_USE" -gt 90 ] 2>/dev/null; then
                _wd_log "P9: GUEST_DISK_WARNING use=${DISK_USE}%"
                _wd_notify "UOM: Guest disk full" "Root partition ${DISK_USE}% used."
            fi
        fi

        # P10: Model quota exhaustion (check usage log)
        ZEN_LOG="${HOME}/.config/uom/zen-usage.log"
        if [ -f "$ZEN_LOG" ]; then
            RECENT_FAILS=$(tail -20 "$ZEN_LOG" 2>/dev/null | grep -c "ERROR\|429\|EXHAUSTED" || echo 0)
            if [ "$RECENT_FAILS" -gt 5 ]; then
                _wd_log "P10: MODEL_QUADOWN failures=$RECENT_FAILS (last 20 entries)"
                touch "$COOLDOWN_FILE" 2>/dev/null || true
            fi
        fi
    fi

    # ── P6: tmux session check ─────────────────────────────────────────
    if uom_qemu_running && ! tmux has-session -t "${UOM_TMUX_SESSION}" 2>/dev/null; then
        _wd_log "P6: QEMU running but tmux session ${UOM_TMUX_SESSION} missing"
        tmux new-session -d -s "${UOM_TMUX_SESSION}" -n console 2>/dev/null || true
        tmux send-keys -t "${UOM_TMUX_SESSION}:console" \
            "tail -f ${HOME}/uom-vm/logs/uom-phone-console.log" Enter 2>/dev/null || true
        _wd_log "P6: created recovery tmux session"
    fi

    # ── Sleep until next interval ───────────────────────────────────────
    LOOP_END=$(date +%s 2>/dev/null || echo 0)
    ELAPSED=$((LOOP_END - LOOP_START))
    SLEEP_TIME=$((WATCHDOG_INTERVAL - ELAPSED))
    [ "$SLEEP_TIME" -gt 0 ] && sleep "$SLEEP_TIME" || sleep 10
done

_wd_log "WATCHDOG_EXIT pid=$$"
