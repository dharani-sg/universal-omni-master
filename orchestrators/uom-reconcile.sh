#!/bin/sh
# scripts/uom-reconcile.sh — 6-step cloud-only UOM reconciler
# Pure opencode CLI cloud pipeline. No local LLM. No Ollama. No sudo.
# All tunnel traffic forced to 127.0.0.1 — no gateway loop risk.
# Fully idempotent. Safe to re-run.
#
# Usage: sh scripts/uom-reconcile.sh [--skip-zen]

set -u

UOM_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STATE_FILE="${UOM_DIR}/.uom-agent/state.json"
LOG_DIR="${UOM_DIR}/.uom-agent/logs"
LOG_FILE="${LOG_DIR}/reconcile.log"
SESSION_NAME="uom"
CLOUD_MODEL="${CLOUD_MODEL:-opencode/deepseek-v4-flash-free}"

SKIP_ZEN=0
for _arg in "$@"; do
  case "$_arg" in --skip-zen) SKIP_ZEN=1 ;; --help|-h)
    printf 'Usage: sh %s [--skip-zen]\n' "$0"; exit 0 ;; esac
done

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"
CYAN="\033[0;36m"; BOLD="\033[1m"; NC="\033[0m"

mkdir -p "$LOG_DIR" "${UOM_DIR}/.uom-agent/runtime" \
  "${UOM_DIR}/.uom-agent/generated" "${UOM_DIR}/.uom-agent/verified"

_log() {
  _ts=$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date)
  printf '[reconcile] %s %s\n' "$_ts" "$*" | tee -a "$LOG_FILE"
}
_step() { printf '\n%s═══ STEP %s: %s ═══%s\n' "$CYAN" "$1" "$2" "$NC"; _log "STEP $1: $2"; }
_pass() { printf '  %s✓%s %s\n' "$GREEN" "$NC" "$1"; }
_warn() { printf '  %s!%s %s\n' "$YELLOW" "$NC" "$1"; }
_fail() { printf '  %s✗%s %s\n' "$RED" "$NC" "$1"; }

IS_TERMUX=0
[ -d "/data/data/com.termux" ] || [ -n "${ANDROID_ROOT:-}" ] && IS_TERMUX=1

# ═══════════════════════════════════════════════════════════════════════
# STEP 0: Pre-flight Safety Checks
# ═══════════════════════════════════════════════════════════════════════
_step "0" "PRE-FLIGHT SAFETY CHECKS"

# sshd alive?
_SSHD_PID=$(pgrep -x sshd 2>/dev/null | head -1 || true)
if [ -n "$_SSHD_PID" ]; then
  _pass "sshd (PID ${_SSHD_PID}) — will NOT be touched"
else
  _warn "sshd not detected — check connectivity before proceeding"
fi

# Project directory valid
if [ ! -f "${UOM_DIR}/install/bootstrap-termux.sh" ]; then
  _fail "${UOM_DIR}/install/bootstrap-termux.sh missing"; exit 1
fi
_pass "Project root: ${UOM_DIR}"

# jq
command -v jq >/dev/null 2>&1 && _pass "jq: $(jq --version 2>/dev/null)" || {
  _fail "jq required — install: pkg/apk/apt install jq"; exit 1; }

# opencode CLI
command -v opencode >/dev/null 2>&1 && _pass "opencode: $(opencode --version 2>/dev/null | head -1)" || {
  _warn "opencode CLI not found — bootstrap Step 2 will install it"; }

# Routing — force 127.0.0.1 tunnel, never touch gateway
_my_ip=$(ip -4 addr show 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1 || echo "unknown")
_gw=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}' || echo "unknown")
if [ "$_my_ip" = "$_gw" ] && [ "$_my_ip" != "unknown" ]; then
  _warn "IP (${_my_ip}) equals gateway — tunnel will use 127.0.0.1 only"
else
  _pass "Routing: my=${_my_ip} gw=${_gw} — 127.0.0.1 tunnel safe"
fi

# Internet reachability to opencode cloud (graceful retry)
_api_ok=0
for _try in 1 2 3; do
  _status=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
    "https://api.opencode.ai/health" 2>/dev/null || echo "000")
  if [ "$_status" = "200" ] || [ "$_status" = "204" ]; then
    _pass "OpenCode cloud reachable (HTTP ${_status})"
    _api_ok=1; break
  fi
  _warn "API health check attempt ${_try}/3 — HTTP ${_status} in 10s"
  sleep 10
