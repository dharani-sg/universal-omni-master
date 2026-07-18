#!/bin/sh
# tools/uom-feedback-aggregator.sh — Structured feedback aggregation
# Reads .result files, writes verified feedback JSON with jq (no heredocs).
# Singleton lock. Atomic writes. Conflict detection.
#
# Usage:
#   sh tools/uom-feedback-aggregator.sh            # one-shot
#   sh tools/uom-feedback-aggregator.sh --watch     # poll every 15s
#   sh tools/uom-feedback-aggregator.sh --dryrun    # validate only

set -u

UOM_DIR="${UOM_DIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
WATCH=0
DRYRUN=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --watch) WATCH=1; shift ;;
    --dryrun) DRYRUN=1; shift ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

# Source state lib
if [ -f "${UOM_DIR}/tools/uom-state-lib.sh" ]; then
  . "${UOM_DIR}/tools/uom-state-lib.sh"
  uom_state_init 2>/dev/null || true
fi

VERIFIED_DIR="${UOM_STATE_DIR:-${UOM_DIR}/.uom-agent}/verified"
FEEDBACK_DIR="${UOM_STATE_DIR:-${UOM_DIR}/.uom-agent}/feedback"
LOG_FILE="${UOM_LOG_DIR:-${UOM_DIR}/.uom-agent/logs}/feedback-aggregator.log"
LOCK_DIR="${UOM_RUNTIME_DIR:-${UOM_DIR}/.uom-agent/runtime}/feedback-agg.lock"
SUMMARY_FILE="${FEEDBACK_DIR}/summary.json"
HASH_CACHE="${FEEDBACK_DIR}/.hash_cache"

mkdir -p "$VERIFIED_DIR" "$FEEDBACK_DIR" "$(dirname "$LOCK_DIR")"

_log() {
  _ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u)"
  printf '[fb-agg] %s %s\n' "$_ts" "$*" | tee -a "$LOG_FILE"
}

_cleanup() {
  rm -rf "$LOCK_DIR" 2>/dev/null || true
}
trap '_cleanup' INT TERM EXIT

_acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "$$" > "$LOCK_DIR/pid"
    return 0
  fi
  _old_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
  if [ -n "$_old_pid" ] && kill -0 "$_old_pid" 2>/dev/null; then
    _log "already running (PID $_old_pid)"
    exit 0
  fi
  rm -rf "$LOCK_DIR" 2>/dev/null || true
  mkdir "$LOCK_DIR" 2>/dev/null || { _log "cannot acquire lock"; exit 1; }
  echo "$$" > "$LOCK_DIR/pid"
}

_sha256() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

