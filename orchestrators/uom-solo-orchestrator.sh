#!/data/data/com.termux/files/usr/bin/sh
# orchestrators/uom-solo-orchestrator.sh — Phone-only fallback mode
# Triggered when laptop is unreachable for >15 minutes
# Runs opencode directly on phone, commits+pushes after each task

set -u

UOM_DIR="${HOME}/src/universal-omni-master"
STATE_FILE="${UOM_DIR}/.uom-agent/state.json"
DONE_FILE="${UOM_DIR}/.uom-agent/done.json"
QUEUE_FILE="${UOM_DIR}/.uom-agent/queue.json"
LOG_FILE="${HOME}/.uom-termux-user/solo-orchestrator.log"

mkdir -p "$(dirname "${LOG_FILE}")"

_log() {
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)
    printf '[solo-oc] %s %s\n' "${_ts}" "$*" | tee -a "${LOG_FILE}"
}

_set_state() {
    _key="$1"; _val="$2"
    jq --arg k "${_key}" --arg v "${_val}" '.[$k] = $v' "${STATE_FILE}" > /tmp/state_tmp.json && \
        mv /tmp/state_tmp.json "${STATE_FILE}"
}

_get_state() {
    jq -r ".$1" "${STATE_FILE}" 2>/dev/null || echo "null"
}

_next_task() {
    jq -r '.[0].id // empty' "${QUEUE_FILE}" 2>/dev/null
}

_complete_task() {
    _task_id="$1"
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)
    # Remove from queue, add to done
    jq --arg id "${_task_id}" --arg ts "${_ts}" \
       '[.[] | select(.id != $id)]' "${QUEUE_FILE}" > /tmp/queue_tmp.json && \
       mv /tmp/queue_tmp.json "${QUEUE_FILE}"
    # Append to done
    jq --arg id "${_task_id}" --arg ts "${_ts}" \
       '. += [{"id": $id, "completed": $ts}]' "${DONE_FILE}" > /tmp/done_tmp.json && \
       mv /tmp/done_tmp.json "${DONE_FILE}"
}

_commit_and_push() {
    _task_id="$1"
    cd "${UOM_DIR}" || return 1
    git add -A
    git commit -m "solo(phone): ${_task_id} [solo]" 2>/dev/null || true
    git push origin main 2>/dev/null || _log "push failed (offline, will retry)"
}

# ── MAIN ──

_log "Solo orchestrator starting"
_set_state "active_agent" "phone-solo"
_set_state "task_status" "solo_active"

# Source IP discovery if available
. "${UOM_DIR}/tools/uom-ip-discover.sh" 2>/dev/null || true

while true; do
    TASK_ID=$(_next_task)
    if [ -z "${TASK_ID}" ]; then
        _log "No pending tasks. Idle loop..."
        sleep 60
        continue
    fi

    _log "Starting task: ${TASK_ID}"
    _set_state "current_task_id" "${TASK_ID}"
    _set_state "task_status" "in_progress"

    # Run opencode on the task
    if command -v opencode >/dev/null 2>&1; then
        cd "${UOM_DIR}"
        opencode --non-interactive --task "${TASK_ID}" 2>&1 | tee -a "${LOG_FILE}"
        _exit_code=$?
    else
        _log "opencode not found — cannot process task"
        _exit_code=127
    fi

    if [ "${_exit_code}" -eq 0 ]; then
        _log "Task ${TASK_ID} completed"
        _complete_task "${TASK_ID}"
        _commit_and_push "${TASK_ID}"
        _set_state "task_status" "idle"
    else
        _log "Task ${TASK_ID} failed (rc=${_exit_code}) — will retry"
        _set_state "task_status" "failed"
        sleep 30
    fi
done
