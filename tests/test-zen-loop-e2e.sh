#!/bin/sh
# tests/test-zen-loop-e2e.sh — PHASE17 burn-in acceptance supervisor
# Authoritative supervisor runs on phone/Termux in tmux uom-burnin:supervisor.
# Laptop-side monitoring is auxiliary.
#
# Usage:
#   sh tests/test-zen-loop-e2e.sh                # 8-hour burn-in
#   sh tests/test-zen-loop-e2e.sh --hours 1      # 1-hour run
#   sh tests/test-zen-loop-e2e.sh --once         # one cycle then exit
#   sh tests/test-zen-loop-e2e.sh --dryrun       # validate config

set -u

UOM_DIR="${UOM_DIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
ONCE=0
DRYRUN=0
BURNIN_HOURS="${UOM_BURNIN_HOURS:-8}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --once)
      ONCE=1; shift ;;
    --hours)
      [ "$#" -ge 2 ] || { echo "--hours requires a value" >&2; exit 2; }
      BURNIN_HOURS="$2"; shift 2 ;;
    --dryrun)
      DRYRUN=1; shift ;;
    *)
      echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

# Validate BURNIN_HOURS as positive integer
case "$BURNIN_HOURS" in
  ''|*[!0-9]*) echo "BURNIN_HOURS must be a positive integer" >&2; exit 2 ;;
esac
[ "$BURNIN_HOURS" -gt 0 ] || { echo "BURNIN_HOURS must be > 0" >&2; exit 2; }

# Source state lib
if [ -f "${UOM_DIR}/tools/uom-state-lib.sh" ]; then
  . "${UOM_DIR}/tools/uom-state-lib.sh"
  uom_state_init 2>/dev/null || true
fi

# ── Paths ─────────────────────────────────────────────────────────────────
LOG_DIR="${UOM_LOG_DIR:-${UOM_DIR}/.uom-agent/logs}"
RUNTIME_DIR="${UOM_RUNTIME_DIR:-${UOM_DIR}/.uom-agent/runtime}"
STATE_DIR="${UOM_STATE_DIR:-${UOM_DIR}/.uom-agent}"
QUEUE_FILE="${UOM_QUEUE_FILE:-${STATE_DIR}/queue.json}"
STATE_FILE="${UOM_STATE_FILE:-${STATE_DIR}/state.json}"
LOCK_DIR="${RUNTIME_DIR}/burnin-supervisor.lock"
LOG_FILE="${LOG_DIR}/burnin-supervisor.log"
E2E_LOG="${LOG_DIR}/burnin-e2e.log"
ATTEMPT_BASE="${LOG_DIR}/burnin-$(date -u +%Y%m%d)-$(date -u +%H%M%S)"

mkdir -p "$LOG_DIR" "$RUNTIME_DIR" "$ATTEMPT_BASE"

# Platform detection
_IS_PHONE=0
[ "$(uname -o 2>/dev/null)" = "Android" ] && _IS_PHONE=1

# ── Counters (cycle-scoped, NOT cumulative garbage) ───────────────────────
CYCLE=0
TOTAL_CYCLES=0
HEALTH_PASS=0
HEALTH_FAIL=0
HEALTH_WARN=0
VERDICT_PASS=0
VERDICT_RETRY=0
VERDICT_BLOCKED=0
VERDICT_UNSAFE=0

_BURNIN_START=0
_BURNIN_END=0

# ── Logging ───────────────────────────────────────────────────────────────
_log() {
  _ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u)"
  printf '[supervisor] %s %s\n' "$_ts" "$*" | tee -a "$LOG_FILE"
}

_e2e_log() {
  _ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u)"
  printf '[burnin-e2e] %s %s\n' "$_ts" "$*" >> "$E2E_LOG"
  printf '[burnin-e2e] %s %s\n' "$_ts" "$*"
}

# ── Singleton lock ────────────────────────────────────────────────────────
_acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "$$" > "$LOCK_DIR/pid"
    echo "$(date -u +%s)" > "$LOCK_DIR/started"
    return 0
  fi
  _old_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
  if [ -n "$_old_pid" ] && kill -0 "$_old_pid" 2>/dev/null; then
    _log "supervisor already running (PID $_old_pid)"
    exit 0
  fi
  rm -rf "$LOCK_DIR" 2>/dev/null || true
  mkdir "$LOCK_DIR" 2>/dev/null || { _log "cannot acquire lock"; exit 1; }
  echo "$$" > "$LOCK_DIR/pid"
  echo "$(date -u +%s)" > "$LOCK_DIR/started"
}

