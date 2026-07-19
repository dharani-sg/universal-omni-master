#!/bin/sh
# scripts/uom-verifier.sh — Zen Loop Verifier Agent (Window B)
# Monitors Generator output, runs syntax/policy/dry-run checks,
# writes structured feedback. Communicates via .uom-agent/generated/
# and .uom-agent/verified/ directories.
#
# Usage: sh scripts/uom-verifier.sh

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
UOM_VERIFIED_DIR="${UOM_VERIFIED_DIR:-${UOM_STATE_DIR}/verified}"
UOM_LOG_DIR="${UOM_LOG_DIR:-${UOM_STATE_DIR}/logs}"
UOM_RUNTIME_DIR="${UOM_RUNTIME_DIR:-${UOM_STATE_DIR}/runtime}"

QUEUE_FILE="${UOM_QUEUE_FILE}"
GEN_DIR="${UOM_GEN_DIR}"
VERIFIED_DIR="${UOM_VERIFIED_DIR}"
LOG_DIR="${UOM_LOG_DIR}"
LOG_FILE="${LOG_DIR}/verifier.log"
LOCK_FILE="${UOM_RUNTIME_DIR}/ver.lock"
PID_FILE="${UOM_RUNTIME_DIR}/ver.pid"
POLL_INTERVAL="${POLL_INTERVAL:-5}"

mkdir -p "$LOG_DIR" "$GEN_DIR" "$VERIFIED_DIR" "$(dirname "$LOCK_FILE")"

# ── Logging ─────────────────────────────────────────────────────────────
_log() {
    _ts=$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date)
    _msg="[verifier] ${_ts} $*"
    printf '%s\n' "$_msg" | tee -a "$LOG_FILE"
}

# ── Cleanup ─────────────────────────────────────────────────────────────
_cleanup() {
    rm -f "$LOCK_FILE" "$PID_FILE" 2>/dev/null || true
    _log "Verifier agent stopped"
}
trap '_cleanup' HUP INT TERM

# ── Singleton guard ─────────────────────────────────────────────────────
_acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        _old=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$_old" ] && kill -0 "$_old" 2>/dev/null; then
            _log "Another verifier is running (PID ${_old}) — exiting"
            exit 0
        fi
        _log "Stale lock from PID ${_old} — reclaiming"
        rm -f "$LOCK_FILE" 2>/dev/null || true
    fi
    echo "$$" > "$LOCK_FILE"
    echo "$$" > "$PID_FILE"
}

# ── Resource check (Phantom Process Killer avoidance) ───────────────────
_check_resources() {
    if [ ! -f /proc/meminfo ]; then
        return 0
    fi
    _mem_avail=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null || echo "999999")
    if [ "${_mem_avail:-999999}" -lt 204800 ] 2>/dev/null; then
        _log "Low memory: $((_mem_avail / 1024))MB — backing off 30s"
            _safe_sleep 30
        return 1
    fi
    return 0
}

# ── Syntax check ────────────────────────────────────────────────────────
_check_syntax() {
    _file="$1"
    _ext="${_file##*.}"

    case "$_ext" in
        sh)
            if sh -n "$_file" 2>/dev/null; then
                echo "PASS"
            else
                echo "FAIL:syntax"
            fi
            ;;
        py)
            if command -v python3 >/dev/null 2>&1; then
                if python3 -m py_compile "$_file" 2>/dev/null; then
                    echo "PASS"
                else
                    echo "FAIL:syntax"
                fi
            else
                echo "PASS:no-interpreter"
            fi
            ;;
        *)
            echo "PASS:unchecked-ext"
            ;;
    esac
}

# ── Policy checks (matching uom-dryrun.sh patterns) ─────────────────────
_check_policy() {
    _file="$1"
    _issues=""

    # No curl-pipe-shell
    if grep -qE 'curl.*\|.*sh|curl.*\|.*bash' "$_file" 2>/dev/null; then
        _issues="${_issues}curl-pipe-shell,"
    fi

    # No sudo/doas in orchestrators
    if grep -qE '\bsudo\b|\bdoas\b' "$_file" 2>/dev/null; then
        _issues="${_issues}privilege-escalation,"
    fi

    # No hardcoded 18022
    if grep -q '18022' "$_file" 2>/dev/null; then
        _issues="${_issues}deprecated-port-18022,"
    fi

    # No unsafe /tmp writes
    if grep -q '> /tmp/' "$_file" 2>/dev/null; then
        _issues="${_issues}unsafe-tmp-write,"
    fi

    # Check for set -u (best practice)
    if ! grep -q 'set -u' "$_file" 2>/dev/null; then
        _issues="${_issues}missing-set-u,"
    fi

    # Check for shebang
    _shebang=$(head -1 "$_file" 2>/dev/null)
    case "$_shebang" in
        #!/bin/sh|#!/usr/bin/env\ sh) ;;
        *) _issues="${_issues}bad-shebang," ;;
    esac

    if [ -z "$_issues" ]; then
        echo "PASS"
    else
        # Remove trailing comma
        echo "WARN:${_issues%,}"
    fi
}