_aggregate() {
  _pass=0
  _retry=0
  _blocked=0
  _unsafe=0
  _total=0
  _tasks_json="["
  _sep=""

  for _rf in "${VERIFIED_DIR}"/*.result; do
    [ -f "$_rf" ] || continue
    _total=$((_total + 1))

    _tid=$(jq -r '.task_id // "unknown"' "$_rf" 2>/dev/null || echo "unknown")
    _status=$(jq -r '.status // "unknown"' "$_rf" 2>/dev/null || echo "unknown")
    _reasons=$(jq -r '.reasons // ""' "$_rf" 2>/dev/null || echo "")
    _result_sha=$(_sha256 "$_rf")

    # Check attempt count
    _attempt=1
    _fb_file="${FEEDBACK_DIR}/${_tid}.json"
    if [ -f "$_fb_file" ]; then
      _attempt=$(jq -r '.attempt // 1' "$_fb_file" 2>/dev/null || echo 1)
      _attempt=$((_attempt + 1))
    fi

    # Determine verdict
    _verdict="PASS"
    case "$_status,$_attempt" in
      PASS,*) _verdict="PASS"; _pass=$((_pass + 1)) ;;
      FAIL,1|FAIL,2) _verdict="RETRY_WITH_FEEDBACK"; _retry=$((_retry + 1)) ;;
      FAIL,3|FAIL,4|FAIL,5) _verdict="BLOCKED"; _blocked=$((_blocked + 1)) ;;
      WARN,*) _verdict="PASS"; _pass=$((_pass + 1)) ;;
      *) _verdict="UNSAFE"; _unsafe=$((_unsafe + 1)) ;;
    esac

    if [ "$_verdict" = "RETRY_WITH_FEEDBACK" ] || [ "$_verdict" = "BLOCKED" ]; then
      # Read generator artifact SHA
      _gen_file="${UOM_STATE_DIR:-${UOM_DIR}/.uom-agent}/generated/${_tid}.sh"
      _gen_sha=""
      [ -f "$_gen_file" ] && _gen_sha=$(_sha256 "$_gen_file")

      _epoch=$(uom_state_get ownership_epoch 2>/dev/null || echo 0)

      # Build JSON with jq — no heredoc interpolation
      _fb_json=$(jq -n \
        --arg tid "$_tid" \
        --arg verdict "$_verdict" \
        --arg reasons "$_reasons" \
        --arg gen_sha "$_gen_sha" \
        --arg result_sha "$_result_sha" \
        --argjson attempt "$_attempt" \
        --argjson epoch "$_epoch" \
        --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" \
        '{
          task_id: $tid,
          verdict: $verdict,
          reasons: $reasons,
          generator_artifact_sha256: $gen_sha,
          verifier_result_sha256: $result_sha,
          ownership_epoch: $epoch,
          attempt: $attempt,
          max_attempts: 3,
          suggestion: "Review code, fix reported issues, regenerate",
          timestamp: $ts
        }' 2>/dev/null) || continue

      # Write atomically via temp file
      _tmp="${FEEDBACK_DIR}/${_tid}.json.tmp.$$"
      printf '%s\n' "$_fb_json" > "$_tmp"
      if jq empty "$_tmp" 2>/dev/null; then
        mv "$_tmp" "${FEEDBACK_DIR}/${_tid}.json"
        if [ "$DRYRUN" -eq 0 ]; then
          _log "feedback ${_verdict} for ${_tid} (attempt ${_attempt}): ${_reasons}"
        else
          _log "dryrun: would write feedback ${_verdict} for ${_tid}"
          rm -f "$_tmp"
        fi
      else
        _log "ERROR: invalid JSON for ${_tid}, skipping"
        rm -f "$_tmp"
      fi
    fi

    # Append to task list
    _tasks_json="${_tasks_json}${_sep}{\"id\":\"${_tid}\",\"verdict\":\"${_verdict}\"}"
    _sep=","
  done
  _tasks_json="${_tasks_json}]"

  # Write summary
  _summary=$(jq -n \
    --argjson pass "$_pass" \
    --argjson retry "$_retry" \
    --argjson blocked "$_blocked" \
    --argjson unsafe "$_unsafe" \
    --argjson total "$_total" \
    --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" \
    '{
      pass: $pass,
      retry_with_feedback: $retry,
      blocked: $blocked,
      unsafe: $unsafe,
      total: $total,
      timestamp: $ts
    }' 2>/dev/null) || {
    _log "ERROR: failed to build summary JSON"
    return 1
  }

  # Check if summary changed before writing
  _cached_hash=""
  [ -f "$SUMMARY_FILE" ] && _cached_hash=$(_sha256 "$SUMMARY_FILE")
  _new_hash=$(printf '%s' "$_summary" | sha256sum | cut -d' ' -f1)

  if [ "$_cached_hash" = "$_new_hash" ]; then
    # No change — skip rewrite
    _log "summary unchanged (${_pass} pass, ${_retry} retry, ${_blocked} blocked, ${_unsafe} unsafe)"
  else
    _tmp_s="${SUMMARY_FILE}.tmp.$$"
    printf '%s\n' "$_summary" > "$_tmp_s"
    if jq empty "$_tmp_s" 2>/dev/null; then
      if [ "$DRYRUN" -eq 0 ]; then
        mv "$_tmp_s" "$SUMMARY_FILE"
        _log "summary: ${_pass} pass, ${_retry} retry, ${_blocked} blocked, ${_unsafe} unsafe (${_total} total)"
      else
        _log "dryrun: would update summary"
        rm -f "$_tmp_s"
      fi
    else
      rm -f "$_tmp_s"
      _log "ERROR: invalid summary JSON"
    fi
  fi
}

main() {
  _acquire_lock
  _log "aggregator started${DRYRUN:+ (dryrun)}"

  if [ "$WATCH" -eq 1 ]; then
    _log "watch mode (poll=15s)"
    while true; do
      _aggregate
      sleep 15
    done
  else
    _aggregate
  fi

  _cleanup
}

main "$@"
