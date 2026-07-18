#!/bin/sh
# orchestrators/uom-watchdog.sh — Phone-side laptop reachability monitor
# Checks heartbeat, tunnel health, and direct reachability.
# Triggers phone takeover after sustained consecutive failures.
# Usage: sh uom-watchdog.sh [--loop [interval_seconds]]

set -eu

_LOCK_DIR="/tmp/.uom_watchdog_lock"
if ! mkdir "$_LOCK_DIR" 2>/dev/null; then
    if [ -f "$_LOCK_DIR/pid" ]; then
        _old=$(cat "$_LOCK_DIR/pid" 2>/dev/null)
        if [ -n "$_old" ] && kill -0 "$_old" 2>/dev/null; then
            printf '[watchdog] already running (PID %s)\n' "$_old" >&2
            exit 1
        fi
    fi
    rm -rf "$_LOCK_DIR" 2>/dev/null || true
    mkdir "$_LOCK_DIR" 2>/dev/null || { echo "Cannot acquire lock"; exit 1; }
fi
echo $$ > "$_LOCK_DIR/pid"
trap 'rm -rf "$_LOCK_DIR"' EXIT INT TERM

# ── Resolve and source state library ────────────────────────────────────────
_SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
_UOM_DIR="$(cd "$_SELF_DIR/.." 2>/dev/null && pwd)"
. "${_UOM_DIR}/tools/uom-state-lib.sh"
uom_state_init

# ── Configuration via environment ──────────────────────────────────────────
WATCHDOG_INTERVAL="${UOM_WATCHDOG_INTERVAL:-30}"
FAIL_THRESHOLD="${UOM_FAIL_THRESHOLD:-6}"
LAPTOP_STALE_SECS="${UOM_LAPTOP_STALE_SECONDS:-300}"
TUNNEL_PORT="${UOM_TUNNEL_PORT:-31415}"

# ── Paths ──────────────────────────────────────────────────────────────────
FAIL_COUNT_FILE="${UOM_RUNTIME_DIR}/watchdog.fail-count"
LOG_FILE="${UOM_LOG_DIR}/watchdog.log"
SOLO_PID_FILE="${UOM_RUNTIME_DIR}/solo-orchestrator.pid"

mkdir -p "$UOM_RUNTIME_DIR" "$UOM_LOG_DIR"

# ── Logging ────────────────────────────────────────────────────────────────
_wlog() {
    _ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)"
    printf '[watchdog] %s %s\n' "$_ts" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

# ── Fail counter helpers ───────────────────────────────────────────────────
_get_fail_count() {
    if [ -f "$FAIL_COUNT_FILE" ]; then
        _fc=$(cat "$FAIL_COUNT_FILE" 2>/dev/null)
        if [ "${_fc:-0}" -ge 0 ] 2>/dev/null; then
            printf '%s\n' "$_fc"
            return
        fi
    fi
    printf '0\n'
}

_set_fail_count() {
    printf '%s\n' "$1" > "$FAIL_COUNT_FILE"
}

_reset_fail_count() {
    _old=$(_get_fail_count)
    if [ "${_old}" -ne 0 ] 2>/dev/null; then
        _set_fail_count 0
        _wlog "failure counter reset (was ${_old})"
    fi
}

# ── Laptop reachability checks ────────────────────────────────────────────

_check_heartbeat() {
    # Returns 0 if heartbeat is fresh, 1 if absent/stale/malformed
    if ! uom_heartbeat_read laptop "$LAPTOP_STALE_SECS"; then
        return 1
    fi
    return 0
}

_check_tunnel() {
    # Returns 0 if reverse tunnel SSH probe succeeds
    ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=no \
        -p "$TUNNEL_PORT" 127.0.0.1 true 2>/dev/null
}

_check_direct_ping() {
    # Returns 0 if we can reach laptop IP directly
    _laptop_ip=""
    if [ -f "${UOM_REPO_ROOT}/.uom-agent/laptop.ip" ]; then
        _laptop_ip=$(cat "${UOM_REPO_ROOT}/.uom-agent/laptop.ip" 2>/dev/null)
    fi
    if [ -z "$_laptop_ip" ]; then
        return 1
    fi
    ping -c 1 -W 3 "$_laptop_ip" >/dev/null 2>&1
}

_check_mdns() {
    # Returns 0 if mDNS resolves laptop hostname
    _mdns_host="${UOM_MDNS_HOST:-laptop.local}"
    ping -c 1 -W 3 "$_mdns_host" >/dev/null 2>&1
}

_check_direct_reachability() {
    # Returns 0 if either direct IP ping or mDNS works
    if _check_direct_ping; then
        return 0
    fi
    if _check_mdns; then
        return 0
    fi
    return 1
}

