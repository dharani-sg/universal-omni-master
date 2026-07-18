#!/bin/sh
# tools/uom-queue.sh — Centralized queue operations with state lease checks
# All scripts should use THIS instead of inline jq queue mutations.
# Usage:
#   tools/uom-queue.sh list [pending|in_progress|verified|failed|done]
#   tools/uom-queue.sh pick                    # Pick highest-priority pending
#   tools/uom-queue.sh claim TASK_ID ROLE      # Mark in_progress (with lease check)
#   tools/uom-queue.sh complete TASK_ID        # Mark verified
#   tools/uom-queue.sh fail TASK_ID REASON     # Mark failed
#   tools/uom-queue.sh reset TASK_ID           # Reset to pending
#   tools/uom-queue.sh show TASK_ID            # Show task details
#   tools/uom-queue.sh count                   # Count by status

set -u

UOM_DIR="${UOM_DIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"

if [ -f "${UOM_DIR}/tools/uom-state-lib.sh" ]; then
    . "${UOM_DIR}/tools/uom-state-lib.sh"
    uom_state_init 2>/dev/null || true
fi

QUEUE_FILE="${UOM_DIR}/.uom-agent/queue.json"
DONE_FILE="${UOM_DIR}/.uom-agent/done.json"

_log() {
    _ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u)"
    printf '[queue] %s %s\n' "$_ts" "$*" >&2
}

_atomic_update() {
    _target="$1"
    _dir="$(dirname "$_target")"
    _tmp="${_dir}/.$(basename "$_target").queue.$$.tmp"
    jq "${@:2}" "$_target" > "$_tmp" 2>/dev/null
    if jq empty "$_tmp" 2>/dev/null; then
        mv "$_tmp" "$_target"
    else
        rm -f "$_tmp"
        return 1
    fi
}

_ensure_queue() {
    if [ ! -f "$QUEUE_FILE" ]; then
        printf '[]\n' > "$QUEUE_FILE"
    fi
    if [ ! -f "$DONE_FILE" ]; then
        printf '[]\n' > "$DONE_FILE"
    fi
}

cmd_list() {
    _filter="${1:-}"
    _ensure_queue
    if [ -n "$_filter" ]; then
        jq -r ".[] | select(.status == \"$_filter\") | .id" "$QUEUE_FILE" 2>/dev/null
    else
        jq -r '.[] | .id' "$QUEUE_FILE" 2>/dev/null
    fi
}

cmd_pick() {
    _ensure_queue
    jq -r '
        [.[] | select(.status == "pending" or .status == "failed")]
        | sort_by(.priority // 999)
        | .[0].id // empty
    ' "$QUEUE_FILE" 2>/dev/null
}

cmd_claim() {
    _task_id="$1"
    _role="${2:-laptop}"

    # Check state lease first
    if command -v uom_state_can_write >/dev/null 2>&1; then
        if ! uom_state_can_write "$_role" 2>/dev/null; then
            _log "ERROR: $_role cannot write (current writer_role=$(uom_state_get writer_role 2>/dev/null || echo unknown))"
            return 1
        fi
    fi

    _ensure_queue
    _atomic_update "$QUEUE_FILE" \
        'map(if .id == $tid then .status = "in_progress" | .claimed_by = $role | .claimed_at = $now else . end)' \
        --arg tid "$_task_id" --arg role "$_role" --arg now "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u)"
}

cmd_complete() {
    _task_id="$1"
    _ensure_queue
    # Remove from queue, add to done
    _atomic_update "$QUEUE_FILE" \
        '[.[] | select(.id != $tid)]' --arg tid "$_task_id"
    _atomic_update "$DONE_FILE" \
        '. += [{"id": $tid, "status": "verified", "completed": $now}]' \
        --arg tid "$_task_id" --arg now "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u)"
}

cmd_fail() {
    _task_id="$1"
    _reason="${2:-unknown}"
    _ensure_queue
    _atomic_update "$QUEUE_FILE" \
        'map(if .id == $tid then .status = "pending" | .fail_reason = $reason | .fail_count = ((.fail_count // 0) + 1) else . end)' \
        --arg tid "$_task_id" --arg reason "$_reason"
}

cmd_reset() {
    _task_id="$1"
    _ensure_queue
    _atomic_update "$QUEUE_FILE" \
        'map(if .id == $tid then .status = "pending" | del(.claimed_by) | del(.claimed_at) else . end)' \
        --arg tid "$_task_id"
}

cmd_show() {
    _task_id="$1"
    _ensure_queue
    jq -r ".[] | select(.id == \"$_task_id\")" "$QUEUE_FILE" 2>/dev/null
}

cmd_count() {
    _ensure_queue
    jq -r '
        reduce .[] as $t ({};
            .[$t.status] += 1
        ) | to_entries | .[] | "\(.key): \(.value)"
    ' "$QUEUE_FILE" 2>/dev/null || echo "pending: 0"
}

main() {
    _cmd="${1:-help}"
    shift 2>/dev/null || true

    case "$_cmd" in
        list)     cmd_list "$@" ;;
        pick)     cmd_pick ;;
        claim)    cmd_claim "$@" ;;
        complete) cmd_complete "$@" ;;
        fail)     cmd_fail "$@" ;;
        reset)    cmd_reset "$@" ;;
        show)     cmd_show "$@" ;;
        count)    cmd_count ;;
        help|--help|-h)
            sed -n '2,12p' "$0"
            ;;
        *)
            printf 'Unknown command: %s\n' "$_cmd" >&2
            sed -n '2,12p' "$0"
            return 1
            ;;
    esac
}

main "$@"
