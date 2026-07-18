#!/bin/sh
# scripts/uom-generator.sh — Zen Loop Generator Agent (Window A)
# Pulls pending tasks from queue, calls free LLM, writes output.
# Designed to run inside PRoot Debian (phone) or natively (laptop).
#
# Communication: reads .uom-agent/queue.json, writes to .uom-agent/generated/
# Verifier (Window B) monitors generated/ for .ready markers.
#
# Environment:
#   UOM_DIR       — project root (default: auto-detect)
#   LLM_MODEL     — Model name (default: auto from setup-env.json)
#   LLM_CMD       — custom LLM command override (pipe-based)
#   POLL_INTERVAL — seconds between queue polls (default: 5)
#
# Usage: sh scripts/uom-generator.sh

set -u

UOM_DIR="${UOM_DIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"

# Source state library for lease/ownership checks
if [ -f "${UOM_DIR}/tools/uom-state-lib.sh" ]; then
    . "${UOM_DIR}/tools/uom-state-lib.sh"
    uom_state_init 2>/dev/null || true
    _HAS_STATE_LIB=1
else
    _HAS_STATE_LIB=0
fi

# Environment overrides for sandbox/burn-in mode
UOM_STATE_DIR="${UOM_STATE_DIR:-${UOM_DIR}/.uom-agent}"
UOM_QUEUE_FILE="${UOM_QUEUE_FILE:-${UOM_STATE_DIR}/queue.json}"
UOM_GEN_DIR="${UOM_GEN_DIR:-${UOM_STATE_DIR}/generated}"
UOM_LOG_DIR="${UOM_LOG_DIR:-${UOM_STATE_DIR}/logs}"
UOM_RUNTIME_DIR="${UOM_RUNTIME_DIR:-${UOM_STATE_DIR}/runtime}"

QUEUE_FILE="${UOM_QUEUE_FILE}"
GEN_DIR="${UOM_GEN_DIR}"
LOG_DIR="${UOM_LOG_DIR}"
LOG_FILE="${LOG_DIR}/generator.log"
LOCK_FILE="${UOM_RUNTIME_DIR}/gen.lock"
PID_FILE="${UOM_RUNTIME_DIR}/gen.pid"
SETUP_META="${UOM_STATE_DIR}/setup-env.json"
POLL_INTERVAL="${POLL_INTERVAL:-5}"

# ── Resolve LLM model from setup metadata or default ────────────────────
MODEL_POOL="opencode/deepseek-v4-flash-free opencode/nemotron-3-ultra-free opencode/north-mini-code-free opencode/big-pickle"
MODEL_ROTATION_SECS=1800
MODEL_FILE="${UOM_DIR}/.uom-agent/runtime/selected_model"
mkdir -p "$(dirname "$MODEL_FILE")"

_rotate_model() {
    _now=$(date +%s 2>/dev/null || echo 0)
    _last_ts=0
    if [ -f "$MODEL_FILE" ]; then
        _last_ts=$(stat -c %Y "$MODEL_FILE" 2>/dev/null || echo 0)
    fi
    _age=$((_now - _last_ts))
    if [ "$_age" -lt "$MODEL_ROTATION_SECS" ] && [ -s "$MODEL_FILE" ]; then
        cat "$MODEL_FILE"
        return 0
    fi
    _count=0
    for _m in $MODEL_POOL; do _count=$((_count + 1)); done
    _idx=$((_now / MODEL_ROTATION_SECS % _count))
    _i=0
    for _m in $MODEL_POOL; do
        if [ "$_i" -eq "$_idx" ]; then
            printf '%s' "$_m" > "$MODEL_FILE"
            printf '%s' "$_m"
            return 0
        fi
        _i=$((_i + 1))
    done
    printf '%s' "opencode/deepseek-v4-flash-free" > "$MODEL_FILE"
    printf '%s' "opencode/deepseek-v4-flash-free"
}

if [ -z "${LLM_MODEL:-}" ]; then
    LLM_MODEL=$(_rotate_model)
fi
LLM_MODEL="${LLM_MODEL:-opencode/deepseek-v4-flash-free}"

