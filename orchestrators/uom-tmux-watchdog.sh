#!/bin/sh
# bin/uom-tmux-watchdog.sh — Tmux session watchdog for UOM project
# Monitors critical tmux sessions and auto-recreates them if they die.
# Also tracks CPU/battery state and restarts orchestrator if crashed.
#
# Usage:
#   uom-tmux-watchdog           # Run once (check and exit)
#   uom-tmux-watchdog --daemon  # Run in background (loops)
#   uom-tmux-watchdog --status  # Show watchdog status
#   uom-tmux-watchdog --stop    # Kill running watchdog
#
# Auto-started from Termux:Boot on phone and ~/.profile on laptop.

set -u

_LOCK_DIR="/tmp/.uom_tmuxwatch_lock"
if [ "${1:-}" != "--stop" ]; then
    if ! mkdir "$_LOCK_DIR" 2>/dev/null; then
        if [ -f "$_LOCK_DIR/pid" ]; then
            _old=$(cat "$_LOCK_DIR/pid" 2>/dev/null)
            if [ -n "$_old" ] && kill -0 "$_old" 2>/dev/null; then
                echo "uom-tmux-watchdog already running (PID $_old)"
                exit 1
            fi
        fi
        rm -rf "$_LOCK_DIR" 2>/dev/null || true
        mkdir "$_LOCK_DIR" 2>/dev/null || { echo "Cannot acquire lock"; exit 1; }
    fi
    echo $$ > "$_LOCK_DIR/pid"
    trap 'rm -rf "$_LOCK_DIR"' EXIT INT TERM
fi

UOM_DIR="${OMNI_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
STATE_FILE="${UOM_DIR}/.uom-agent/state.json"
QUEUE_FILE="${UOM_DIR}/.uom-agent/queue.json"
HYB_DIR="${HOME}/.uom-termux-user"
WATCHDOG_PID="${HYB_DIR}/tmux-watchdog.pid"
WATCHDOG_LOG="${HYB_DIR}/tmux-watchdog.log"
CHECK_INTERVAL=30
STALE_THRESHOLD=300

mkdir -p "$HYB_DIR"

_log() {
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)
    printf '[tmuxwd] %s %s\n' "${_ts}" "$*" >> "$WATCHDOG_LOG"
    printf '[tmuxwd] %s\n' "$*"
}

_rotate_log() {
    [ ! -f "$WATCHDOG_LOG" ] && return
    _size=$(wc -c < "$WATCHDOG_LOG" 2>/dev/null || echo 0)
    if [ "${_size:-0}" -gt 1048576 ] 2>/dev/null; then
        _tmp="${WATCHDOG_LOG}.rotated.$$.tmp"
        tail -500 "$WATCHDOG_LOG" > "$_tmp" 2>/dev/null
        mv "$_tmp" "$WATCHDOG_LOG" 2>/dev/null || true
        _log "log rotated (was ${_size} bytes)"
    fi
}

IS_PHONE=false
if echo "$HOME" | grep -q '/data/data/com.termux' 2>/dev/null; then
    IS_PHONE=true
fi

# ═══════════════════════════════════════════════════════════════════════
# Tmux Session Templates
# ═══════════════════════════════════════════════════════════════════════

_create_uom_session() {
    _session="uom"
    # Check if session already exists — preserve it if so
    if tmux has-session -t "$_session" 2>/dev/null; then
        # Verify pane count — repair if too few
        _pane_count=$(tmux list-panes -t "$_session" 2>/dev/null | wc -l)
        if [ "${_pane_count:-0}" -lt 2 ] 2>/dev/null; then
            _log "Session '$_session' exists but only $_pane_count pane(s) — adding state pane"
            tmux split-window -t "${_session}" -v -p 25 2>/dev/null || true
            tmux send-keys -t "${_session}" \
                "cd ${UOM_DIR} && while true; do if [ -f .uom-agent/state.json ]; then jq -c '{mode:.active_agent,writer:.writer_role,task:.task_status,epoch:.ownership_epoch}' .uom-agent/state.json 2>/dev/null || cat .uom-agent/state.json; else echo '{\"error\":\"no state\"}'; fi; sleep 5; done" C-m 2>/dev/null || true
        fi
        return 0
    fi

    # Create new session with main + state pane layout
    tmux new-session -d -s "$_session" -n "opencode" \
        -x "$(tput cols 2>/dev/null || echo 80)" \
        -y "$(tput lines 2>/dev/null || echo 24)" 2>/dev/null || return 1
    sleep 0.3

    # Set pane title and launch main command
    tmux select-pane -t "${_session}:opencode.0" -T "uom-main" 2>/dev/null || true
    tmux send-keys -t "${_session}:opencode.0" \
        "cd ${UOM_DIR} && sh bin/omni-project-start.sh --menu" C-m 2>/dev/null || true

    # Add state watcher pane (bottom 25%)
    tmux split-window -t "${_session}:opencode.0" -v -p 25 2>/dev/null || true
    sleep 0.2
    tmux select-pane -t "${_session}:opencode.1" -T "uom-state" 2>/dev/null || true
    tmux send-keys -t "${_session}:opencode.1" \
        "cd ${UOM_DIR} && while true; do if [ -f .uom-agent/state.json ]; then jq -c '{mode:.active_agent,writer:.writer_role,task:.task_status,epoch:.ownership_epoch}' .uom-agent/state.json 2>/dev/null || cat .uom-agent/state.json; else echo '{\"error\":\"no state\"}'; fi; sleep 5; done" C-m 2>/dev/null || true

    # Add log pane if terminal is wide enough (>120 cols)
    _cols=$(tput cols 2>/dev/null || echo 80)
    if [ "${_cols:-80}" -gt 120 ] 2>/dev/null; then
        tmux split-window -t "${_session}:opencode.0" -h -p 25 2>/dev/null || true
        sleep 0.2
        tmux select-pane -t "${_session}:opencode.0" -T "uom-log" 2>/dev/null || true
        tmux send-keys -t "${_session}:opencode.0" \
            "tail -f ${WATCHDOG_LOG}" C-m 2>/dev/null || true
    fi

    # Select main pane (last pane after splits)
    tmux select-pane -t "${_session}:opencode.0" 2>/dev/null || true

    _log "Created tmux session '${_session}' with pane layout (main + state + optional log)"
    return 0
}

