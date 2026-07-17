#!/bin/sh
# bin/uom-port-guardian.sh — Dynamic host/port sentinel (guardian) for UOM
# Runs in the background and continuously watches for:
#   * the phone (Termux) changing its sshd port
#   * the laptop changing its IP because it hops between the phone hotspot
#     and other WiFi sources
# When drift is detected it re-points the reverse tunnel (uom-reverse-ssh.sh)
# and rewrites the relevant ~/.ssh/config entries, then signals the hybrid
# orchestrator to re-evaluate (it fails closed until a stable target exists).
#
# Usage:
#   sh bin/uom-port-guardian.sh start        # launch as background daemon (tmux)
#   sh bin/uom-port-guardian.sh stop         # stop daemon
#   sh bin/uom-port-guardian.sh status       # running? last-seen targets?
#   sh bin/uom-port-guardian.sh once         # one reconciliation pass (no loop)
#   sh bin/uom-port-guardian.sh --loop [s]   # foreground loop (interval secs)
#   sh bin/uom-port-guardian.sh dryrun       # self-test the watch primitives
#
# POSIX sh, no bashisms, no eval. Safe to dry-run.

set -u

UOM_DIR="${OMNI_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
. "${UOM_DIR}/tools/uom-port-watch.sh" 2>/dev/null || \
    . "$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/tools/uom-port-watch.sh"

STATE_DIR="${UOM_DIR}/.uom-agent"
LOG_DIR="${STATE_DIR}/logs"
LOG_FILE="${LOG_DIR}/port-guardian.log"
RUNTIME="${STATE_DIR}/runtime"
LOCK_DIR="${RUNTIME}/portguard.lock"
PID_FILE="${LOCK_DIR}/pid"
SSH_CFG="${HOME}/.ssh/config"
TUNNEL_PORT="${UOM_PW_TUNNEL_PORT}"
LOOP_INTERVAL="${2:-20}"
HYBRID_SESSION="uom-hybrid"

mkdir -p "$LOG_DIR" "$RUNTIME"

_log() {
    _ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)"
    printf '[port-guardian] %s %s\n' "$_ts" "$*" | tee -a "$LOG_FILE"
}

_rotate_log() {
    [ ! -f "$LOG_FILE" ] && return
    _size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "${_size:-0}" -gt 1048576 ] 2>/dev/null; then
        _tmp="${LOG_FILE}.rotated.$$.tmp"
        tail -500 "$LOG_FILE" > "$_tmp" 2>/dev/null
        mv "$_tmp" "$LOG_FILE" 2>/dev/null || true
        _log "log rotated (was ${_size} bytes)"
    fi
}

_acquire_guard() {
    mkdir "$LOCK_DIR" 2>/dev/null || {
        if [ -f "$PID_FILE" ]; then
            _old=$(cat "$PID_FILE" 2>/dev/null)
            if [ -n "$_old" ] && kill -0 "$_old" 2>/dev/null; then
                _log "guardian already running (PID $_old)"
                return 1
            fi
        fi
        rm -rf "$LOCK_DIR" 2>/dev/null || true
        mkdir "$LOCK_DIR" 2>/dev/null || return 1
    }
    echo "$$" > "$PID_FILE"
    return 0
}

_release_guard() { rm -rf "$LOCK_DIR" 2>/dev/null || true; }

# ── React to drift: phone side restarts reverse tunnel; laptop side signals ─
# Role is auto-detected unless UOM_GUARDIAN_ROLE is set (laptop|phone).
_detect_role() {
    if [ -n "${UOM_GUARDIAN_ROLE:-}" ]; then
        echo "$UOM_GUARDIAN_ROLE"; return
    fi
    if [ -d "/data/data/com.termux" ] || [ -n "${ANDROID_ROOT:-}" ]; then
        echo "phone"
    else
        echo "laptop"
    fi
}