_release_lock() {
  _lp=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
  [ "$_lp" = "$$" ] && rm -rf "$LOCK_DIR" 2>/dev/null || true
}

# ── Cleanup trap ──────────────────────────────────────────────────────────
_CLEAN_EXIT=0
_cleanup() {
  [ "$_CLEAN_EXIT" -eq 1 ] && return
  _CLEAN_EXIT=1
  _BURNIN_END=$(date -u +%s)
  _log "supervisor stopping — writing interrupted summary"
  _cleanup_agents
  _write_report "INTERRUPTED"
  _release_lock
  _log "supervisor stopped"
  exit 0
}

_cleanup_agents() {
  # Graceful stop of task agents only
  for _patt in "uom-generator.sh" "uom-phone-gen-loop" "uom-verifier.sh" "uom-sync-loop" "uom-feedback-aggregator"; do
    _pids=$(pgrep -f "$_patt" 2>/dev/null || true)
    for _pid in $_pids; do
      kill -TERM "$_pid" 2>/dev/null || true
    done
  done
  # Release lease if we own it
  if command -v uom_state_update_filter >/dev/null 2>&1; then
    uom_state_update_filter '.task_status = "idle" | .current_task_id = ""' 2>/dev/null || true
  fi
}

trap '_cleanup' INT TERM HUP

# ═══════════════════════════════════════════════════════════════════════════
# HEALTH CHECKS
# ═══════════════════════════════════════════════════════════════════════════

_pass() { _e2e_log "  PASS: $*"; HEALTH_PASS=$((HEALTH_PASS + 1)); }
_fail() { _e2e_log "  FAIL: $*"; HEALTH_FAIL=$((HEALTH_FAIL + 1)); }
_warn() { _e2e_log "  WARN: $*"; HEALTH_WARN=$((HEALTH_WARN + 1)); }

_check_wrapper() {
  # Single-instance helper: check if a process matching pattern is running
  # Usage: _check_wrapper "description" "pid_file" "process_pattern"
  _desc="$1"
  _pidf="$2"
  _pat="$3"
  _pid=""
  [ -f "$_pidf" ] && _pid=$(cat "$_pidf" 2>/dev/null)
  if [ -n "$_pid" ] && [ -d "/proc/$_pid" ]; then
    _cmdline=$(cat "/proc/$_pid/cmdline" 2>/dev/null | tr '\0' ' ')
    case "$_cmdline" in
      *"$_pat"*) _pass "$_desc (PID $_pid)"; return 0 ;;
    esac
  fi
  # Fallback: pgrep
  _alt=$(pgrep -f "$_pat" 2>/dev/null | head -1)
  if [ -n "$_alt" ]; then
    _pass "$_desc (PID $_alt, no pidfile)"
    return 0
  fi
  _fail "$_desc not found (pattern: $_pat)"
  return 1
}

_check_qemu() {
  _qemu=$(pgrep -f "qemu-system-aarch64" 2>/dev/null | head -1)
  if [ -n "$_qemu" ]; then
    _pass "QEMU running (PID $_qemu)"
    return 0
  fi
  _fail "QEMU not running"
  return 1
}

_check_guest_ssh() {
  if ssh -o ConnectTimeout=5 -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -p 2222 uom@127.0.0.1 'echo OK' 2>/dev/null | grep -q OK; then
    _pass "guest SSH reachable"
    return 0
  fi
  _warn "guest SSH unreachable"
  return 1
}

_check_generator() {
  _cnt=0
  # Check phone Termux
  if [ "$_IS_PHONE" -eq 1 ]; then
    _pid=$(pgrep -f "uom-generator.sh" 2>/dev/null | head -1)
    [ -n "$_pid" ] && _cnt=$((_cnt + 1)) && _pass "generator (Termux, PID $_pid)"
  fi
  # Check guest via phone
  _gpid=$(ssh -o ConnectTimeout=5 -o BatchMode=yes \
    -p 2222 uom@127.0.0.1 'pgrep -f "uom-generator.sh" 2>/dev/null | head -1' \
    2>/dev/null || echo "")
  [ -n "$_gpid" ] && _cnt=$((_cnt + 1)) && _warn "generator on guest (PID $_gpid) — should run on Termux host"

  if [ "$_cnt" -eq 0 ]; then
    _warn "no generator detected"
    return 1
  fi
  if [ "$_cnt" -gt 1 ]; then
    _fail "multiple generators detected ($_cnt)"
    return 1
  fi
  return 0
}

