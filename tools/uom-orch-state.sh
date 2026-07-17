#!/bin/sh
# tools/uom-orch-state.sh — Shared state functions (POSIX/BusyBox ash safe)
# Source this from both laptop and phone orchestrators
# POSIX-first: zero bashisms, zero eval, zero set --

_STATE_DIR="${OMNI_ROOT:-.}/.uom-agent"
_STATE_FILE="$_STATE_DIR/state.json"
_QUEUE_FILE="$_STATE_DIR/queue.json"
_DONE_FILE="$_STATE_DIR/done.json"
_HEARTBEAT_STALE_SECS=300

state_init() {
    mkdir -p "$_STATE_DIR/context"
    [ -f "$_STATE_FILE" ] || printf '{"schema":1,"active_agent":"none","laptop_heartbeat":"","phone_heartbeat":"","current_task_id":"","task_status":"idle","takeover_count":0}\n' > "$_STATE_FILE"
    [ -f "$_QUEUE_FILE" ] || printf '[]\n' > "$_QUEUE_FILE"
    [ -f "$_DONE_FILE"  ] || printf '[]\n' > "$_DONE_FILE"
}

state_get() {
    jq -r ".$1 // empty" "$_STATE_FILE" 2>/dev/null
}

state_set() {
    _field="$1"; _val="$2"
    _tmp="${_STATE_FILE}.tmp"
    jq ".$_field = \"$_val\"" "$_STATE_FILE" > "$_tmp" && mv "$_tmp" "$_STATE_FILE"
}

state_heartbeat() {
    _agent="$1"
    _now=$(date -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
    state_set "${_agent}_heartbeat" "$_now"
    state_set "active_agent" "$_agent"
}

state_laptop_stale() {
    _ts=$(state_get "laptop_heartbeat")
    [ -z "$_ts" ] && return 0
    _epoch_now=$(date -u +%s 2>/dev/null)
    _epoch_hb=$(date -u -d "$_ts" +%s 2>/dev/null) || \
        _epoch_hb=$(python3 -c "import datetime; print(int(datetime.datetime.fromisoformat('$_ts').timestamp()))" 2>/dev/null) || \
        _epoch_hb=0
    _diff=$(( _epoch_now - _epoch_hb ))
    [ "$_diff" -gt "$_HEARTBEAT_STALE_SECS" ]
}

state_next_task() {
    jq -r '[.[] | select(.status=="pending")] | first | .id // empty' "$_QUEUE_FILE" 2>/dev/null
}

state_task_desc() {
    jq -r --arg id "$1" '.[] | select(.id==$id) | .desc // empty' "$_QUEUE_FILE" 2>/dev/null
}

state_task_context() {
    _ctx_file=$(jq -r --arg id "$1" '.[] | select(.id==$id) | .context_file // empty' "$_QUEUE_FILE" 2>/dev/null)
    [ -n "$_ctx_file" ] && [ -f "${OMNI_ROOT:-.}/$_ctx_file" ] && cat "${OMNI_ROOT:-.}/$_ctx_file"
}

state_mark_task() {
    _id="$1"; _status="$2"
    _tmp="${_QUEUE_FILE}.tmp"
    jq --arg id "$_id" --arg st "$_status" \
       'map(if .id==$id then .status=$st else . end)' \
       "$_QUEUE_FILE" > "$_tmp" && mv "$_tmp" "$_QUEUE_FILE"
    if [ "$_status" = "done" ]; then
        _now=$(date -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
        _agent=$(state_get "active_agent")
        _tmp2="${_DONE_FILE}.tmp"
        jq --arg id "$_id" --arg t "$_now" --arg a "$_agent" \
           '. + [{"id":$id,"completed":$t,"by":$a}]' \
           "$_DONE_FILE" > "$_tmp2" && mv "$_tmp2" "$_DONE_FILE"
    fi
}

state_git_sync() {
    _msg="$1"
    cd "${OMNI_ROOT:-.}" || return 1
    git add .uom-agent/ 2>/dev/null
    git diff --cached --quiet && return 0
    git commit -m "$_msg" || return 1
    if [ "${UOM_ALLOW_PUSH:-0}" = "1" ]; then
        git push origin main 2>/dev/null || true
    fi
}

state_status() {
    _state_file="${OMNI_ROOT:-.}/.uom-agent/state.json"
    if [ ! -f "$_state_file" ]; then
        echo "STATE_FILE_NOT_FOUND"
        return 1
    fi

    _active_agent=$(jq -r '.active_agent // "unknown"' "$_state_file" 2>/dev/null || echo "unknown")
    _task_status=$(jq -r '.task_status // "idle"' "$_state_file" 2>/dev/null || echo "idle")
    _current_task=$(jq -r '.current_task_id // "none"' "$_state_file" 2>/dev/null || echo "none")

    echo "status: OK"
    echo "active_agent: ${_active_agent}"
    echo "task_status: ${_task_status}"
    echo "current_task_id: ${_current_task}"
    echo "last_commit: $(jq -r '.last_commit // "none"' "$_state_file" 2>/dev/null)"
    echo "takeover_count: $(jq -r '.takeover_count // 0' "$_state_file" 2>/dev/null)"
    echo "laptop_heartbeat: $(jq -r '.laptop_heartbeat // "none"' "$_state_file" 2>/dev/null)"
    echo "phone_heartbeat: $(jq -r '.phone_heartbeat // "none"' "$_state_file" 2>/dev/null)"
}

state_git_pull() {
    cd "${OMNI_ROOT:-.}" || return 1
    git pull --rebase origin main 2>/dev/null || true
}

# ── Recover in_progress tasks abandoned by crash ────────────────────────
# If an agent was processing a task and crashed (laptop power loss, etc.),
# the task is stuck in "in_progress". This checks if the heartbeat of the
# agent that claimed it is stale, and resets the task to "pending".
state_recover_in_progress() {
    _stuck=$(jq -r '[.[] | select(.status=="in_progress")] | first | .id // empty' "$_QUEUE_FILE" 2>/dev/null)
    [ -z "$_stuck" ] && return 0

    _claimed_by=$(state_get "active_agent")
    _hb=$(state_get "${_claimed_by}_heartbeat")
    if [ -z "$_hb" ]; then
        _log "No heartbeat for $_claimed_by — resetting $_stuck to pending"
        state_mark_task "$_stuck" "pending"
        return 0
    fi
    _epoch_now=$(date -u +%s 2>/dev/null)
    _epoch_hb=$(date -u -d "$_hb" +%s 2>/dev/null) || \
        _epoch_hb=$(python3 -c "import datetime; print(int(datetime.datetime.fromisoformat('$_hb').timestamp()))" 2>/dev/null) || \
        _epoch_hb=0
    _diff=$(( _epoch_now - _epoch_hb ))
    if [ "$_diff" -gt "$_HEARTBEAT_STALE_SECS" ]; then
        _log "Agent $_claimed_by stale (${_diff}s) — recovering stuck task $_stuck"
        state_mark_task "$_stuck" "pending"
        return 0
    fi
    return 1
}
