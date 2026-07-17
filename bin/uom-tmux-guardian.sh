#!/bin/sh
# bin/uom-tmux-guardian.sh — POSIX tmux session guardian for UOM
# Creates/repairs the "uom" tmux session with managed panes.
# Usage: sh bin/uom-tmux-guardian.sh [once|--loop [interval]]

set -u

# ── Resolve repo root ──────────────────────────────────────────────────────
UOM_DIR="${OMNI_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
STATE_FILE="${UOM_DIR}/.uom-agent/state.json"
LOG_DIR="${UOM_DIR}/.uom-agent/logs"
LOG_FILE="${LOG_DIR}/tmux-guardian.log"
LOCK_DIR="${UOM_DIR}/.uom-agent/runtime/guardian.lock"
PID_FILE="${LOCK_DIR}/pid"

UOM_SESSION="uom"
UOM_WINDOW="opencode"
MAIN_CMD="cd '${UOM_DIR}' && sh bin/omni-project-start.sh --menu"
STATE_CMD="cd '${UOM_DIR}' && while true; do if [ -f .uom-agent/state.json ]; then jq -c '{mode:.active_agent,writer:.writer_role,task:.task_status,epoch:.ownership_epoch,tasks:.current_task_id}' .uom-agent/state.json 2>/dev/null || cat .uom-agent/state.json; else echo '{\"error\":\"no state\"}'; fi; sleep 5; done"
LOG_CMD="tail -f '${UOM_DIR}/.uom-agent/logs/watchdog.log' 2>/dev/null || echo 'No watchdog log yet'"

mkdir -p "$LOG_DIR" "${UOM_DIR}/.uom-agent/runtime"

_log() {
    _ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)"
    printf '[tmux-guardian] %s %s\n' "$_ts" "$*" | tee -a "$LOG_FILE"
}

# ── Log rotation ───────────────────────────────────────────────────────────
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

# ── Singleton guard ────────────────────────────────────────────────────────
_acquire_guard() {
    mkdir "$LOCK_DIR" 2>/dev/null || {
        # Check if existing guardian is alive
        if [ -f "$PID_FILE" ]; then
            _old_pid=$(cat "$PID_FILE" 2>/dev/null)
            if [ -n "$_old_pid" ] && kill -0 "$_old_pid" 2>/dev/null; then
                _log "guardian already running (PID $_old_pid)"
                return 1
            fi
        fi
        # Stale lock — reclaim
        rm -rf "$LOCK_DIR" 2>/dev/null || true
        mkdir "$LOCK_DIR" 2>/dev/null || return 1
    }
    echo "$$" > "$PID_FILE"
    return 0
}

_release_guard() {
    rm -rf "$LOCK_DIR" 2>/dev/null || true
}

# ── Check if tmux is available ────────────────────────────────────────────
if ! command -v tmux >/dev/null 2>&1; then
    _log "ERROR: tmux not installed"
    echo "ERROR: tmux not installed" >&2
    exit 1
fi

# ── Determine mode ─────────────────────────────────────────────────────────
_mode="${1:-once}"
_interval="${2:-30}"

# ── Ensure session exists (create if needed) ───────────────────────────────
_ensure_session() {
    if tmux has-session -t "$UOM_SESSION" 2>/dev/null; then
        return 0
    fi

    _log "creating tmux session '$UOM_SESSION'..."
    tmux new-session -d -s "$UOM_SESSION" -n "$UOM_WINDOW" \
        -x "$(tput cols 2>/dev/null || echo 80)" \
        -y "$(tput lines 2>/dev/null || echo 24)"

    # Set pane titles for identification
    tmux select-pane -t "${UOM_SESSION}:${UOM_WINDOW}.0" -T "uom-main"
    tmux send-keys -t "${UOM_SESSION}:${UOM_WINDOW}.0" "$MAIN_CMD" C-m

    # Add state watcher pane (bottom)
    tmux split-window -t "${UOM_SESSION}:${UOM_WINDOW}.0" -v -p 25
    tmux select-pane -t "${UOM_SESSION}:${UOM_WINDOW}.1" -T "uom-state"
    tmux send-keys -t "${UOM_SESSION}:${UOM_WINDOW}.1" "$STATE_CMD" C-m

    # Add log pane if terminal is wide enough
    _cols=$(tput cols 2>/dev/null || echo 80)
    if [ "${_cols:-80}" -gt 120 ] 2>/dev/null; then
        tmux split-window -t "${UOM_SESSION}:${UOM_WINDOW}.0" -h -p 25
        tmux select-pane -t "${UOM_SESSION}:${UOM_WINDOW}.0" -T "uom-log"
        tmux send-keys -t "${UOM_SESSION}:${UOM_WINDOW}.0" "$LOG_CMD" C-m
    fi

    # Select main pane (last pane is the main one after splits)
    tmux select-pane -t "${UOM_SESSION}:${UOM_WINDOW}.0"

    _log "session '$UOM_SESSION' created"
    return 0
}

# ── Verify managed panes exist ─────────────────────────────────────────────
_verify_panes() {
    _pane_count=$(tmux list-panes -t "$UOM_SESSION" 2>/dev/null | wc -l)
    if [ "${_pane_count:-0}" -lt 2 ] 2>/dev/null; then
        _log "WARNING: only $_pane_count pane(s) found, need at least 2"
        # Add missing state pane
        tmux split-window -t "${UOM_SESSION}:${UOM_WINDOW}" -v -p 25
        tmux send-keys -t "${UOM_SESSION}:${UOM_WINDOW}.1" "$STATE_CMD" C-m
        _log "repaired state watcher pane"
    fi
    return 0
}

# ── Main action ────────────────────────────────────────────────────────────
_run_guardian() {
    _rotate_log
    _ensure_session || return 1
    _verify_panes
    _log "guardian check complete"
}

trap '_release_guard' 0 HUP INT TERM

case "$_mode" in
    once)
        if _acquire_guard; then
            _run_guardian
        fi
        ;;
    --loop)
        if ! _acquire_guard; then
            exit 1
        fi
        _log "starting guardian loop (interval=${_interval}s)"
        while true; do
            _run_guardian
            sleep "$_interval"
        done
        ;;
    stop)
        if [ -f "$PID_FILE" ]; then
            _pid=$(cat "$PID_FILE" 2>/dev/null)
            if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
                kill "$_pid" 2>/dev/null || true
                _log "stopped guardian PID $_pid"
            fi
            rm -rf "$LOCK_DIR" 2>/dev/null || true
        fi
        ;;
    status)
        if [ -f "$PID_FILE" ]; then
            _pid=$(cat "$PID_FILE" 2>/dev/null)
            if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
                printf 'guardian: RUNNING (PID %s)\n' "$_pid"
            else
                printf 'guardian: STALE (PID %s dead)\n' "$_pid"
            fi
        else
            printf 'guardian: NOT RUNNING\n'
        fi
        if tmux has-session -t "$UOM_SESSION" 2>/dev/null; then
            _pc=$(tmux list-panes -t "$UOM_SESSION" 2>/dev/null | wc -l)
            printf 'session:  EXISTS (%s panes)\n' "$_pc"
        else
            printf 'session:  NOT FOUND\n'
        fi
        ;;
    *)
        printf 'Usage: %s [once|--loop [interval]|stop|status]\n' "$0"
        exit 1
        ;;
esac