done
[ "$_api_ok" -eq 0 ] && _warn "OpenCode cloud unreachable — agents will use stub fallback"

# Existing tmux sessions (info only)
tmux list-sessions 2>/dev/null | while IFS= read -r _s; do _log "  $_s"; done

# ═══════════════════════════════════════════════════════════════════════
# STEP 1: Tmux Isolation & Window Guard
# ═══════════════════════════════════════════════════════════════════════
_step "1" "TMUX ISOLATION & WINDOW GUARD"

command -v tmux >/dev/null 2>&1 || { _fail "tmux not installed"; exit 1; }

# Check for existing 'uom' session — never create duplicate
if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
  _pass "Session '${SESSION_NAME}' exists — adding windows"
else
  _log "Creating new tmux session '${SESSION_NAME}'..."
  tmux new-session -d -s "${SESSION_NAME}" -n "orchestrator" \
    -x "$(tput cols 2>/dev/null || echo 120)" \
    -y "$(tput lines 2>/dev/null || echo 40)"
  _pass "Session '${SESSION_NAME}' created"
fi

# Create windows idempotently — skip if they already exist
for _win in orchestrator generator verifier status; do
  if tmux list-windows -t "${SESSION_NAME}" 2>/dev/null | grep -q "^${_win}"; then
    _pass "Window '${_win}' exists"
  else
    case "$_win" in
      orchestrator)
        tmux new-window -t "${SESSION_NAME}" -n "${_win}" \
          "cd '${UOM_DIR}' && sh bin/omni-project-start.sh --menu" ;;
      generator|verifier)
        tmux new-window -t "${SESSION_NAME}" -n "${_win}" "sh" ;;
      status)
        tmux new-window -t "${SESSION_NAME}" -n "${_win}" \
          "watch -n10 'cd ${UOM_DIR} && sh bin/uom-status.sh 2>/dev/null'" ;;
    esac
    _pass "Window '${_win}' created"
  fi
done

# ═══════════════════════════════════════════════════════════════════════
# STEP 2: UOM Bootstrap Application
# ═══════════════════════════════════════════════════════════════════════
_step "2" "UOM BOOTSTRAP APPLICATION"

_log "Running: sh install/bootstrap-termux.sh --apply..."
cd "$UOM_DIR"
_bootstrap_out=$(sh install/bootstrap-termux.sh --apply 2>&1)
_bootstrap_rc=$?
printf '%s\n' "$_bootstrap_out" >> "$LOG_FILE"
[ "$_bootstrap_rc" -eq 0 ] && _pass "Bootstrap finished (RC=0)" \
  || _warn "Bootstrap RC=${_bootstrap_rc} — review ${LOG_FILE}"

# Verify opencode
if command -v opencode >/dev/null 2>&1; then
  _pass "opencode: $(opencode --version 2>/dev/null | head -1)"
else
  _warn "opencode still missing after bootstrap — generator will stub"
fi

# Verify SSH config
[ -f "${HOME}/.ssh/config" ] && _pass "SSH config present" \
  || _warn "No ~/.ssh/config — tunnel may fail"
[ -f "${HOME}/.ssh/id_ed25519" ] && _pass "SSH key present" \
  || _warn "No SSH key — bootstrap may not have generated one"

# ═══════════════════════════════════════════════════════════════════════
# STEP 3: Reverse Tunnel Isolation (127.0.0.1 only)
# ═══════════════════════════════════════════════════════════════════════
_step "3" "REVERSE TUNNEL ISOLATION"

_tunnel_up=false
pgrep -f 'autossh.*-R.*31415' >/dev/null 2>&1 && { _tunnel_up=true; }
pgrep -f 'ssh.*-R.*31415' >/dev/null 2>&1 && { _tunnel_up=true; }

if [ "$_tunnel_up" = false ]; then
  ssh -o ConnectTimeout=3 -o BatchMode=yes -p 31415 127.0.0.1 true 2>/dev/null \
    && _tunnel_up=true
fi

if [ "$_tunnel_up" = true ]; then
  _pass "Reverse tunnel already active (127.0.0.1:31415)"
