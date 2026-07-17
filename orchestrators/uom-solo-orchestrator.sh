#!/bin/sh
# orchestrators/uom-solo-orchestrator.sh — Phone-only task executor
# Runs only while active_agent=phone-solo and writer_role=phone.
# Processes tasks from queue.json using opencode.
# Does NOT auto-push. Rechecks state before each task-changing step.

set -eu

# ── Resolve and source state library ────────────────────────────────────────
_SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
_UOM_DIR="$(cd "$_SELF_DIR/.." 2>/dev/null && pwd)"
. "${_UOM_DIR}/tools/uom-state-lib.sh"
uom_state_init

# ── Paths ──────────────────────────────────────────────────────────────────
LOG_FILE="${UOM_LOG_DIR}/solo-orchestrator.log"
LOCK_DIR="${UOM_RUNTIME_DIR}/solo-orchestrator.lock"
RUNTIME_DIR="${UOM_RUNTIME_DIR}"

mkdir -p "$UOM_LOG_DIR" "$RUNTIME_DIR"

# ── Logging ────────────────────────────────────────────────────────────────
_slog() {
    _ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)"
    printf '[solo-oc] %s %s\n' "$_ts" "$*" >> "$LOG_FILE" 2>/dev/null || true
    printf '[solo-oc] %s %s\n' "$_ts" "$*" >&2
}

# ── Single-instance guard via mkdir ────────────────────────────────────────
_acquire_instance_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        printf '%s\n' "$$" > "$LOCK_DIR/pid"
        printf '%s\n' "$(uom_now_epoch)" > "$LOCK_DIR/started"
        chmod 700 "$LOCK_DIR" 2>/dev/null || true
        return 0
    fi

    # Check if existing instance is alive
    _old_pid=""
    if [ -f "$LOCK_DIR/pid" ]; then
        _old_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    fi
    if [ -n "$_old_pid" ] && kill -0 "$_old_pid" 2>/dev/null; then
        _slog "another instance already running (PID $_old_pid), exiting"
        return 1
    fi

    # Stale lock, reclaim
    _slog "reclaiming stale instance lock (old_pid=${_old_pid:-unknown})"
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        printf '%s\n' "$$" > "$LOCK_DIR/pid"
        printf '%s\n' "$(uom_now_epoch)" > "$LOCK_DIR/started"
        chmod 700 "$LOCK_DIR" 2>/dev/null || true
        return 0
    fi
    _slog "failed to acquire instance lock"
    return 1
}

_release_instance_lock() {
    if [ ! -d "$LOCK_DIR" ]; then
        return 0
    fi
    _lp=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    if [ "$_lp" = "$$" ]; then
        rm -rf "$LOCK_DIR" 2>/dev/null || true
    fi
}

# ── Signal handling: clean shutdown ────────────────────────────────────────
_CLEAN_EXIT=0

_cleanup() {
    if [ "$_CLEAN_EXIT" -eq 1 ]; then
        return
    fi
    _CLEAN_EXIT=1
    _slog "shutdown signal received, cleaning up"

    # Re-check state before modifying
    _cur_mode=$(uom_state_get "active_agent")
    _cur_writer=$(uom_state_get "writer_role")

    if [ "$_cur_mode" = "phone-solo" ] && [ "$_cur_writer" = "phone" ]; then
        # Checkpoint in-progress task if any
        _ts=$(uom_state_get "task_status")
        _tid=$(uom_state_get "current_task_id")
        if [ "$_ts" = "in_progress" ] && [ -n "$_tid" ]; then
            _slog "checkpointing task $_tid on shutdown"
            _now_utc=$(uom_now_utc)
            _ckpt="shutdown-ckpt-$(uom_now_epoch)"
            state_update "task_status" "checkpointed"
            state_update "checkpoint_ref" "$_ckpt"
            state_update "last_transition" "solo-shutdown"
            state_update "last_transition_at" "$_now_utc"
        else
            # Not mid-task; mark blocked so laptop knows we stopped
            _now_utc=$(uom_now_utc)
            state_update "task_status" "blocked"
            state_update "last_transition" "solo-shutdown"
            state_update "last_transition_at" "$_now_utc"
        fi
    fi

    # Release local locks
    _release_instance_lock
    _slog "cleanup complete"
}

trap '_cleanup' INT TERM
trap '_cleanup; exit 0' EXIT