# ── Dry-run integration ────────────────────────────────────────────────
_check_dryrun() {
    if [ -f "${UOM_DIR}/scripts/uom-dryrun.sh" ]; then
        _dry_out=$(cd "$UOM_DIR" && sh scripts/uom-dryrun.sh 2>&1 | tail -5)
        if echo "$_dry_out" | grep -q 'RESULT: PASS'; then
            echo "PASS"
        else
            _fail_summary=$(echo "$_dry_out" | grep 'RESULT:' | head -1)
            echo "FAIL:${_fail_summary}"
        fi
    elif [ -f "${UOM_DIR}/bin/uom-status.sh" ]; then
        # Fallback: just run status check
        if sh "${UOM_DIR}/bin/uom-status.sh" >/dev/null 2>&1; then
            echo "PASS"
        else
            echo "WARN:status-check-failed"
        fi
    else
        echo "SKIP:no-checker"
    fi
}

# ── Verify a single generated file ──────────────────────────────────────
_verify_one() {
    _task_id="$1"
    _gen_file="${GEN_DIR}/${_task_id}.sh"
    _result_file="${VERIFIED_DIR}/${_task_id}.result"

    # Skip if already verified
    if [ -f "$_result_file" ]; then
        return 0
    fi

    _log "━━━ Verifying: ${_task_id}"

    # Check file exists and non-empty
    if [ ! -s "$_gen_file" ]; then
        _log "  FAIL: generated file empty or missing"
        printf '{"task":"%s","status":"FAIL","reason":"empty_output","at":"%s"}\n' \
            "$_task_id" "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" > "$_result_file"
        _update_queue "$_task_id" "failed" "verifier:empty_output"
        return 1
    fi

    # 1. Syntax check
    _syntax=$(_check_syntax "$_gen_file")
    _log "  Syntax: ${_syntax}"

    # 2. Policy check
    _policy=$(_check_policy "$_gen_file")
    _log "  Policy: ${_policy}"

    # 3. Dry-run check (only every Nth cycle to avoid overhead)
    _dryrun="SKIP"
    if [ -f "${GEN_DIR}/${_task_id}.ready" ]; then
        _ready_age=$(awk -F'"' '/generated_at/{print $4}' "${GEN_DIR}/${_task_id}.ready" 2>/dev/null || echo "")
        # Only dry-run on first verification
        _dryrun=$(_check_dryrun)
        _log "  Dryrun: ${_dryrun}"
    fi

    # Determine overall result
    _overall="PASS"
    _reasons=""

    case "$_syntax" in
        FAIL*) _overall="FAIL"; _reasons="${_reasons}syntax:"; _reasons="${_reasons}${_syntax#FAIL:}," ;;
    esac

    case "$_policy" in
        FAIL*) _overall="FAIL"; _reasons="${_reasons}policy:"; _reasons="${_reasons}${_policy#FAIL:}," ;;
        WARN*) 
            if [ "$_overall" != "FAIL" ]; then
                _overall="WARN"
            fi
            _reasons="${_reasons}policy-warn:${_policy#WARN:}," ;;
    esac

    case "$_dryrun" in
        FAIL*) _overall="FAIL"; _reasons="${_reasons}dryrun:"; _reasons="${_reasons}${_dryrun#FAIL:}," ;;
    esac

    # Write structured result
    cat > "$_result_file" << RESULTEOF
{
  "task_id": "${_task_id}",
  "status": "${_overall}",
  "syntax": "${_syntax}",
  "policy": "${_policy}",
  "dryrun": "${_dryrun}",
  "reasons": "${_reasons%,}",
  "verified_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)",
  "verifier_pid": $$
}
RESULTEOF

    if [ "$_overall" = "PASS" ]; then
        _log "  ✓ PASS"
    elif [ "$_overall" = "WARN" ]; then
        _log "  ⚠ WARN: ${_reasons%,}"
    else
        _log "  ✗ FAIL: ${_reasons%,}"
    fi

    # Update queue
    case "$_overall" in
        PASS) _update_queue "$_task_id" "verified" "verifier:pass" ;;
        WARN) _update_queue "$_task_id" "verified" "verifier:pass-with-warnings" ;;
        FAIL)
            # Check retry eligibility
            _task_obj=$(jq -c "map(select(.id == \"$_task_id\")) | .[0]" "$QUEUE_FILE" 2>/dev/null)
            _max_attempts=$(echo "$_task_obj" | jq -r '.max_attempts // 1')
            _attempts=$(echo "$_task_obj" | jq -r '.attempts // 0')
            _new_attempts=$((_attempts + 1))
            if [ "$_new_attempts" -lt "$_max_attempts" ]; then
                _log "  → Retry ${_new_attempts}/${_max_attempts}"
                _update_queue "$_task_id" "pending" "verifier:retry-${_new_attempts}"
                # Bump attempts counter
                jq "(map(if .id == \"$_task_id\" then .attempts = $_new_attempts else . end))" "$QUEUE_FILE" > "${QUEUE_FILE}.tmp" && mv "${QUEUE_FILE}.tmp" "$QUEUE_FILE" || true
            else
                _log "  ✗ FAIL (retries exhausted ${_attempts}/${_max_attempts})"
                _update_queue "$_task_id" "failed" "verifier:${_reasons%,}"
            fi
            ;;
    esac

    # Move .ready to .done
    mv "${GEN_DIR}/${_task_id}.ready" "${GEN_DIR}/${_task_id}.done" 2>/dev/null || true

    return 0
}

