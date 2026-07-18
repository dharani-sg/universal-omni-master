#!/bin/sh
# tests/test-zen-loop-e2e.sh — End-to-End Zen Loop acceptance test
# Validates the full pipeline: generator → verifier → feedback.
# Designed for overnight burn-in (PHASE17).
#
# Usage: sh tests/test-zen-loop-e2e.sh [--hours N] [--once]

set -u

UOM_DIR="${UOM_DIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
ONCE=0
BURNIN_HOURS="${UOM_BURNIN_HOURS:-8}"

for _a in "$@"; do
    case "$_a" in
        --once) ONCE=1 ;;
        --hours) BURNIN_HOURS="$2"; shift ;;
    esac
    shift 2>/dev/null || true
done

. "${UOM_DIR}/tools/uom-state-lib.sh"
uom_state_init

LOG_DIR="${UOM_LOG_DIR}"
LOG_FILE="${LOG_DIR}/burnin-e2e.log"
SUMMARY_FILE="${UOM_STATE_DIR}/burnin-summary.json"
_BURNIN_START=$(date -u +%s)

mkdir -p "$LOG_DIR" "$UOM_STATE_DIR"

_log() {
    _ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u)"
    printf '[burnin-e2e] %s %s\n' "$_ts" "$*" | tee -a "$LOG_FILE"
}

_pass() { printf '  PASS: %s\n' "$*"; }
_fail() { printf '  FAIL: %s\n' "$*"; _ALL_FAIL=$((_ALL_FAIL + 1)); }
_warn() { printf '  WARN: %s\n' "$*"; }

_ALL_PASS=0
_ALL_FAIL=0
_ALL_WARN=0
_CYCLE=0

_check_generator() {
    _pid_file="${UOM_RUNTIME_DIR}/gen.pid"
    if [ -f "$_pid_file" ]; then
        _pid=$(cat "$_pid_file" 2>/dev/null)
        if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
            _pass "generator running (PID ${_pid})"
            return 0
        fi
    fi
    # Also check tmux
    _tmux_out=$(tmux list-windows -t uom-hybrid 2>/dev/null | grep generator || true)
    if [ -n "$_tmux_out" ]; then
        _pass "generator window exists in tmux"
        return 0
    fi
    _warn "generator not detected"
    return 1
}

_check_verifier() {
    _pid_file="${UOM_RUNTIME_DIR}/ver.pid"
    if [ -f "$_pid_file" ]; then
        _pid=$(cat "$_pid_file" 2>/dev/null)
        if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
            _pass "verifier running (PID ${_pid})"
            return 0
        fi
    fi
    _tmux_out=$(tmux list-windows -t uom-hybrid 2>/dev/null | grep verifier || true)
    if [ -n "$_tmux_out" ]; then
        _pass "verifier window exists in tmux"
        return 0
    fi
    _warn "verifier not detected"
    return 1
}

_check_queue() {
    if [ ! -f "$UOM_QUEUE_FILE" ]; then
        _warn "queue.json missing"
        return 1
    fi
    _pending=$(jq -r '[.[] | select(.status == "pending")] | length' "$UOM_QUEUE_FILE" 2>/dev/null || echo 0)
    _in_prog=$(jq -r '[.[] | select(.status == "in_progress")] | length' "$UOM_QUEUE_FILE" 2>/dev/null || echo 0)
    _verified=$(jq -r '[.[] | select(.status == "verified")] | length' "$UOM_QUEUE_FILE" 2>/dev/null || echo 0)
    _failed=$(jq -r '[.[] | select(.status == "failed")] | length' "$UOM_QUEUE_FILE" 2>/dev/null || echo 0)
    _log "queue: ${_pending} pending, ${_in_prog} in_progress, ${_verified} verified, ${_failed} failed"
}

_check_generated_output() {
    _gen_dir="${UOM_STATE_DIR}/generated"
    _rdy=$(find "$_gen_dir" -name '*.ready' 2>/dev/null | wc -l)
    _dne=$(find "$_gen_dir" -name '*.done' 2>/dev/null | wc -l)
    _log "generated: ${_rdy} ready, ${_dne} done"
}

_check_verified_output() {
    _ver_dir="${UOM_STATE_DIR}/verified"
    _results=$(find "$_ver_dir" -name '*.result' 2>/dev/null | wc -l)
    _log "verified: ${_results} results"
}

_check_feedback() {
    _fb_dir="${UOM_STATE_DIR}/feedback"
    _summary="${_fb_dir}/summary.json"
    if [ -f "$_summary" ]; then
        _p=$(jq -r '.pass // 0' "$_summary" 2>/dev/null)
        _f=$(jq -r '.fail // 0' "$_summary" 2>/dev/null)
        _w=$(jq -r '.warn // 0' "$_summary" 2>/dev/null)
        _log "feedback summary: ${_p} pass, ${_f} fail, ${_w} warn"
        _ALL_PASS=$((_ALL_PASS + _p))
        _ALL_FAIL=$((_ALL_FAIL + _f))
        _ALL_WARN=$((_ALL_WARN + _w))
    else
        _warn "no feedback summary yet"
    fi
}

main() {
    _log "=== ZEN LOOP E2E TEST STARTED ==="
    _log "burn-in duration: ${BURNIN_HOURS}h (max $(date -u -d "@$((_BURNIN_START + BURNIN_HOURS * 3600))" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "unknown"))"

    while true; do
        _CYCLE=$((_CYCLE + 1))
        _now=$(date -u +%s)
        _elapsed=$((_now - _BURNIN_START))
        _elapsed_h=$((_elapsed / 3600))
        _elapsed_m=$(((_elapsed % 3600) / 60))

        _log "=== CYCLE ${_CYCLE} (${_elapsed_h}h ${_elapsed_m}m elapsed) ==="

        _check_generator
        _check_verifier
        _check_queue
        _check_generated_output
        _check_verified_output
        _check_feedback

        # Write cycle summary
        cat > "$SUMMARY_FILE" << EOF
{
  "burnin_start": $_BURNIN_START,
  "elapsed_seconds": $_elapsed,
  "cycle": $_CYCLE,
  "total_pass": $_ALL_PASS,
  "total_fail": $_ALL_FAIL,
  "total_warn": $_ALL_WARN,
  "last_check": "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u)"
}
EOF

        if [ "$ONCE" -eq 1 ]; then
            _log "=== ONE-SHOT COMPLETE ==="
            printf '\nSummary: %d pass, %d fail, %d warn (cycle %d)\n' "$_ALL_PASS" "$_ALL_FAIL" "$_ALL_WARN" "$_CYCLE"
            exit $((_ALL_FAIL > 0 ? 1 : 0))
        fi

        # Check burn-in duration
        _max_secs=$((BURNIN_HOURS * 3600))
        if [ "$_elapsed" -ge "$_max_secs" ]; then
            _log "=== BURN-IN COMPLETE (${BURNIN_HOURS}h) ==="
            printf '\n=== BURN-IN COMPLETE ===\n'
            printf 'Duration: %dh %dm\n' "$_elapsed_h" "$_elapsed_m"
            printf 'Cycles:   %d\n' "$_CYCLE"
            printf 'Pass:     %d\n' "$_ALL_PASS"
            printf 'Fail:     %d\n' "$_ALL_FAIL"
            printf 'Warn:     %d\n' "$_ALL_WARN"
            exit $((_ALL_FAIL > 0 ? 1 : 0))
        fi

        sleep 60
    done
}

main "$@"