_handle_drift() {
    _phone="$1"   # host:port
    _role=$(_detect_role)
    _phost=$(printf '%s' "$_phone" | sed 's/:.*//')
    _pport=$(printf '%s' "$_phone" | sed 's/.*://')

    if [ "$_role" = "phone" ]; then
        # Phone: the reverse tunnel is phone-initiated. Restart it with the
        # laptop's CURRENT target so it always lands on the laptop.
        _laptop=$(uom_pw_discover_laptop)
        _lhost=$(printf '%s' "${_laptop:-}" | sed 's/:.*//')
        _lport=$(printf '%s' "${_laptop:-}" | sed 's/.*://')
        [ -z "$_lhost" ] && _lhost=$(uom_pw_read_hint laptop.host | sed 's/:.*//')
        [ -z "$_lhost" ] && _lhost=""
        _log "PHONE role: restarting reverse-ssh -> laptop ${_lhost:-<auto>}:${_lport:-22} (tunnel ${TUNNEL_PORT})"
        pkill -f "uom-reverse-ssh.sh" 2>/dev/null || true
        sleep 1
        if [ -f "${UOM_DIR}/bin/uom-reverse-ssh.sh" ]; then
            UOM_LAPTOP_HOST="$_lhost" UOM_LAPTOP_SSH_PORT="${_lport:-22}" \
                UOM_PHONE_SSH_PORT="$_pport" \
                sh "${UOM_DIR}/bin/uom-reverse-ssh.sh" start >/dev/null 2>&1 &
        fi
    else
        # Laptop: tunnel is phone-initiated; we can't launch it here. Just keep
        # ssh config + hints correct and signal the hybrid orchestrator. The
        # phone-side guardian is responsible for (re)establishing the tunnel.
        _log "LAPTOP role: drift handled via ssh-config + hybrid signal (phone owns tunnel)"
    fi
}

# ── Rewrite ~/.ssh/config block for uom-phone-rev to live target ──────────
_rewrite_ssh_config() {
    _phone="$1"   # host:port
    _phost=$(printf '%s' "$_phone" | sed 's/:.*//')
    _pport=$(printf '%s' "$_phone" | sed 's/.*://')
    [ -z "$_phost" ] && return 1
    mkdir -p "${HOME}/.ssh"
    _block="$(cat <<EOF
# >>> uom auto-managed (port-guardian) — do not edit by hand
Host uom-phone-rev
    HostName ${_phost}
    Port ${TUNNEL_PORT}
    User u0_a608
    StrictHostKeyChecking accept-new
    BatchMode yes

Host uom-phone-lan
    HostName ${_phost}
    Port ${_pport}
    User u0_a608
    StrictHostKeyChecking accept-new
# <<< uom auto-managed
EOF
)"
    # Remove any prior managed block, then append fresh one.
    if [ -f "$SSH_CFG" ]; then
        _tmp="${SSH_CFG}.tmp.$$"
        awk 'BEGIN{c=0} /^# >>> uom auto-managed/{c=1} /^# <<< uom auto-managed/{c=0;next} c==0{print}' \
            "$SSH_CFG" > "$_tmp" 2>/dev/null
        printf '%s\n' "$_block" >> "$_tmp" 2>/dev/null
        mv "$_tmp" "$SSH_CFG" 2>/dev/null
    else
        printf '%s\n' "$_block" > "$SSH_CFG" 2>/dev/null
    fi
    chmod 600 "$SSH_CFG" 2>/dev/null || true
    _log "ssh config updated: phone ${_phost}:${_pport} via tunnel ${TUNNEL_PORT}"
}

# ── Tell the hybrid orchestrator to re-evaluate (best effort) ─────────────
_signal_hybrid() {
    if tmux has-session -t "$HYBRID_SESSION" 2>/dev/null; then
        # send a harmless Ctrl-C-free nudge: touch a sentinel the orch polls
        touch "${RUNTIME}/portguard.drift" 2>/dev/null || true
        _log "signaled hybrid orchestrator (drift sentinel touched)"
    fi
}

# ── One reconciliation pass ────────────────────────────────────────────────
_reconcile() {
    _rotate_log

    # Gateway / my IP context (for logging + hotspot awareness)
    _my=$(uom_pw_my_ip); _gw=$(uom_pw_gateway)
    if uom_pw_on_phone_hotspot; then
        _ctx="HOTSPOT(${_gw})"
    else
        _ctx="WIFI(${_gw})"
    fi
    _log "context: my=${_my:-?} gw=${_gw:-?} ${_ctx}"

    # Discover phone live target
    _phone=$(uom_pw_discover_phone)
    if [ -z "$_phone" ]; then
        _log "phone not reachable via LAN — checking tunnel"
        if uom_pw_tunnel_up; then
            _log "tunnel alive (127.0.0.1:${TUNNEL_PORT}) — no action"
            return 0
        fi
        _log "phone unreachable AND no tunnel — nothing to do until phone appears"
        return 0
    fi
    _log "phone discovered at ${_phone}"

    _last=$(uom_pw_read_hint "phone.host")
    if [ "$_phone" != "$_last" ]; then
        uom_pw_write_hint "phone.host" "$_phone"
        _log "phone target drift: ${_last:-none} -> ${_phone}"
        _rewrite_ssh_config "$_phone"
        _signal_hybrid
        _handle_drift "$_phone"
    else
        _log "phone target stable (${_phone})"
    fi

    # Laptop discovery (for phone-side use / state mirror)
    _laptop=$(uom_pw_discover_laptop)
    if [ -n "$_laptop" ]; then
        _llast=$(uom_pw_read_hint "laptop.host")
        if [ "$_laptop" != "$_llast" ]; then
            uom_pw_write_hint "laptop.host" "$_laptop"
            _log "laptop target drift: ${_llast:-none} -> ${_laptop}"
        fi
    fi
    return 0
}

