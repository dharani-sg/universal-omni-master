#!/bin/sh
# tools/uom-phone-gen-loop.sh — Phone-side generator loop
# Picks pending tasks from queue, calls remote LLM via laptop.
# Designed to run inside Termux. Uses state lease check.
#
# Usage: sh tools/uom-phone-gen-loop.sh [--once]

set -u

UOM_DIR="${UOM_DIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
ONCE=0
[ "${1:-}" = "--once" ] && ONCE=1

. "${UOM_DIR}/tools/uom-state-lib.sh"
uom_state_init

QUEUE_FILE="${UOM_QUEUE_FILE}"
GEN_DIR="${UOM_STATE_DIR}/generated"
LOG_DIR="${UOM_LOG_DIR}"
LOG_FILE="${LOG_DIR}/phone-gen-loop.log"
LOCK_DIR="${UOM_RUNTIME_DIR}/phone-gen-loop.lock"
POLL_INTERVAL=10

mkdir -p "$GEN_DIR" "$LOG_DIR" "$(dirname "$LOCK_DIR")"

_log() {
    _ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u)"
    printf '[phone-gen] %s %s\n' "$_ts" "$*" >> "$LOG_FILE"
    printf '[phone-gen] %s %s\n' "$_ts" "$*"
}

_cleanup() {
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    _log "stopped"
}
trap '_cleanup' INT TERM EXIT

_acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo "$$" > "$LOCK_DIR/pid"
        return 0
    fi
    _old_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
    if [ -n "$_old_pid" ] && kill -0 "$_old_pid" 2>/dev/null; then
        _log "another instance running (PID $_old_pid), exiting"
        exit 0
    fi
    _log "reclaiming stale lock (PID $_old_pid)"
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    mkdir "$LOCK_DIR" 2>/dev/null || { _log "cannot acquire lock"; exit 1; }
    echo "$$" > "$LOCK_DIR/pid"
}

_llm_remote() {
    _prompt="$1"
    _output="$2"
    _model="${LLM_MODEL:-opencode/deepseek-v4-flash-free}"
    _remote="${UOM_DIR}/scripts/uom-llm-remote.sh"

    if [ ! -f "$_remote" ]; then
        _log "ERROR: uom-llm-remote.sh not found"
        return 1
    fi

    _log "calling remote LLM (model=${_model})..."
    printf '%s\n' "$_prompt" | timeout 120 sh "$_remote" "$_model" > "$_output" 2>>"$LOG_FILE"
    _rc=$?

    if [ "$_rc" -ne 0 ]; then
        _log "remote LLM failed (exit=$_rc)"
        return 1
    fi
    if [ ! -s "$_output" ]; then
        _log "remote LLM produced empty output"
        return 1
    fi

    _log "output: $(wc -l < "$_output") lines"
    return 0
}

main() {
    _acquire_lock
    _log "phone generator loop started (poll=${POLL_INTERVAL}s)"

    while true; do
        # Check write lease
        if ! uom_state_can_write phone 2>/dev/null; then
            _log "no write lease (writer_role=$(uom_state_get writer_role 2>/dev/null)), sleeping"
            sleep 30
            [ "$ONCE" -eq 1 ] && break
            continue
        fi

        # Pick pending task
        _task_id=$(sh "${UOM_DIR}/tools/uom-queue.sh" pick)
        if [ -z "$_task_id" ]; then
            sleep "$POLL_INTERVAL"
            [ "$ONCE" -eq 1 ] && break
            continue
        fi

        _task_desc=$(uom_state_get "current_task_desc")
        _log "processing: ${_task_id}"

        # Build prompt from context
        _ctx_file=$(jq -r --arg id "$_task_id" \
            '[.[] | select(.id == $id)] | first | .context_file // empty' \
            "$QUEUE_FILE" 2>/dev/null)
        _prompt="Generate a POSIX shell script for task: ${_task_id}"
        if [ -n "$_ctx_file" ] && [ -f "${UOM_DIR}/${_ctx_file}" ]; then
            _prompt="${_prompt}
Context:
$(cat "${UOM_DIR}/${_ctx_file}" | head -50)"
        fi

        # Claim task
        sh "${UOM_DIR}/tools/uom-queue.sh" claim "$_task_id" "phone" || {
            _log "cannot claim $_task_id — lease lost"
            [ "$ONCE" -eq 1 ] && break
            continue
        }

        # Generate
        _output="${GEN_DIR}/${_task_id}.sh"
        if _llm_remote "$_prompt" "$_output"; then
            # Write ready marker
            cat > "${GEN_DIR}/${_task_id}.ready" << EOF
{
  "task_id": "${_task_id}",
  "generated_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)",
  "model": "${LLM_MODEL:-opencode/deepseek-v4-flash-free}",
  "generator": "phone-gen-loop"
}
EOF
            _log "completed: ${_task_id}"
        else
            sh "${UOM_DIR}/tools/uom-queue.sh" fail "$_task_id" "llm-failed"
            _log "failed: ${_task_id}"
        fi

        [ "$ONCE" -eq 1 ] && break
        sleep "$POLL_INTERVAL"
    done

    _cleanup
}

main "$@"