_laptop_is_reachable() {
    # Returns 0 if heartbeat, tunnel, or direct reachability is OK
    if _check_heartbeat; then
        return 0
    fi
    if _check_tunnel; then
        return 0
    fi
    if _check_direct_reachability; then
        return 0
    fi
    return 1
}

# ── All three failure conditions ───────────────────────────────────────────
_all_conditions_failing() {
    # Returns 0 only if heartbeat stale AND tunnel down AND direct unreachable
    if _check_heartbeat; then
        return 1
    fi
    if _check_tunnel; then
        return 1
    fi
    if _check_direct_reachability; then
        return 1
    fi
    return 0
}

# ── Laptop return reachability ─────────────────────────────────────────────
_laptop_return_reachable() {
    # Returns 0 if any of: tunnel, direct IP, mDNS succeeds
    if _check_tunnel; then
        return 0
    fi
    if _check_direct_ping; then
        return 0
    fi
    if _check_mdns; then
        return 0
    fi
    return 1
}

# ── IP change detection ────────────────────────────────────────────────
_IP_CACHE_FILE="${UOM_RUNTIME_DIR}/watchdog.last-laptop-ip"

_check_ip_changed() {
    _cur_laptop_ip=""
    if [ -f "${UOM_REPO_ROOT}/.uom-agent/laptop.ip" ]; then
        _cur_laptop_ip=$(cat "${UOM_REPO_ROOT}/.uom-agent/laptop.ip" 2>/dev/null | tr -d '[:space:]')
    fi
    [ -z "$_cur_laptop_ip" ] && return 1

    _prev_ip=""
    if [ -f "$_IP_CACHE_FILE" ]; then
        _prev_ip=$(cat "$_IP_CACHE_FILE" 2>/dev/null | tr -d '[:space:]')
    fi

    if [ "$_cur_laptop_ip" != "$_prev_ip" ]; then
        printf '%s\n' "$_cur_laptop_ip" > "$_IP_CACHE_FILE"
        _wlog "laptop IP changed: ${_prev_ip:-<none>} -> $_cur_laptop_ip"
        return 0
    fi
    return 1
}

# ── Tunnel auto-restart on drift ──────────────────────────────────────
_restart_tunnel() {
    _wlog "attempting tunnel restart"
    _tunnel_script="${_UOM_DIR}/bin/uom-reverse-ssh.sh"
    if [ ! -x "$_tunnel_script" ]; then
        _wlog "tunnel script not found: $_tunnel_script"
        return 1
    fi
    # Stop existing tunnel
    sh "$_tunnel_script" stop 2>/dev/null || true
    sleep 2
    # Start new tunnel
    nohup sh "$_tunnel_script" start >> "$LOG_FILE" 2>&1 &
    _npid=$!
    _wlog "tunnel restart initiated (PID $_npid)"
    # Wait briefly for tunnel to establish
    _w=0
    while [ "$_w" -lt 10 ]; do
        sleep 1; _w=$((_w + 1))
        if _check_tunnel; then
            _wlog "tunnel restart succeeded after ${_w}s"
            return 0
        fi
    done
    _wlog "tunnel restart may have failed (not reachable after 10s)"
    return 1
}

# ── Hotspot mode detection ─────────────────────────────────────────────
_check_hotspot_mode() {
    # Returns 0 if this phone is acting as a hotspot (laptop tethered to us)
    _gw=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
    [ -z "$_gw" ] && return 1
    case "$_gw" in
        192.168.43.1) return 0 ;;  # Standard Android hotspot
        10.42.*.1)    return 0 ;;  # Ubuntu tethering
    esac
    _my_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '/src/{print $7; exit}')
    _gw_last=$(echo "$_gw" | sed 's/.*\.//')
    if [ "$_gw_last" = "1" ]; then
        case "${_my_ip:-}" in
            192.168.4[0-9].*) return 0 ;;
            192.168.1[0-9].*) return 0 ;;
            10.0.0.*)         return 0 ;;
        esac
    fi
    return 1
}

# ── Wake-lock (Android/Termux only) ────────────────────────────────────
_acquire_wakelock() {
    if [ "$(uname -o 2>/dev/null)" != "Android" ]; then
        return 0
    fi
    if command -v termux-wake-lock >/dev/null 2>&1; then
        termux-wake-lock 2>/dev/null || true
        _wlog "wake-lock acquired"
    fi
}

_release_wakelock() {
    if [ "$(uname -o 2>/dev/null)" != "Android" ]; then
        return 0
    fi
    if command -v termux-wake-unlock >/dev/null 2>&1; then
        termux-wake-unlock 2>/dev/null || true
        _wlog "wake-lock released"
    fi
}