else
  if [ "$IS_TERMUX" -eq 1 ]; then
    _log "Phone-side: launching uom-reverse-ssh.sh bound to 127.0.0.1..."
    export UOM_LAPTOP_HOST="${UOM_LAPTOP_HOST:-127.0.0.1}"
    nohup sh "${UOM_DIR}/bin/uom-reverse-ssh.sh" start \
      >> "${LOG_DIR}/tunnel-start.log" 2>&1 &
    _tunnel_pid=$!
    _log "Tunnel PID: ${_tunnel_pid}"

    _waited=0
    while [ "$_waited" -lt 20 ]; do
      sleep 2; _waited=$((_waited + 2))
      ssh -o ConnectTimeout=2 -o BatchMode=yes -p 31415 127.0.0.1 true 2>/dev/null \
        && { _pass "Tunnel established after ${_waited}s"; break; }
    done
    [ "$_waited" -ge 20 ] && _warn "Tunnel not reachable yet — check UOM_LAPTOP_HOST"
  else
    _warn "Laptop-side: tunnel is phone-initiated — waiting for phone to connect"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════
# STEP 4: Port Guardian Initialization
# ═══════════════════════════════════════════════════════════════════════
_step "4" "PORT GUARDIAN INITIALIZATION"

if [ ! -f "${UOM_DIR}/bin/uom-port-guardian.sh" ]; then
  _warn "uom-port-guardian.sh not found — skipping"; exit 0
fi

_pg_out=$(sh "${UOM_DIR}/bin/uom-port-guardian.sh" status 2>/dev/null || echo "")
if echo "$_pg_out" | grep -q RUNNING; then
  _pass "Port guardian already running — no action"
else
  _log "Starting port guardian..."
  sh "${UOM_DIR}/bin/uom-port-guardian.sh" start >/dev/null 2>&1 || true
  sleep 2
  _pg_out2=$(sh "${UOM_DIR}/bin/uom-port-guardian.sh" status 2>/dev/null || echo "")
  echo "$_pg_out2" | grep -q RUNNING && _pass "Port guardian started" \
    || _warn "Port guardian start may have failed"
fi

# ═══════════════════════════════════════════════════════════════════════
# STEP 5: Dual-Agent Zen Hybrid Loop (Generator + Verifier)
# ═══════════════════════════════════════════════════════════════════════
_step "5" "DUAL-AGENT ZEN HYBRID LOOP"

if [ "$SKIP_ZEN" -eq 1 ]; then
  _pass "Zen loop skipped (--skip-zen)"
else
  # Kill stale agent processes
  for _f in gen ver; do
    _pid_file="${UOM_DIR}/.uom-agent/runtime/${_f}.pid"
    _lock_file="${UOM_DIR}/.uom-agent/runtime/${_f}.lock"
    _old=$(cat "$_pid_file" 2>/dev/null || echo "")
    [ -n "$_old" ] && kill "$_old" 2>/dev/null || true
    rm -f "$_lock_file" "$_pid_file" 2>/dev/null || true
  done

  # Build launch command — platform-adaptive
  _launch_cmd() {
    _script="$1"
    printf "cd '%s' && sh scripts/%s" "$UOM_DIR" "$_script"
  }

  _gen_cmd=$(_launch_cmd "uom-generator.sh")
  _ver_cmd=$(_launch_cmd "uom-verifier.sh")

  # Launch generator into tmux window
  if tmux list-windows -t "${SESSION_NAME}" 2>/dev/null | grep -q 'generator'; then
    tmux send-keys -t "${SESSION_NAME}:generator" "$_gen_cmd" C-m
    _pass "Generator agent launched in tmux window"
  else
    nohup sh -c "$_gen_cmd" >> "${LOG_DIR}/generator.log" 2>&1 &
    _pass "Generator background PID $!"
  fi

  # Launch verifier into tmux window
  if tmux list-windows -t "${SESSION_NAME}" 2>/dev/null | grep -q 'verifier'; then
    tmux send-keys -t "${SESSION_NAME}:verifier" "$_ver_cmd" C-m
    _pass "Verifier agent launched in tmux window"
  else
    nohup sh -c "$_ver_cmd" >> "${LOG_DIR}/verifier.log" 2>&1 &
    _pass "Verifier background PID $!"
  fi

  sleep 2

  # Verify agents started
  for _role in gen ver; do
    _pid_file="${UOM_DIR}/.uom-agent/runtime/${_role}.pid"
    _pid=$(cat "$_pid_file" 2>/dev/null || echo "")
    if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
      _pass "${_role}: running (PID ${_pid})"
    else
      _warn "${_role}: not running — check logs"
    fi
  done

  # Queue snapshot
  if [ -f "${UOM_DIR}/.uom-agent/queue.json" ]; then
    for _s in pending in_progress verified failed; do
      _c=$(jq -r "[.[] | select(.status==\"${_s}\")] | length" \
        "${UOM_DIR}/.uom-agent/queue.json" 2>/dev/null || echo 0)
      [ "$_c" -gt 0 ] && _pass "Queue ${_s}: ${_c}"
    done
  fi