# ── Atomic temp file helpers ───────────────────────────────────────────────
# Write to temp file in same directory, then mv atomically
_atomic_json_update() {
    # Usage: _atomic_json_update TARGET_FILE JQ_FILTER [JQ_ARGS...]
    _target="$1"; shift
    _dir="$(dirname "$_target")"
    _tmp="${_dir}/.$(basename "$_target").$$.$(uom_now_epoch).tmp"

    jq "$@" "$_target" > "$_tmp" 2>/dev/null
    if ! jq empty "$_tmp" 2>/dev/null; then
        rm -f "$_tmp"
        _slog "ERROR: JSON update produced invalid output for $_target"
        return 1
    fi
    mv "$_tmp" "$_target"
}

# ── Queue operations ───────────────────────────────────────────────────────
_next_task() {
    jq -r 'map(select(.status == "pending" or .status == "failed")) | sort_by(.priority // 999) | .[0].id // empty' "$UOM_QUEUE_FILE" 2>/dev/null
}

_next_task_desc() {
    jq -r 'map(select(.status == "pending" or .status == "failed")) | sort_by(.priority // 999) | .[0].desc // empty' "$UOM_QUEUE_FILE" 2>/dev/null
}

_set_task_status_in_queue() {
    _task_id="$1"; _new_status="$2"
    _atomic_json_update "$UOM_QUEUE_FILE" \
        'map(if .id == $tid then .status = $st else . end)' \
        --arg tid "$_task_id" --arg st "$_new_status"
}

_move_task_to_done() {
    _task_id="$1"
    _ts=$(uom_now_utc)
    _atomic_json_update "$UOM_QUEUE_FILE" \
        '[.[] | select(.id != $tid)]' --arg tid "$_task_id"
    _atomic_json_update "$UOM_DONE_FILE" \
        '. += [{"id": $tid, "completed": $ts}]' \
        --arg tid "$_task_id" --arg ts "$_ts"
}

# ── State recheck helper ──────────────────────────────────────────────────
_verify_solo_mode() {
    _m=$(uom_state_get "active_agent")
    _w=$(uom_state_get "writer_role")
    if [ "$_m" = "phone-solo" ] && [ "$_w" = "phone" ]; then
        return 0
    fi
    _slog "mode changed (active_agent=$_m, writer_role=$_w), stopping"
    return 1
}

# ── Acquire instance lock ─────────────────────────────────────────────────
if ! _acquire_instance_lock; then
    exit 1
fi
_slog "solo orchestrator started (PID $$)"

# ── Pre-flight: confirm we should be running ───────────────────────────────
if ! _verify_solo_mode; then
    _slog "not in phone-solo mode at startup, exiting"
    _release_instance_lock
    exit 0
fi

# ── Task processing loop ──────────────────────────────────────────────────
while true; do
    # Recheck mode before every task-changing step
    if ! _verify_solo_mode; then
        break
    fi

    _task_id=$(_next_task)
    if [ -z "$_task_id" ]; then
        _slog "no pending tasks, sleeping"
        sleep 30
        continue
    fi

    _task_desc=$(_next_task_desc)
    _slog "processing task: $_task_id — $_task_desc"

    # Mark in-progress
    state_update "current_task_id" "$_task_id"
    state_update "current_task_desc" "$_task_desc"
    state_update "task_status" "in_progress"

    # Double-check mode before executing
    if ! _verify_solo_mode; then
        _slog "mode changed before execution, requeueing $_task_id"
        break
    fi

    # Execute task
    _exit_code=0
    if command -v opencode >/dev/null 2>&1; then
        (
            cd "$UOM_REPO_ROOT"
            opencode --non-interactive --task "$_task_id"
        ) >> "$LOG_FILE" 2>&1 || _exit_code=$?
    else
        _slog "opencode not found — cannot process task $_task_id"
        _exit_code=127
    fi

    # Recheck mode after execution before state mutation
    if ! _verify_solo_mode; then
        _slog "mode changed after execution, leaving $_task_id as-is"
        break
    fi

    if [ "$_exit_code" -eq 0 ]; then
        _slog "task $_task_id completed successfully"
        _set_task_status_in_queue "$_task_id" "done"
        _move_task_to_done "$_task_id"
        state_update "task_status" "idle"
        state_update "current_task_id" ""
        state_update "current_task_desc" ""
    else
        _slog "task $_task_id failed (rc=$_exit_code), will retry"
        state_update "task_status" "failed"
    fi

    # Brief pause between tasks
    sleep 5
done

_slog "solo orchestrator exiting"
_cleanup
