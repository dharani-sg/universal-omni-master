#!/bin/sh
# tools/uom-feedback-aggregator.sh — Aggregate verifier results into summary
# Reads all .uom-agent/verified/*.result files.
# Writes summary to .uom-agent/feedback/summary.json.
# Writes per-task feedback to .uom-agent/feedback/{task_id}.json for FAIL.
#
# Usage: sh tools/uom-feedback-aggregator.sh [--watch]

set -u

UOM_DIR="${UOM_DIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
WATCH=0
[ "${1:-}" = "--watch" ] && WATCH=1

. "${UOM_DIR}/tools/uom-state-lib.sh"
uom_state_init

VERIFIED_DIR="${UOM_STATE_DIR}/verified"
FEEDBACK_DIR="${UOM_STATE_DIR}/feedback"
LOG_FILE="${UOM_LOG_DIR}/feedback-aggregator.log"

mkdir -p "$VERIFIED_DIR" "$FEEDBACK_DIR" "$UOM_LOG_DIR"

_log() {
    _ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u)"
    printf '[fb-agg] %s %s\n' "$_ts" "$*" | tee -a "$LOG_FILE"
}

_aggregate() {
    _pass=0
    _fail=0
    _warn=0
    _total=0

    _summary='{"pass":0,"fail":0,"warn":0,"tasks":[]}'

    for _rf in "${VERIFIED_DIR}"/*.result; do
        [ -f "$_rf" ] || continue
        _total=$((_total + 1))

        _tid=$(jq -r '.task_id // "unknown"' "$_rf" 2>/dev/null || echo "unknown")
        _status=$(jq -r '.status // "unknown"' "$_rf" 2>/dev/null || echo "unknown")
        _reasons=$(jq -r '.reasons // ""' "$_rf" 2>/dev/null || echo "")

        case "$_status" in
            PASS) _pass=$((_pass + 1)) ;;
            FAIL)
                _fail=$((_fail + 1))
                # Write per-task feedback
                cat > "${FEEDBACK_DIR}/${_tid}.json" << EOF
{
  "task_id": "${_tid}",
  "feedback_for": "generator",
  "result": "FAIL",
  "issues": "${_reasons}",
  "suggestion": "Fix the reported issues and regenerate",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u)"
}
EOF
                _log "feedback written for ${_tid}: ${_reasons}"
                ;;
            WARN) _warn=$((_warn + 1)) ;;
        esac

        _summary=$(printf '%s' "$_summary" | jq \
            --arg tid "$_tid" \
            --arg st "$_status" \
            --arg re "$_reasons" \
            '.tasks += [{"id": $tid, "status": $st, "reasons": $re}]' \
            2>/dev/null || echo "$_summary")
    done

    _summary=$(printf '%s' "$_summary" | jq \
        --argjson p "$_pass" \
        --argjson f "$_fail" \
        --argjson w "$_warn" \
        '.pass = $p | .fail = $f | .warn = $w' \
        2>/dev/null || echo '{"pass":0,"fail":0,"warn":0}')

    printf '%s\n' "$_summary" > "${FEEDBACK_DIR}/summary.json"
    _log "aggregated: ${_pass} pass, ${_fail} fail, ${_warn} warn (${_total} total)"
}

main() {
    _log "feedback aggregator started"

    if [ "$WATCH" -eq 1 ]; then
        _log "watch mode enabled (poll=15s)"
        while true; do
            _aggregate
            sleep 15
        done
    else
        _aggregate
    fi
}

main "$@"