fi

# ═══════════════════════════════════════════════════════════════════════
# STEP 6: Final Verification
# ═══════════════════════════════════════════════════════════════════════
_step "6" "FINAL VERIFICATION"

# State file
if [ -f "$STATE_FILE" ] && jq -e '.' "$STATE_FILE" >/dev/null 2>&1; then
  _agent=$(jq -r '.active_agent // "unknown"' "$STATE_FILE")
  _mode=$(jq -r '.hybrid_mode // "dual"' "$STATE_FILE")
  _pass "state.json: agent=${_agent} mode=${_mode}"
else
  _fail "state.json missing or invalid"
fi

# Tmux
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  _wc=$(tmux list-windows -t "$SESSION_NAME" 2>/dev/null | wc -l)
  _pass "Tmux '${SESSION_NAME}': ${_wc} windows"
  tmux list-windows -t "$SESSION_NAME" 2>/dev/null | while IFS= read -r _w; do
    _log "  $_w"
  done
else
  _fail "Tmux session missing"
fi

# Processes
for _proc in uom-orch-laptop uom-orch-phone uom-solo-orchestrator; do
  pgrep -f "$_proc" >/dev/null 2>&1 && _pass "${_proc}: running"
done

# Tunnel
if pgrep -f 'autossh.*-R.*31415' >/dev/null 2>&1 || pgrep -f 'ssh.*-R.*31415' >/dev/null 2>&1; then
  _pass "Tunnel: UP"
elif ssh -o ConnectTimeout=3 -o BatchMode=yes -p 31415 127.0.0.1 true 2>/dev/null; then
  _pass "Tunnel: UP (127.0.0.1:31415)"
else
  _warn "Tunnel: DOWN"
fi

# Zen output
if [ "$SKIP_ZEN" -eq 0 ]; then
  _rdy=$(find "${UOM_DIR}/.uom-agent/generated" -name '*.ready' 2>/dev/null | wc -l)
  _dne=$(find "${UOM_DIR}/.uom-agent/generated" -name '*.done' 2>/dev/null | wc -l)
  _vrf=$(find "${UOM_DIR}/.uom-agent/verified" -name '*.result' 2>/dev/null | wc -l)
  _pass "Zen: ${_rdy} awaiting, ${_dne} processed, ${_vrf} verified"
fi

# ── Summary ──────────────────────────────────────────────────────────
printf '\n%s═══ RECONCILE COMPLETE ═══%s\n' "$GREEN" "$NC"
printf '\n'
printf '%sQuick commands:%s\n' "$BOLD" "$NC"
printf '  tmux attach -t %-16s # Attach to session\n' "${SESSION_NAME}"
printf '  sh bin/uom-status.sh            # Check all services\n'
printf '  cat %-43s # Reconcile log\n' "${LOG_FILE}"
printf '  cat %-43s # Generator log\n' "${LOG_DIR}/generator.log"
printf '  cat %-43s # Verifier log\n' "${LOG_DIR}/verifier.log"
printf '\n'
printf '%sSession layout:%s\n' "$BOLD" "$NC"
printf '  Window: orchestrator  → Project start menu\n'
printf '  Window: generator     → Cloud LLM agent (opencode %s)\n' "$CLOUD_MODEL"
printf '  Window: verifier      → Syntax/policy checker\n'
printf '  Window: status        → Live status watcher\n'
printf '\n'
printf '%sZen loop pipeline:%s\n' "$BOLD" "$NC"
printf '  queue.json (pending) → generator → generated/*.ready\n'
printf '                                        ↓\n'
printf '                                  verifier → verified/*.result → queue (verified/failed)\n'
printf '\n'