# ── Update task status in queue ─────────────────────────────────────────
_update_queue() {
    _task_id="$1"
    _new_status="$2"
    _note="$3"

    if [ ! -f "$QUEUE_FILE" ]; then
        return
    fi

    _tmp="${QUEUE_FILE}.ver.$$"
    jq --arg id "$_task_id" --arg st "$_new_status" --arg nt "$_note" \
        'map(if .id == $id then .status = $st | .verifier_note = $nt else . end)' \
        "$QUEUE_FILE" > "$_tmp" 2>/dev/null && mv "$_tmp" "$QUEUE_FILE"
}

# ── Write feedback for generator ────────────────────────────────────────
_write_feedback() {
    _task_id="$1"
    _result="$2"
    _reasons="$3"

    _fb_dir="${UOM_DIR}/.uom-agent/feedback"
    mkdir -p "$_fb_dir"

    # Only write feedback for failures (generator should retry differently)
    case "$_result" in
        FAIL)
            cat > "${_fb_dir}/${_task_id}.json" << FBEOF
{
  "task_id": "${_task_id}",
  "feedback_for": "generator",
  "result": "${_result}",
  "issues": "${_reasons}",
  "suggestion": "Fix the reported issues and regenerate",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)"
}
FBEOF
            _log "Feedback written for ${_task_id}"
            ;;
    esac
}

# ── Signal-safe sleep ──────────────────────────────────────────────────
_safe_sleep() { sleep "$1" & wait $! 2>/dev/null; }

# ── Main loop ───────────────────────────────────────────────────────────
main() {
    _acquire_lock
    _cleanup_sig() { _log "Shutting down (signal)"; rm -f "$LOCK_FILE" "$PID_FILE" 2>/dev/null; exit 0; }
    trap _cleanup_sig TERM INT
    _log "Verifier agent starting (poll=${POLL_INTERVAL}s)"
    _log "PID: $$, watching: ${GEN_DIR}, results: ${VERIFIED_DIR}"

    _cycle=0
    while true; do
        _cycle=$((_cycle + 1))

        # Resource gating
        if ! _check_resources; then
            continue
        fi

        # Scan for .ready files
        _found=0
        for _ready_file in "${GEN_DIR}"/*.ready; do
            # glob returns literal if no match
            [ -f "$_ready_file" ] || continue

            _task_id=$(basename "$_ready_file" .ready)

            # Skip if already verified
            if [ -f "${VERIFIED_DIR}/${_task_id}.result" ]; then
                continue
            fi

            _found=$((_found + 1))

            if _verify_one "$_task_id"; then
                # Read result for feedback
                _status=$(jq -r '.status // "unknown"' "${VERIFIED_DIR}/${_task_id}.result" 2>/dev/null || echo "unknown")
                _reasons=$(jq -r '.reasons // ""' "${VERIFIED_DIR}/${_task_id}.result" 2>/dev/null || echo "")

                case "$_status" in
                    FAIL)
                        _write_feedback "$_task_id" "$_status" "$_reasons"
                        ;;
                esac
            fi
        done

        # Periodic summary
        if [ "$((_cycle % 120))" -eq 0 ] 2>/dev/null; then
            _gen_count=$(ls "${GEN_DIR}"/*.ready 2>/dev/null | wc -l || echo "0")
            _ver_count=$(ls "${VERIFIED_DIR}"/*.result 2>/dev/null | wc -l || echo "0")
            _log "Status: ${_gen_count} pending verification, ${_ver_count} total verified (cycle ${_cycle})"
        fi

        if [ "$_found" -eq 0 ]; then
            _safe_sleep "$POLL_INTERVAL"
        fi
    done
}

main "$@"