_check_verifier() {
  # Verifier should run on laptop
  if [ "$_IS_PHONE" -eq 1 ]; then
    # Phone can't directly check laptop process — check via heartbeat
    _last_hb=$(uom_state_get laptop_heartbeat 2>/dev/null || echo "")
    if [ -n "$_last_hb" ]; then
      _pass "laptop heartbeat: $_last_hb"
      return 0
    fi
    _warn "cannot verify laptop verifier from phone"
    return 1
  fi
  _check_wrapper "verifier" "${RUNTIME_DIR}/ver.pid" "uom-verifier.sh"
}

_check_queue_invariants() {
  [ -f "$QUEUE_FILE" ] || { _fail "queue.json missing"; return 1; }
  jq empty "$QUEUE_FILE" 2>/dev/null || { _fail "queue.json invalid JSON"; return 1; }
  _pending=$(jq -r '[.[] | select(.status == "pending")] | length' "$QUEUE_FILE" 2>/dev/null || echo 0)
  _in_prog=$(jq -r '[.[] | select(.status == "in_progress")] | length' "$QUEUE_FILE" 2>/dev/null || echo 0)
  _verified=$(jq -r '[.[] | select(.status == "verified")] | length' "$QUEUE_FILE" 2>/dev/null || echo 0)
  _failed=$(jq -r '[.[] | select(.status == "failed")] | length' "$QUEUE_FILE" 2>/dev/null || echo 0)

  [ "$_in_prog" -le 1 ] || _warn "multiple in_progress tasks ($_in_prog)"
  _e2e_log "queue: ${_pending} pending, ${_in_prog} in_progress, ${_verified} verified, ${_failed} failed"
}