# ── Phone announce (write current IP to state) ─────────────────────────
_phone_announce() {
    _my_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '/src/{print $7; exit}')
    if [ -n "${_my_ip:-}" ]; then
        printf '%s\n' "$_my_ip" > "${UOM_REPO_ROOT}/.uom-agent/phone.ip" 2>/dev/null || true
    fi
}

# ── Generate pseudo-random lease ID ────────────────────────────────────────
_gen_lease_id() {
    _now=$(uom_now_epoch)
    _rand=""
    if [ -f /dev/urandom ]; then
        _rand=$(od -An -tu4 -N4 /dev/urandom 2>/dev/null | tr -d ' ')
    fi
    printf 'lease-%s-%s' "$_now" "${_rand:-$$}"
}

# ── Solo orchestrator lifecycle ────────────────────────────────────────────
_start_solo_orchestrator() {
    if [ -f "$SOLO_PID_FILE" ]; then
        _opid=$(cat "$SOLO_PID_FILE" 2>/dev/null)
        if [ -n "$_opid" ] && kill -0 "$_opid" 2>/dev/null; then
            _wlog "solo orchestrator already running (PID $_opid)"
            return 0
        fi
        rm -f "$SOLO_PID_FILE"
    fi
    _wlog "launching solo orchestrator"
    nohup sh "${_UOM_DIR}/orchestrators/uom-solo-orchestrator.sh" >> "$LOG_FILE" 2>&1 &
    _npid=$!
    printf '%s\n' "$_npid" > "$SOLO_PID_FILE"
    _wlog "solo orchestrator started (PID $_npid)"
}

_stop_solo_orchestrator() {
    if [ ! -f "$SOLO_PID_FILE" ]; then
        return 0
    fi
    _opid=$(cat "$SOLO_PID_FILE" 2>/dev/null)
    if [ -n "$_opid" ] && kill -0 "$_opid" 2>/dev/null; then
        kill "$_opid" 2>/dev/null || true
        # Brief wait for graceful shutdown
        _wait=0
        while [ "$_wait" -lt 5 ] && kill -0 "$_opid" 2>/dev/null; do
            sleep 1
            _wait=$((_wait + 1))
        done
        if kill -0 "$_opid" 2>/dev/null; then
            kill -9 "$_opid" 2>/dev/null || true
        fi
        _wlog "solo orchestrator (PID $_opid) stopped"
    fi
    rm -f "$SOLO_PID_FILE"
}

# ── Takeover: transition to phone-solo ─────────────────────────────────────
_do_takeover() {
    _cur_mode=$(uom_state_get "active_agent")
    _cur_epoch=$(uom_state_get "ownership_epoch")
    _cur_takeover=$(uom_state_get "takeover_count")

    # Already phone-solo: do NOT increment takeover_count again
    if [ "$_cur_mode" = "phone-solo" ]; then
        _wlog "already phone-solo, skipping takeover (epoch=$_cur_epoch, takeover_count=$_cur_takeover)"
        return 0
    fi

    _lease=$(_gen_lease_id)
    _reason="laptop-unreachable: heartbeat stale, tunnel down, direct unreachable"
    _now_utc=$(uom_now_utc)

    if uom_state_compare_and_update "$_cur_mode" "$_cur_epoch" \
        '.active_agent = "phone-solo" |
         .writer_role = "phone" |
         .takeover_count = (.takeover_count | if type == "string" then tonumber else . end) + 1 |
         .lease_id = $lease |
         .task_status = (if .task_status == "in_progress" then "in_progress" else "idle" end) |
         .last_transition = $reason |
         .last_transition_at = $now' \
        --arg lease "$_lease" --arg now "$_now_utc"; then
        _wlog "TAKEOVER committed: phone-solo epoch=$((_cur_epoch + 1)) lease=$_lease"
        _acquire_wakelock
        _start_solo_orchestrator
        return 0
    else
        _wlog "TAKEOVER failed: compare-and-update rejected (concurrent change?)"
        return 1
    fi
}