_dryrun() {
    echo "=== port-guardian self-test ==="
    echo "my_ip=$(uom_pw_my_ip)"
    echo "gateway=$(uom_pw_gateway)"
    echo "on_phone_hotspot=$(uom_pw_on_phone_hotspot && echo yes || echo no)"
    echo "tunnel_up=$(uom_pw_tunnel_up && echo yes || echo no)"
    _d=$(uom_pw_discover_phone); echo "discover_phone=${_d:-<none>}"
    _l=$(uom_pw_discover_laptop); echo "discover_laptop=${_l:-<none>}"
    echo "probe 127.0.0.1:22 = $(uom_pw_probe_ssh 127.0.0.1 22 2 && echo up || echo down)"
    echo "probe 127.0.0.1:31415 = $(uom_pw_probe_ssh 127.0.0.1 31415 2 && echo up || echo down)"
    echo "=== end self-test ==="
}

_status() {
    if [ -f "$PID_FILE" ]; then
        _pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
            printf 'port-guardian: RUNNING (PID %s)\n' "$_pid"
        else
            printf 'port-guardian: STALE (PID %s dead)\n' "$_pid"
        fi
    else
        printf 'port-guardian: NOT RUNNING\n'
    fi
    printf 'phone.host:  %s\n' "$(uom_pw_read_hint phone.host || echo none)"
    printf 'laptop.host: %s\n' "$(uom_pw_read_hint laptop.host || echo none)"
    printf 'tunnel:      %s\n' "$(uom_pw_tunnel_up && echo UP || echo DOWN)"
}

_start() {
    if [ -f "$PID_FILE" ]; then
        _pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
            _log "already running (PID $_pid)"; echo "already running (PID $_pid)"; return 0
        fi
    fi
    _log "launching port-guardian as background daemon"
    # Detach via tmux if available, else nohup
    if command -v tmux >/dev/null 2>&1; then
        tmux new-session -d -s "${HYBRID_SESSION}-pg" \
            "sh '${UOM_DIR}/bin/uom-port-guardian.sh' --loop ${LOOP_INTERVAL}" 2>/dev/null \
            && echo "started in tmux session ${HYBRID_SESSION}-pg" \
            || nohup sh "${UOM_DIR}/bin/uom-port-guardian.sh" --loop "${LOOP_INTERVAL}" >/dev/null 2>&1 &
    else
        nohup sh "${UOM_DIR}/bin/uom-port-guardian.sh" --loop "${LOOP_INTERVAL}" >/dev/null 2>&1 &
    fi
    echo "port-guardian started (interval ${LOOP_INTERVAL}s)"
}

_stop() {
    if [ -f "$PID_FILE" ]; then
        _pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
            kill "$_pid" 2>/dev/null || true
            _log "stopped guardian PID $_pid"
        fi
        rm -rf "$LOCK_DIR" 2>/dev/null || true
    fi
    pkill -f "${HYBRID_SESSION}-pg" 2>/dev/null || true
    echo "port-guardian stopped"
}

trap '_release_guard' 0 HUP INT TERM

# When sourced (for testing/function reuse), do not auto-run main.
case "$0" in
    *uom-port-guardian.sh) : ;;
    *) return 0 2>/dev/null || true ;;
esac

case "${1:-once}" in
    start)   _start ;;
    stop)    _stop ;;
    status)  _status ;;
    once)    _acquire_guard && _reconcile ;;
    dryrun)  _dryrun ;;
    role)    _detect_role ;;
    rewrite) _rewrite_ssh_config "${2:-}" ;;
    --loop)
        _acquire_guard || exit 1
        _log "guardian loop start (interval=${LOOP_INTERVAL}s)"
        while true; do
            _reconcile
            sleep "$LOOP_INTERVAL"
        done
        ;;
    *)
        printf 'Usage: %s [start|stop|status|once|dryrun|role|rewrite HOST:PORT|--loop [sec]]\n' "$0"
        exit 1
        ;;
esac