_create_orch_session() {
    _session="uom-orch"
    tmux kill-session -t "$_session" 2>/dev/null || true
    sleep 0.5

    if $IS_PHONE; then
        _cmd="sh ${UOM_DIR}/tools/uom-orch-phone.sh"
    else
        _cmd="sh ${UOM_DIR}/tools/uom-orch-laptop.sh"
    fi

    tmux new-session -d -s "$_session" -n "orchestrator" "$_cmd" 2>/dev/null || return 1
    sleep 0.3

    tmux new-window -t "$_session" -n "logs" \
        "tail -f ${WATCHDOG_LOG}" 2>/dev/null || true
    sleep 0.2

    tmux new-window -t "$_session" -n "state" \
        "cd ${UOM_DIR} && watch -n5 'cat .uom-agent/state.json && echo --- && cat .uom-agent/queue.json'" \
        2>/dev/null || true

    tmux select-window -t "$_session:0"
    _log "Created orchestrator tmux session '${_session}'"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════
# Health Checks
# ═══════════════════════════════════════════════════════════════════════

_check_session() {
    _session="$1"
    tmux has-session -t "$_session" 2>/dev/null
}

_check_orchestrator() {
    if $IS_PHONE; then
        ps -ef 2>/dev/null | grep -v grep | grep -q 'uom-orch-phone'
    else
        ps -ef 2>/dev/null | grep -v grep | grep -q 'uom-orch-laptop'
    fi
}

_check_tunnel() {
    pgrep -f 'autossh.*-R.*31415' >/dev/null 2>&1 || \
    pgrep -f 'ssh.*-R.*31415' >/dev/null 2>&1
}

_check_state_stale() {
    if [ ! -f "$STATE_FILE" ]; then return 1; fi
    _hb=$(jq -r '.laptop_heartbeat // ""' "$STATE_FILE" 2>/dev/null)
    [ -z "$_hb" ] && return 1
    _now=$(date -u +%s 2>/dev/null)
    _epoch=$(date -u -d "$_hb" +%s 2>/dev/null || python3 -c "import datetime; print(int(datetime.datetime.fromisoformat('$_hb').timestamp()))" 2>/dev/null || echo "0")
    _diff=$(( _now - _epoch ))
    [ "$_diff" -gt "$STALE_THRESHOLD" ]
}

# ═══════════════════════════════════════════════════════════════════════
# Watchdog Check (single pass)
# ═══════════════════════════════════════════════════════════════════════

_watchdog_check() {
    _recovered=false
    _rotate_log

    # 1. Check uom session (main project tmux)
    if ! _check_session "uom"; then
        _log "Session 'uom' not found. Recreating..."
        _create_uom_session && _recovered=true
    else
        # Session exists — verify pane count (repair if <2 panes)
        _pane_count=$(tmux list-panes -t "uom" 2>/dev/null | wc -l)
        if [ "${_pane_count:-0}" -lt 2 ] 2>/dev/null; then
            _log "Session 'uom' has only $_pane_count pane(s) — adding state pane"
            tmux split-window -t "uom" -v -p 25 2>/dev/null || true
            tmux send-keys -t "uom" \
                "cd ${UOM_DIR} && while true; do if [ -f .uom-agent/state.json ]; then jq -c '{mode:.active_agent,writer:.writer_role,task:.task_status,epoch:.ownership_epoch}' .uom-agent/state.json 2>/dev/null || cat .uom-agent/state.json; else echo '{\"error\":\"no state\"}'; fi; sleep 5; done" C-m 2>/dev/null || true
            _recovered=true
        fi
    fi

    # 2. Check orchestrator session
    if ! _check_session "uom-orch"; then
        _log "Session 'uom-orch' not found. Recreating..."
        _create_orch_session && _recovered=true
    fi

    # 3. Check orchestrator process directly (not just tmux window)
    if ! _check_orchestrator; then
        _log "Orchestrator process not running. Starting..."
        if $IS_PHONE; then
            nohup sh "${UOM_DIR}/tools/uom-orch-phone.sh" \
                > "${HYB_DIR}/phone-orch.log" 2>&1 &
        else
            nohup sh "${UOM_DIR}/tools/uom-orch-laptop.sh" \
                > "${HYB_DIR}/laptop-orch.log" 2>&1 &
        fi
        _log "Orchestrator restarted (PID $!)"
        _recovered=true
    fi

    # 4. Check reverse tunnel (phone only)
    if $IS_PHONE && ! _check_tunnel; then
        _log "Reverse tunnel not found. Starting..."
        nohup sh "${UOM_DIR}/bin/uom-reverse-ssh.sh" \
            > "${HYB_DIR}/tunnel-restart.log" 2>&1 &
        _log "Tunnel restart initiated (PID $!)"
        _recovered=true
    fi

    # 5. Check for stale state (laptop unreachable for too long)
    if $IS_PHONE && _check_state_stale; then
        _log "Laptop heartbeat stale. Checking if takeover needed..."
        # The orchestrator handles this — just log it here
        _active=$(jq -r '.active_agent // "unknown"' "$STATE_FILE" 2>/dev/null)
        _log "Current active agent: ${_active}"
    fi

    $_recovered
}

# ═══════════════════════════════════════════════════════════════════════
# Daemon Mode
# ═══════════════════════════════════════════════════════════════════════

_daemon_loop() {
    echo "$$" > "$WATCHDOG_PID"
    _log "Tmux watchdog started (PID $$). Interval: ${CHECK_INTERVAL}s"
    _rotate_log

    # Initial creation
    _create_uom_session
    _create_orch_session

    while true; do
        if _watchdog_check; then
            _log "Watchdog: recovered something"
        fi
        sleep "$CHECK_INTERVAL"
    done
}

# ═══════════════════════════════════════════════════════════════════════
# Status
# ═══════════════════════════════════════════════════════════════════════

_show_status() {
    echo "═══ UOM TMUX WATCHDOG STATUS ═══"

    if [ -f "$WATCHDOG_PID" ]; then
        _pid=$(cat "$WATCHDOG_PID")
        if kill -0 "$_pid" 2>/dev/null; then
            echo "Watchdog: ${GREEN:-}RUNNING${NC:-} (PID ${_pid})"
        else
            echo "Watchdog: ${RED:-}STALE PID${NC:-} (${_pid})"
        fi
    else
        echo "Watchdog: ${RED:-}NOT RUNNING${NC:-}"
    fi

    echo ""
    echo "Tmux Sessions:"
    for _s in uom uom-orch uom-hybrid; do
        if tmux has-session -t "$_s" 2>/dev/null; then
            _windows=$(tmux list-windows -t "$_s" -F '#W' 2>/dev/null | tr '\n' ', ')
            echo "  ✓ ${_s}: ${_windows}"
        else
            echo "  ✗ ${_s}: not found"
        fi
    done

    echo ""
    echo "Orchestrator:"
    if _check_orchestrator; then
        echo "  ✓ Running"
    else
        echo "  ✗ Not running"
    fi

    echo ""
    echo "Tunnel:"
    if _check_tunnel; then
        echo "  ✓ Running"
    else
        echo "  ✗ Not running"
    fi

    echo ""
    echo "Recent log:"
    tail -5 "$WATCHDOG_LOG" 2>/dev/null || echo "  (no log)"
}

# ═══════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════

main() {
    _cmd="${1:-}"

    case "$_cmd" in
        --daemon|-d)
            _daemon_loop
            ;;
        --status|-s)
            _show_status
            ;;
        --stop|-k)
            if [ -f "$WATCHDOG_PID" ]; then
                _pid=$(cat "$WATCHDOG_PID")
                kill "$_pid" 2>/dev/null || true
                rm -f "$WATCHDOG_PID"
                _log "Watchdog stopped (PID ${_pid})"
            fi
            ;;
        --check|-c)
            _watchdog_check
            if _check_session "uom" && _check_session "uom-orch"; then
                echo "All sessions OK"
                exit 0
            else
                echo "Some sessions missing"
                exit 1
            fi
            ;;
        "")
            _watchdog_check
            ;;
        *)
            echo "Usage: uom-tmux-watchdog [--daemon|--status|--stop|--check]"
            exit 1
            ;;
    esac
}

main "$@"