mkdir -p "$LOG_DIR" "$GEN_DIR" "$(dirname "$LOCK_FILE")"

# ── Logging ─────────────────────────────────────────────────────────────
_log() {
    _ts=$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date)
    _msg="[generator] ${_ts} $*"
    printf '%s\n' "$_msg" | tee -a "$LOG_FILE"
}

# ── Cleanup ─────────────────────────────────────────────────────────────
_cleanup() {
    rm -f "$LOCK_FILE" "$PID_FILE" 2>/dev/null || true
    _log "Generator agent stopped"
}
trap '_cleanup' HUP INT TERM

# ── Singleton guard ─────────────────────────────────────────────────────
_acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        _old=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$_old" ] && kill -0 "$_old" 2>/dev/null; then
            _log "Another generator is running (PID ${_old}) — exiting"
            exit 0
        fi
        _log "Stale lock from PID ${_old} — reclaiming"
        rm -f "$LOCK_FILE" 2>/dev/null || true
    fi
    echo "$$" > "$LOCK_FILE"
    echo "$$" > "$PID_FILE"
}

# ── Android resource check (Phantom Process Killer avoidance) ───────────
_check_resources() {
    if [ ! -f /proc/meminfo ]; then
        return 0
    fi

    _mem_avail=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null || echo "999999")
    _mem_min=204800  # 200MB minimum

    if [ "${_mem_avail:-999999}" -lt "$_mem_min" ] 2>/dev/null; then
        _log "Low memory: $((_mem_avail / 1024))MB — backing off 30s"
        sleep 30
        return 1
    fi

    _load=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0")
    _load_int=$(echo "$_load" | cut -d. -f1)
    if [ "${_load_int:-0}" -ge 4 ] 2>/dev/null; then
        _log "High load: ${_load} — backing off 15s"
        sleep 15
        return 1
    fi

    return 0
}