# ── Laptop return: transition to dual-pending ──────────────────────────────
_do_laptop_return() {
    _cur_mode=$(uom_state_get "active_agent")
    _cur_epoch=$(uom_state_get "ownership_epoch")

    if [ "$_cur_mode" != "phone-solo" ]; then
        return 0
    fi

    _wlog "laptop return detected during phone-solo, transitioning to dual-pending"

    # Checkpoint in-progress task
    _task_status=$(uom_state_get "task_status")
    _task_id=$(uom_state_get "current_task_id")
    if [ "$_task_status" = "in_progress" ] && [ -n "$_task_id" ]; then
        _wlog "checkpointing task $_task_id"
        # Set checkpoint_ref to signal the task was interrupted
        _ckpt_ref="checkpoint-${_task_id}-$(uom_now_epoch)"
    else
        _ckpt_ref=""
    fi

    _now_utc=$(uom_now_utc)

    # Use compare-and-update to atomically transition
    if uom_state_compare_and_update "$_cur_mode" "$_cur_epoch" \
        '.active_agent = "dual-pending" |
         .writer_role = "none" |
         .task_status = (if .task_status == "in_progress" then "checkpointed" else .task_status end) |
         .checkpoint_ref = $ckpt |
         .last_transition = "laptop-returned" |
         .last_transition_at = $now' \
        --arg ckpt "$_ckpt_ref" --arg now "$_now_utc"; then
        _wlog "transitioned to dual-pending (epoch=$((_cur_epoch + 1)))"
        _stop_solo_orchestrator
        _release_wakelock
        _wlog "NOTIFY: laptop returned — in dual-pending, awaiting laptop confirmation"
    else
        _wlog "dual-pending transition failed (concurrent change?)"
    fi
}

# ── Single check pass ─────────────────────────────────────────────────────
_check_once() {
    _cur_mode=$(uom_state_get "active_agent")

    # Announce phone IP each cycle
    _phone_announce

    # Check for IP drift — if laptop IP changed, restart tunnel
    if _check_ip_changed; then
        _wlog "IP drift detected, restarting tunnel"
        _restart_tunnel || true
    fi

    # Check if we're in hotspot mode (laptop may be tethered to us)
    if _check_hotspot_mode; then
        _wlog "hotspot mode detected — laptop reachable via gateway"
    fi

    if _laptop_is_reachable; then
        # Laptop is reachable
        _reset_fail_count

        if [ "$_cur_mode" = "phone-solo" ]; then
            _do_laptop_return
        fi
        return 0
    fi

    # Laptop not reachable — check if all three conditions are failing
    if ! _all_conditions_failing; then
        # One of the reachability methods partially works (e.g. heartbeat stale
        # but tunnel is up). Reset counter — we don't trigger on partial failure.
        _reset_fail_count
        _wlog "partial failure: at least one reachability path works, no escalation"
        return 0
    fi

    # All three conditions are failing — increment counter
    _fc=$(_get_fail_count)
    _fc=$((_fc + 1))
    _set_fail_count "$_fc"
    _wlog "all conditions failing, consecutive count: $_fc/$FAIL_THRESHOLD"

    if [ "$_fc" -ge "$FAIL_THRESHOLD" ]; then
        if [ "$_cur_mode" = "phone-solo" ]; then
            # Already in phone-solo — do nothing, don't re-increment takeover_count
            _wlog "threshold reached but already phone-solo (epoch=$(uom_state_get ownership_epoch))"
            return 0
        fi
        _wlog "threshold reached — initiating takeover"
        _do_takeover
    fi
}

# ── Parse arguments ────────────────────────────────────────────────────────
_LOOP_MODE=0

case "${1:-}" in
    --loop)
        _LOOP_MODE=1
        shift
        if [ "${1:-}" -ge 0 ] 2>/dev/null; then
            WATCHDOG_INTERVAL="$1"
            shift
        fi
        ;;
    --help|-h)
        printf 'Usage: %s [--loop [interval_seconds]]\n' "$0"
        printf '  Single check (default), or loop with configurable interval.\n'
        printf 'Environment:\n'
        printf '  UOM_WATCHDOG_INTERVAL=%s  (loop sleep seconds)\n' "$WATCHDOG_INTERVAL"
        printf '  UOM_FAIL_THRESHOLD=%s     (consecutive failures before takeover)\n' "$FAIL_THRESHOLD"
        printf '  UOM_LAPTOP_STALE_SECONDS=%s (heartbeat max age)\n' "$LAPTOP_STALE_SECS"
        exit 0
        ;;
    '')
        ;;
    *)
        printf 'Unknown option: %s\n' "$1" >&2
        exit 1
        ;;
esac

# ── Main ───────────────────────────────────────────────────────────────────
if [ "$_LOOP_MODE" -eq 1 ]; then
    _wlog "watchdog loop starting (interval=${WATCHDOG_INTERVAL}s, threshold=$FAIL_THRESHOLD, stale=${LAPTOP_STALE_SECS}s)"
    trap '_wlog "watchdog loop exiting"; _release_wakelock; exit 0' INT TERM
    while true; do
        _check_once
        sleep "$WATCHDOG_INTERVAL"
    done
else
    _check_once
fi