_check_state_invariants() {
  [ -f "$STATE_FILE" ] || { _fail "state.json missing"; return 1; }
  jq empty "$STATE_FILE" 2>/dev/null || { _fail "state.json invalid JSON"; return 1; }
  _sv=$(jq -r '.schema_version // 0' "$STATE_FILE" 2>/dev/null || echo 0)
  [ "$_sv" -ge 2 ] || _warn "schema_version < 2 ($_sv)"
  _aa=$(jq -r '.active_agent // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
  _wr=$(jq -r '.writer_role // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
  _eo=$(jq -r '.ownership_epoch // 0' "$STATE_FILE" 2>/dev/null || echo 0)
  _e2e_log "state: active=$_aa writer=$_wr epoch=$_eo"
}

_check_disk_memory() {
  if [ -f /proc/meminfo ]; then
    _mem_avail=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null || echo 999999)
    _mem_mb=$((_mem_avail / 1024))
    [ "$_mem_mb" -lt 100 ] && _warn "low memory: ${_mem_mb}MB"
  fi
  if command -v df >/dev/null 2>&1; then
    _disk_pct=$(df "$UOM_DIR" 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%' || echo 0)
    [ "$_disk_pct" -gt 90 ] 2>/dev/null && _warn "disk >90% (${_disk_pct}%)"
  fi
}

_check_git_clean() {
  _dirty=$(cd "$UOM_DIR" && git status --short 2>/dev/null | grep -v '^?' | wc -l)
  [ "$_dirty" -gt 0 ] && _warn "${_dirty} dirty tracked files"
}

# ═══════════════════════════════════════════════════════════════════════════
# REPORTING
# ═══════════════════════════════════════════════════════════════════════════

_write_report() {
  _final_status="${1:-RUNNING}"
  _elapsed=0
  if [ "$_BURNIN_START" -gt 0 ]; then
    _now=$(date -u +%s)
    _elapsed=$((_now - _BURNIN_START))
  fi

  _branch="$(cd "$UOM_DIR" && git branch --show-current 2>/dev/null || echo unknown)"
  _head="$(cd "$UOM_DIR" && git rev-parse HEAD 2>/dev/null || echo unknown)"

  cat > "${ATTEMPT_BASE}/summary.json" << EOF
{
  "status": "${_final_status}",
  "burnin_start_epoch": $_BURNIN_START,
  "burnin_end_epoch": $_BURNIN_END,
  "elapsed_seconds": $_elapsed,
  "branch": "${_branch}",
  "head": "${_head}",
  "cycles": $CYCLE,
  "health_checks": {
    "pass": $HEALTH_PASS,
    "fail": $HEALTH_FAIL,
    "warn": $HEALTH_WARN
  },
  "verdicts": {
    "pass": $VERDICT_PASS,
    "retry": $VERDICT_RETRY,
    "blocked": $VERDICT_BLOCKED,
    "unsafe": $VERDICT_UNSAFE
  },
  "final_state": "$(jq -c . "$STATE_FILE" 2>/dev/null || echo '{}')"
}
EOF

  # Copy logs
  cp "$LOG_FILE" "${ATTEMPT_BASE}/supervisor.log" 2>/dev/null || true
  cp "$E2E_LOG" "${ATTEMPT_BASE}/e2e.log" 2>/dev/null || true
  cp "$STATE_FILE" "${ATTEMPT_BASE}/state.json" 2>/dev/null || true
  cp "$QUEUE_FILE" "${ATTEMPT_BASE}/queue.json" 2>/dev/null || true

  _log "report written to ${ATTEMPT_BASE}/summary.json"
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN SUPERVISOR LOOP
# ═══════════════════════════════════════════════════════════════════════════

main() {
  _acquire_lock
  _BURNIN_START=$(date -u +%s)
  _BURNIN_END=0

  _e2e_log "=== ZEN LOOP E2E TEST STARTED ==="
  _e2e_log "burn-in duration: ${BURNIN_HOURS}h max"
  _e2e_log "branch: $(cd "$UOM_DIR" && git branch --show-current 2>/dev/null || echo unknown)"

  if [ "$DRYRUN" -eq 1 ]; then
    _e2e_log "dryrun mode — one cycle with no process checks"
    _check_queue_invariants
    _check_state_invariants
    _write_report "DRYRUN"
    _release_lock
    return 0
  fi

  while true; do
    CYCLE=$((CYCLE + 1))
    TOTAL_CYCLES=$CYCLE
    _now=$(date -u +%s)
    _elapsed=$((_now - _BURNIN_START))
    _elapsed_h=$((_elapsed / 3600))
    _elapsed_m=$(((_elapsed % 3600) / 60))

    # Reset cycle counters
    HEALTH_PASS=0
    HEALTH_FAIL=0
    HEALTH_WARN=0

    _e2e_log "=== CYCLE ${CYCLE} (${_elapsed_h}h ${_elapsed_m}m) ==="

    # Health checks
    _check_qemu || true
    _check_guest_ssh || true
    _check_generator || true
    _check_verifier || true
    _check_queue_invariants || true
    _check_state_invariants || true
    _check_disk_memory || true
    _check_git_clean || true

    # Read feedback summary for verdicts
    _sf="${STATE_DIR}/feedback/summary.json"
    if [ -f "$_sf" ]; then
      _p=$(jq -r '.pass // 0' "$_sf" 2>/dev/null || echo 0)
      _r=$(jq -r '.retry_with_feedback // 0' "$_sf" 2>/dev/null || echo 0)
      _b=$(jq -r '.blocked // 0' "$_sf" 2>/dev/null || echo 0)
      _u=$(jq -r '.unsafe // 0' "$_sf" 2>/dev/null || echo 0)
      VERDICT_PASS=$_p
      VERDICT_RETRY=$_r
      VERDICT_BLOCKED=$_b
      VERDICT_UNSAFE=$_u
      _e2e_log "verdicts: ${_p} pass, ${_r} retry, ${_b} blocked, ${_u} unsafe"
    else
      _e2e_log "no feedback summary yet"
    fi

    # Every 15 min: write checkpoint
    if [ $((CYCLE % 15)) -eq 0 ]; then
      _write_report "RUNNING"
    fi

    # Block on UNSAFE
    if [ "$VERDICT_UNSAFE" -gt 0 ]; then
      _e2e_log "BLOCKING: UNSAFE verdict detected"
      _write_report "BLOCKED_UNSAFE"
      break
    fi

    if [ "$ONCE" -eq 1 ]; then
      _e2e_log "=== ONE-SHOT COMPLETE (${CYCLE} cycle(s)) ==="
      _write_report "ONE_SHOT"
      break
    fi

    # Check burn-in duration
    _max_secs=$((BURNIN_HOURS * 3600))
    if [ "$_elapsed" -ge "$_max_secs" ]; then
      _e2e_log "=== BURN-IN COMPLETE (${BURNIN_HOURS}h) ==="
      _cleanup_agents
      _write_report "COMPLETE"
      break
    fi

    sleep 60
  done

  _BURNIN_END=$(date -u +%s)
  _release_lock
  _log "supervisor exited (status=$_final_status)"
}

main "$@"