# ── Read first pending task from queue ──────────────────────────────────
_read_pending_task() {
    if [ ! -f "$QUEUE_FILE" ]; then
        return 1
    fi

    _task_id=$(jq -r '
        [.[] | select(.status == "pending")]
        | sort_by(.priority // 99)
        | first
        | .id // empty
    ' "$QUEUE_FILE" 2>/dev/null)

    if [ -z "$_task_id" ]; then
        return 1
    fi

    _task_desc=$(jq -r --arg id "$_task_id" '
        [.[] | select(.id == $id)]
        | first
        | .desc // "no description"
    ' "$QUEUE_FILE" 2>/dev/null)

    _task_ctx=""
    _ctx_file=$(jq -r --arg id "$_task_id" '
        [.[] | select(.id == $id)]
        | first
        | .context_file // empty
    ' "$QUEUE_FILE" 2>/dev/null)
    if [ -n "$_ctx_file" ] && [ -f "${UOM_DIR}/${_ctx_file}" ]; then
        _task_ctx=$(cat "${UOM_DIR}/${_ctx_file}" 2>/dev/null | head -100)
    fi

    # Check for feedback from previous failures
    _fb_file="${UOM_DIR}/.uom-agent/feedback/${_task_id}.json"
    if [ -f "$_fb_file" ]; then
        _fb_issues=$(jq -r '.issues // empty' "$_fb_file" 2>/dev/null || echo "")
        _fb_suggestion=$(jq -r '.suggestion // empty' "$_fb_file" 2>/dev/null || echo "")
        if [ -n "$_fb_issues" ] || [ -n "$_fb_suggestion" ]; then
            _task_ctx="${_task_ctx}
PREVIOUS FEEDBACK (retry):
  Issues: ${_fb_issues:-none}
  Suggestion: ${_fb_suggestion:-none}"
        fi
    fi

    return 0
}

# ── Mark task status in queue ───────────────────────────────────────────
_mark_task() {
    _task_id="$1"
    _new_status="$2"
    _extra="${3:-}"

    _tmp="${QUEUE_FILE}.gen.$$"
    if [ -n "$_extra" ]; then
        jq --arg id "$_task_id" --arg st "$_new_status" --arg ex "$_extra" \
            'map(if .id == $id then .status = $st | .generator_note = $ex else . end)' \
            "$QUEUE_FILE" > "$_tmp" 2>/dev/null && mv "$_tmp" "$QUEUE_FILE"
    else
        jq --arg id "$_task_id" --arg st "$_new_status" \
            'map(if .id == $id then .status = $st else . end)' \
            "$QUEUE_FILE" > "$_tmp" 2>/dev/null && mv "$_tmp" "$QUEUE_FILE"
    fi
}

# ── Cloud LLM call via opencode CLI ────────────────────────────────────
_call_llm_cloud() {
    _prompt="$1"
    _output="$2"
    _model="${LLM_MODEL:-opencode/deepseek-v4-flash-free}"
    _max_retries=3
    _retry=0
    _llm_timeout=120

    _use_local=0
    if command -v opencode >/dev/null 2>&1; then
        if [ -d /system ] 2>/dev/null || [ -f /data/data/com.termux/files/usr/bin/opencode ] 2>/dev/null; then
            _log "Android/Termux detected — skipping local opencode, using remote"
        else
            _use_local=1
        fi
    fi

    if [ "$_use_local" -eq 1 ]; then
        _log "opencode run (local) → ${_model}"
        while [ "$_retry" -lt "$_max_retries" ]; do
            _log "Attempt $((_retry + 1))..."
            printf '%s\n' "$_prompt" | timeout "$_llm_timeout" opencode run --model "$_model" > "$_output" 2>>"$LOG_FILE"

            if [ -s "$_output" ]; then
                sed -i '/^```/d' "$_output" 2>/dev/null
                _log "Generated $(wc -l < "$_output") lines"
                return 0
            fi

            _retry=$((_retry + 1))
            [ "$_retry" -lt "$_max_retries" ] && { _log "Retry ${_retry}/${_max_retries} in 10s"; sleep 10; }
        done
    fi

    _retry=0
    _remote_script="${UOM_DIR}/scripts/uom-llm-remote.sh"
    if [ -f "$_remote_script" ]; then
        _log "opencode (remote via laptop) → ${_model}"
        while [ "$_retry" -lt "$_max_retries" ]; do
            _log "Attempt $((_retry + 1))..."
            printf '%s\n' "$_prompt" | timeout "$_llm_timeout" sh "$_remote_script" "$_model" > "$_output" 2>>"$LOG_FILE"

            if [ -s "$_output" ]; then
                sed -i '/^```/d' "$_output" 2>/dev/null
                _log "Generated $(wc -l < "$_output") lines (remote)"
                return 0
            fi

            _retry=$((_retry + 1))
            [ "$_retry" -lt "$_max_retries" ] && { _log "Retry ${_retry}/${_max_retries} in 10s"; sleep 10; }
        done
    fi

    _log "All attempts failed — stub fallback"
    _generate_stub "$_prompt" "$_output"
    return 0
}

# ── Generate stub (fallback when cloud API unavailable) ─────────────────
_generate_stub() {
    _prompt="$1"
    _output="$2"
    _task_id=$(printf '%s' "$_prompt" | grep -om1 'Task ID: [^ ]*' | sed 's/Task ID: //' || echo 'unknown')

    cat > "$_output" << STUBEOF
#!/bin/sh
# Auto-generated stub — opencode cloud API unavailable
# Task: ${_task_id}
# Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)
set -u
echo "Stub: implement ${_task_id} manually"
exit 1
STUBEOF
    _log "Stub generated for task ${_task_id}"
    return 0
}

# ── Build prompt for a task ─────────────────────────────────────────────
_build_prompt() {
    _task_id="$1"
    _task_desc="$2"
    _task_ctx="$3"

    _prompt="You are a POSIX shell script generator for the UOM (Universal Omni Master) orchestrator project.
Generate a complete, working shell script. Output ONLY executable code — no markdown fences, no explanations.

PROJECT CONTEXT:
- This is a dual-agent orchestrator for Android (Termux) + Linux (Alpine) devices
- Scripts use POSIX sh (no bashisms), set -u, proper error handling
- State is stored in .uom-agent/state.json (JSON, managed via jq)
- Queue is in .uom-agent/queue.json
- Tests: scripts/uom-dryrun.sh

TASK:
- ID: ${_task_id}
- Description: ${_task_desc}
"

    if [ -n "$_task_ctx" ]; then
        _prompt="${_prompt}
ADDITIONAL CONTEXT:
${_task_ctx}
"
    fi

    _prompt="${_prompt}
REQUIREMENTS:
1. Output a complete, runnable .sh script
2. Use POSIX sh only (no bash-specific syntax)
3. Start with: #!/bin/sh and set -u
4. Include function-level error handling
5. Be concise and production-ready
6. Use the project's existing patterns (see bin/ for examples)

OUTPUT: Just the script code, nothing else."

    printf '%s' "$_prompt"
}

# ── Main loop ───────────────────────────────────────────────────────────
main() {
    _acquire_lock
    _log "Generator agent starting (model=${LLM_MODEL}, poll=${POLL_INTERVAL}s)"
    _log "PID: $$, queue: ${QUEUE_FILE}, output: ${GEN_DIR}"

    _cycle=0
    while true; do
        _cycle=$((_cycle + 1))

        # Resource gating
        if ! _check_resources; then
            continue
        fi

        # Read pending task
        if ! _read_pending_task; then
            if [ "$((_cycle % 60))" -eq 0 ] 2>/dev/null; then
                _log "Idle — no pending tasks (cycle ${_cycle})"
            fi
            sleep "$POLL_INTERVAL"
            continue
        fi

        # Skip if already generated (idempotent)
        if [ -f "${GEN_DIR}/${_task_id}.ready" ] || [ -f "${GEN_DIR}/${_task_id}.done" ]; then
            _log "Task ${_task_id}: already generated — marking in_progress"
            _mark_task "$_task_id" "in_progress" "generated-already-existed"
            sleep "$POLL_INTERVAL"
            continue
        fi

        _log "━━━ Task ${_task_id}: ${_task_desc}"

        # Check state lease before claiming task
        _may_write=0
        if [ "$_HAS_STATE_LIB" -eq 1 ]; then
            if uom_state_can_write phone 2>/dev/null; then
                _may_write=1
            fi
        else
            # No state lib — allow (backward compat)
            _may_write=1
        fi

        if [ "$_may_write" -eq 1 ]; then
            _mark_task "$_task_id" "in_progress" "generator-picked-up"
        else
            _log "WARNING: no write lease (writer_role=$(uom_state_get writer_role 2>/dev/null || echo unknown)) — processing without queue mutation"
        fi

        # Build prompt
        _prompt=$(_build_prompt "$_task_id" "$_task_desc" "$_task_ctx")

        # Generate output
        _output_file="${GEN_DIR}/${_task_id}.sh"
        _log "Calling LLM..."
        _start_ts=$(date +%s 2>/dev/null || echo 0)

        if _call_llm_cloud "$_prompt" "$_output_file"; then
            _end_ts=$(date +%s 2>/dev/null || echo 0)
            _elapsed=$((_end_ts - _start_ts))

            if [ -s "$_output_file" ]; then
                _lines=$(wc -l < "$_output_file" 2>/dev/null || echo 0)
                # Create ready marker with metadata
                cat > "${GEN_DIR}/${_task_id}.ready" << READYEOF
{
  "task_id": "${_task_id}",
  "generated_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)",
  "generator_pid": $$,
  "model": "${LLM_MODEL}",
  "lines": ${_lines},
  "elapsed_sec": ${_elapsed}
}
READYEOF
                _log "✓ Generated ${_lines} lines in ${_elapsed}s — ready for verifier"
            else
                _log "✗ LLM produced empty output for ${_task_id}"
                [ "$_may_write" -eq 1 ] && _mark_task "$_task_id" "pending" "llm-empty-output"
                rm -f "$_output_file" 2>/dev/null || true
            fi
        else
            _log "✗ LLM call failed for ${_task_id}"
            [ "$_may_write" -eq 1 ] && _mark_task "$_task_id" "pending" "llm-call-failed"
            rm -f "$_output_file" 2>/dev/null || true
        fi

        sleep "$POLL_INTERVAL"
    done
}

main "$@"
