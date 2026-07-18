#!/bin/sh
# orchestrators/uom-reconcile.sh — v0.32.0 cloud-only UOM reconciler
# Dynamic model selection + dynamic port/IP handling + network drift resilience.
# Pure opencode CLI cloud pipeline. No local LLM. No Ollama. No sudo.
# All tunnel traffic forced to 127.0.0.1 — no gateway loop risk.
# Fully idempotent. Safe to re-run.
#
# Usage: sh orchestrators/uom-reconcile.sh [--status] [--force] [--dryrun]
#        [--reselect-model] [--reset-network] [--skip-zen]

set -u

# ═══════════════════════════════════════════════════════════════════════════
# SECTION F: ARGUMENT PARSING
# ═══════════════════════════════════════════════════════════════════════════

ARG_STATUS=0
ARG_FORCE=0
ARG_DRYRUN=0
ARG_RESELECT=0
ARG_RESET_NET=0
ARG_SKIP_ZEN=0

for _arg in "$@"; do
  case "$_arg" in
    --status)          ARG_STATUS=1 ;;
    --force)           ARG_FORCE=1 ;;
    --dryrun)          ARG_DRYRUN=1 ;;
    --reselect-model)  ARG_RESELECT=1 ;;
    --reset-network)   ARG_RESET_NET=1 ;;
    --skip-zen)        ARG_SKIP_ZEN=1 ;;
    --help|-h)
      printf 'Usage: sh %s [--status] [--force] [--dryrun] [--reselect-model]\n' "$0"
      printf '       [--reset-network] [--skip-zen]\n'
      exit 0 ;;
    *)
      printf 'Unknown option: %s\n' "$_arg" >&2; exit 1 ;;
  esac
done

# ═══════════════════════════════════════════════════════════════════════════
# SECTION F: CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════

UOM_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STATE_FILE="${UOM_DIR}/.uom-agent/state.json"
LOG_DIR="${UOM_DIR}/.uom-agent/logs"
LOG_FILE="${LOG_DIR}/reconcile.log"
RUNTIME_DIR="${UOM_DIR}/.uom-agent/runtime"
SESSION_NAME="uom-hybrid"

MODEL_POOL="opencode/deepseek-v4-flash-free opencode/nemotron-3-ultra-free opencode/north-mini-code-free opencode/big-pickle"
MODEL_CACHE_TTL=300
TUNNEL_PORT_START=31400
TUNNEL_PORT_END=31499
PHONE_HOST_MAX_AGE=120
LAPTOP_HOST_MAX_AGE=120
NET_FP_FILE="${RUNTIME_DIR}/net_fingerprint"
MODEL_FILE="${RUNTIME_DIR}/selected_model"
TUNNEL_PORT_FILE="${RUNTIME_DIR}/tunnel_port"
NET_STATE_FILE="${RUNTIME_DIR}/net_state.json"
PHONE_HOST_HINT="${UOM_DIR}/.uom-agent/phone.host"
LAPTOP_HOST_HINT="${UOM_DIR}/.uom-agent/laptop.host"
DEGRADED_DIR="${UOM_DIR}/.uom-agent/degraded"
UOM_TMP="${TMPDIR:-${HOME}/tmp}"

mkdir -p "$LOG_DIR" "$RUNTIME_DIR" "$DEGRADED_DIR" "$UOM_TMP"

# ═══════════════════════════════════════════════════════════════════════════
# SECTION F: HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"
CYAN="\033[0;36m"; BOLD="\033[1m"; NC="\033[0m"

_log() {
  _ts=$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date)
  printf '[reconcile] %s %s\n' "$_ts" "$*" >> "$LOG_FILE"
  printf '[reconcile] %s %s\n' "$_ts" "$*"
}

_step() {
  printf '\n%s═══ STEP %s: %s ═══%s\n' "$CYAN" "$1" "$2" "$NC"
  _log "STEP $1: $2"
}

_pass() { printf '  %s✓%s %s\n' "$GREEN" "$NC" "$1"; }
_warn() { printf '  %s!%s %s\n' "$YELLOW" "$NC" "$1"; }
_fail() { printf '  %s✗%s %s\n' "$RED" "$NC" "$1"; }

cleanup() {
  rm -f "${UOM_TMP}/model_probe_$$.txt" 2>/dev/null || true
}

check_binary() {
  command -v "$1" >/dev/null 2>&1
}

check_lock() {
  _lock_dir="${UOM_DIR}/.uom-agent/locks/reconcile.lock"
  mkdir -p "${UOM_DIR}/.uom-agent/locks" 2>/dev/null || true
  if ! mkdir "$_lock_dir" 2>/dev/null; then
    if [ -f "$_lock_dir/pid" ]; then
      _old=$(cat "$_lock_dir/pid" 2>/dev/null || echo "")
      if [ -n "$_old" ] && kill -0 "$_old" 2>/dev/null; then
        printf 'reconcile already running (PID %s)\n' "$_old" >&2
        exit 1
      fi
      _log "Stale lock from PID $_old — cleaning"
    fi
    rm -rf "$_lock_dir" 2>/dev/null || true
    mkdir "$_lock_dir" 2>/dev/null || { printf 'Cannot acquire lock\n' >&2; exit 1; }
  fi
  echo $$ > "$_lock_dir/pid"
  trap 'rm -rf "${UOM_DIR}/.uom-agent/locks/reconcile.lock" 2>/dev/null; cleanup' EXIT INT TERM
}

# ═══════════════════════════════════════════════════════════════════════════
# SECTION E: HELPER FUNCTIONS (v0.32.0)
# ═══════════════════════════════════════════════════════════════════════════

test_model() {
  _model_name="$1"
  printf 'echo POSIX sh function name\n' \
    | timeout 10 opencode --model "$_model_name" 2>&1 \
    | head -20
}

allocate_tunnel_port() {
  _port=$TUNNEL_PORT_START
  while [ "$_port" -le "$TUNNEL_PORT_END" ]; do
    if ! nc -z 127.0.0.1 "$_port" 2>/dev/null; then
      printf '%s\n' "$_port"
      return 0
    fi
    _port=$((_port + 1))
  done
  return 1
}

compute_net_fingerprint() {
  _gw=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
  _lip=$(ip addr show 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' \
    | awk '{print $2}' | cut -d/ -f1 | head -1)
  _paddr="UNKNOWN:8022"
  if [ -f "$PHONE_HOST_HINT" ]; then
    _paddr=$(cat "$PHONE_HOST_HINT" 2>/dev/null | tr -d '[:space:]')
  fi
  printf '%s:%s:%s\n' "${_gw:-NONE}" "${_lip:-UNKNOWN}" "${_paddr}" \
    | sha256sum | awk '{print $1}'
}

check_hint_freshness() {
  _hf="$1"
  _max="$2"
  if [ ! -f "$_hf" ]; then
    return 1
  fi
  _hint_ts=$(stat -c %Y "$_hf" 2>/dev/null || echo 0)
  _now_ts=$(date +%s)
  _age=$((_now_ts - _hint_ts))
  [ "$_age" -lt "$_max" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# SECTION F: EXECUTION BLOCKS
# ═══════════════════════════════════════════════════════════════════════════

IS_TERMUX=0
[ -d "/data/data/com.termux" ] || [ -n "${ANDROID_ROOT:-}" ] && IS_TERMUX=1

# ═══════════════════════════════════════════════════════════════════════════
# STEP 0: PRE-FLIGHT SAFETY CHECKS (ENHANCED)
# ═══════════════════════════════════════════════════════════════════════════
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
check_binary jq && _pass "jq: $(jq --version 2>/dev/null)" || {
  _fail "jq required — install: pkg/apk/apt install jq"; exit 1; }

# opencode CLI
check_binary opencode && _pass "opencode: $(opencode --version 2>/dev/null | head -1)" || {
  _warn "opencode CLI not found — Step 2 will handle model selection"; }

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

# 0.10 Network discovery sanity check
if [ -f "${UOM_DIR}/bin/uom-port-guardian.sh" ] || [ -f "${UOM_DIR}/orchestrators/uom-port-guardian.sh" ]; then
  _pass "Port guardian installed"
else
  _warn "Port guardian not found — tunnel hints may be stale"
fi

if [ -r "$PHONE_HOST_HINT" ]; then
  _pass "Phone host hint readable: $(cat "$PHONE_HOST_HINT" 2>/dev/null | tr -d '[:space:]')"
else
  _warn "Phone host hint not readable — will use fallback"
fi

if [ -z "$_gw" ] || [ "$_gw" = "unknown" ]; then
  _warn "No default gateway — check network"
fi

# 0.11 Model pool verification
_pass "Model pool: $(echo "$MODEL_POOL" | wc -w) candidates defined"

# Existing tmux sessions (info only)
tmux list-sessions 2>/dev/null | while IFS= read -r _s; do _log "  $_s"; done

if [ "$ARG_DRYRUN" -eq 1 ]; then
  _pass "Dry run — stopping at Step 0"
  exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════
# SINGLETON LOCK ACQUISITION
# ═══════════════════════════════════════════════════════════════════════════
check_lock

# ═══════════════════════════════════════════════════════════════════════════
# STEP 1: TMUX ISOLATION & WINDOW GUARD
# ═══════════════════════════════════════════════════════════════════════════
_step "1" "TMUX ISOLATION & WINDOW GUARD"

check_binary tmux || { _fail "tmux not installed"; exit 1; }

if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
  _pass "Session '${SESSION_NAME}' exists — adding windows"
else
  _log "Creating new tmux session '${SESSION_NAME}'..."
  tmux new-session -d -s "${SESSION_NAME}" -n "orchestrator" \
    -x "$(tput cols 2>/dev/null || echo 120)" \
    -y "$(tput lines 2>/dev/null || echo 40)"
  _pass "Session '${SESSION_NAME}' created"
fi

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

# ═══════════════════════════════════════════════════════════════════════════
# STEP 2: CLOUD ENVIRONMENT BOOTSTRAP WITH DYNAMIC MODEL SELECTION
# ═══════════════════════════════════════════════════════════════════════════
_step "2" "CLOUD BOOTSTRAP — DYNAMIC MODEL SELECTION"

SELECTED_MODEL=""
DEGRADED_MODE=0

# 2.1 Platform detection
IS_TERMUX=0
[ -d "/data/data/com.termux" ] || [ -n "${ANDROID_ROOT:-}" ] && IS_TERMUX=1
if [ "$IS_TERMUX" -eq 1 ]; then
  _pass "Platform: Termux (Android)"
else
  _pass "Platform: Linux (Alpine/Generic)"
fi

# 2.2 Model pool definition (already in constants block)
_pass "Model pool: $(echo "$MODEL_POOL" | wc -w) candidates"

# 2.3 Cached model check
_skip_probe=0
if [ "$ARG_RESELECT" -eq 0 ] && [ -f "$MODEL_FILE" ]; then
  _cached_model=$(cat "$MODEL_FILE" 2>/dev/null | tr -d '[:space:]')
  _model_ts=$(stat -c %Y "$MODEL_FILE" 2>/dev/null || echo 0)
  _now_ts=$(date +%s)
  _model_age=$((_now_ts - _model_ts))
  if [ "$_model_age" -lt "$MODEL_CACHE_TTL" ] 2>/dev/null && [ -n "$_cached_model" ]; then
    SELECTED_MODEL="$_cached_model"
    _skip_probe=1
    _pass "Cached model valid (${_model_age}s < ${MODEL_CACHE_TTL}s): $_cached_model"
  else
    _log "Cached model stale (${_model_age}s) — re-probing"
  fi
fi

# 2.4 Model health check (runtime selection)
if [ "$_skip_probe" -eq 0 ]; then
  _log "Probing model pool..."
  for _candidate in $MODEL_POOL; do
    _log "  Testing: $_candidate"
    _probe_start=$(date +%s%N 2>/dev/null || date +%s)
    _probe_out=$(test_model "$_candidate" 2>&1 || true)
    _probe_end=$(date +%s%N 2>/dev/null || date +%s)
    _probe_ms=0
    if [ "$_probe_start" -gt 0 ] 2>/dev/null && [ "$_probe_end" -gt 0 ] 2>/dev/null; then
      _probe_ms=$(( (_probe_end - _probe_start) / 1000000 )) 2>/dev/null || _probe_ms=0
    fi

    _probe_exit=$?

    # Check result
    _probe_pass=0
    case "$_probe_out" in
      *error*429*|*rate*limit*)  _log "    SKIP: rate limited"; continue ;;
      *error*5[0-9][0-9]*)      _log "    SKIP: server error"; continue ;;
      *error*auth*|*API*key*)   _log "    SKIP: auth required"; continue ;;
      *timeout*|*timed*out*)    _log "    SKIP: timeout"; continue ;;
    esac
    case "$_probe_out" in
      *sh*|*posix*|*function*|*POSIX*) _probe_pass=1 ;;
    esac
    # Also accept if non-empty and no error exit
    if [ "$_probe_pass" -eq 0 ] && [ -n "$_probe_out" ] && [ $_probe_exit -eq 0 ]; then
      case "$_probe_out" in
        *error*|*Error*|*ERROR*) : ;;
        *) _probe_pass=1 ;;
      esac
    fi

    if [ "$_probe_pass" -eq 1 ]; then
      SELECTED_MODEL="$_candidate"
      printf '%s\n' "$_candidate" > "${MODEL_FILE}.tmp"
      mv "${MODEL_FILE}.tmp" "$MODEL_FILE"
      _pass "Selected model: $_candidate (probe: ${_probe_ms}ms)"
      break
    else
      _log "    FAIL: $_candidate (exit=$_probe_exit)"
    fi
  done
fi

# 2.5 Model selection fallback
if [ -z "$SELECTED_MODEL" ]; then
  SELECTED_MODEL="STUB"
  DEGRADED_MODE=1
  printf '%s\n' "STUB" > "$MODEL_FILE"
  _warn "DEGRADED MODE: No cloud models available — using stub generator"
fi

# 2.6 Model selection export
export UOM_SELECTED_MODEL="$SELECTED_MODEL"
export UOM_DEGRADED_MODE="$DEGRADED_MODE"

if [ "$DEGRADED_MODE" -eq 1 ]; then
  _log "2.6: WARN Cloud bootstrap complete — DEGRADED MODE active"
else
  _log "2.6: INFO Cloud bootstrap complete — model: $SELECTED_MODEL"
fi

# 2.7 DNS resolution check
if check_binary nslookup; then
  _dns_out=$(nslookup api.opencode.ai 2>/dev/null | head -3 || true)
  case "$_dns_out" in
    *Address*|*address*) _pass "DNS: api.opencode.ai resolves" ;;
    *) _warn "DNS: api.opencode.ai may not resolve — check /etc/resolv.conf" ;;
  esac
elif check_binary host; then
  host api.opencode.ai >/dev/null 2>&1 && _pass "DNS: resolves" \
    || _warn "DNS: api.opencode.ai may not resolve"
else
  _pass "DNS: no resolver tool — skipping check"
fi

# 2.8 Secrets isolation verification
if [ -f "${UOM_DIR}/install/secrets.env.template" ]; then
  _pass "Secrets template present"
  if [ -f "${HOME}/.config/uom/secrets.env" ] || [ -f "${UOM_DIR}/.uom-agent/secrets.env" ]; then
    _pass "Secrets file found"
  else
    _warn "No secrets.env — some features may be limited"
  fi
else
  _pass "No secrets template — optional"
fi

# 2.9 State file initialization
if [ ! -f "$NET_STATE_FILE" ]; then
  printf '{"tunnel_port":31415,"phone_ip":"unknown","laptop_ip":"unknown"}\n' \
    > "$NET_STATE_FILE"
  _pass "Initialized net_state.json"
else
  _pass "net_state.json exists"
fi

# ═══════════════════════════════════════════════════════════════════════════
# STEP 3: NETWORK TOPOLOGY DISCOVERY & TUNNEL ORCHESTRATION (DYNAMIC)
# ═══════════════════════════════════════════════════════════════════════════
_step "3" "NETWORK TOPOLOGY & TUNNEL ORCHESTRATION"

NETWORK_CHANGED=0

# 3.1 Network fingerprint computation
_gw_ip=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
[ -z "$_gw_ip" ] && _gw_ip="NONE"

_laptop_ip=$(ip addr show 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' \
  | awk '{print $2}' | cut -d/ -f1 | head -1)
[ -z "$_laptop_ip" ] && _laptop_ip="UNKNOWN"

_phone_addr="UNKNOWN:8022"
if [ -f "$PHONE_HOST_HINT" ]; then
  _phone_addr=$(cat "$PHONE_HOST_HINT" 2>/dev/null | tr -d '[:space:]')
fi

_current_fp=$(printf '%s:%s:%s\n' "$_gw_ip" "$_laptop_ip" "$_phone_addr" \
  | sha256sum | awk '{print $1}')

_stored_fp="NONE"
if [ -f "$NET_FP_FILE" ]; then
  _stored_fp=$(cat "$NET_FP_FILE" 2>/dev/null | tr -d '[:space:]')
fi

_pass "Gateway: $_gw_ip  Laptop: $_laptop_ip  Phone: $_phone_addr"

# 3.2 Network change detection
if [ "$_current_fp" != "$_stored_fp" ] || [ "$ARG_RESET_NET" -eq 1 ]; then
  _log "Network topology changed — re-initializing tunnel"
  NETWORK_CHANGED=1
  printf '%s\n' "$_current_fp" > "${NET_FP_FILE}.tmp"
  mv "${NET_FP_FILE}.tmp" "$NET_FP_FILE"

  if check_binary jq; then
    jq --arg gw "$_gw_ip" --arg lip "$_laptop_ip" --arg paddr "$_phone_addr" \
      '.gateway=$gw | .laptop_ip=$lip | .phone_addr=$paddr' \
      "$NET_STATE_FILE" > "${NET_STATE_FILE}.tmp" 2>/dev/null \
      && mv "${NET_STATE_FILE}.tmp" "$NET_STATE_FILE"
  fi
else
  _log "Network topology unchanged — fingerprint: $(printf '%s' "$_current_fp" | head -c 16)..."
  NETWORK_CHANGED=0
fi

# 3.3 Tunnel port allocation (dynamic)
TUNNEL_PORT=""
if [ -f "$TUNNEL_PORT_FILE" ] && [ "$NETWORK_CHANGED" -eq 0 ] && [ "$ARG_FORCE" -eq 0 ]; then
  _cached_port=$(cat "$TUNNEL_PORT_FILE" 2>/dev/null | tr -d '[:space:]')
  if [ -n "$_cached_port" ] && ! nc -z 127.0.0.1 "$_cached_port" 2>/dev/null; then
    TUNNEL_PORT="$_cached_port"
    _pass "Using cached tunnel port: $TUNNEL_PORT"
  else
    _log "Cached port $_cached_port occupied or invalid — reallocating"
  fi
fi

if [ -z "$TUNNEL_PORT" ]; then
  TUNNEL_PORT=$(allocate_tunnel_port)
  if [ $? -ne 0 ] || [ -z "$TUNNEL_PORT" ]; then
    _fail "No free tunnel ports in range ${TUNNEL_PORT_START}-${TUNNEL_PORT_END}"
    exit 1
  fi
  printf '%s\n' "$TUNNEL_PORT" > "${TUNNEL_PORT_FILE}.tmp"
  mv "${TUNNEL_PORT_FILE}.tmp" "$TUNNEL_PORT_FILE"
  _pass "Allocated tunnel port: $TUNNEL_PORT"
fi

export UOM_TUNNEL_PORT="$TUNNEL_PORT"

if check_binary jq; then
  jq --arg tp "$TUNNEL_PORT" '.tunnel_port=($tp|tonumber)' \
    "$NET_STATE_FILE" > "${NET_STATE_FILE}.tmp" 2>/dev/null \
    && mv "${NET_STATE_FILE}.tmp" "$NET_STATE_FILE"
fi

# 3.4 Tunnel liveness check (dynamic port)
TUNNEL_ALIVE=0

# Process check
if pgrep -f "autossh.*${TUNNEL_PORT}" >/dev/null 2>&1; then
  TUNNEL_ALIVE=1
fi
if pgrep -f "ssh.*-R.*${TUNNEL_PORT}" >/dev/null 2>&1; then
  TUNNEL_ALIVE=1
fi

# Port check
if [ "$TUNNEL_ALIVE" -eq 0 ]; then
  ssh -o ConnectTimeout=3 -o BatchMode=yes -p "$TUNNEL_PORT" 127.0.0.1 true 2>/dev/null \
    && TUNNEL_ALIVE=1
fi

if [ "$TUNNEL_ALIVE" -eq 1 ]; then
  _pass "Tunnel 127.0.0.1:${TUNNEL_PORT} ALIVE"
else
  _warn "Tunnel 127.0.0.1:${TUNNEL_PORT} DOWN"
fi

# 3.5 Tunnel restart logic (on network change or down)
if [ "$NETWORK_CHANGED" -eq 1 ] || [ "$TUNNEL_ALIVE" -eq 0 ]; then
  # Kill existing tunnel processes (all autossh/ssh on this port)
  pkill -f "autossh.*31[4-5][0-9][0-9]" 2>/dev/null || true
  sleep 2

  # Verify phone.host freshness
  if [ -f "$PHONE_HOST_HINT" ]; then
    _phone_ts=$(stat -c %Y "$PHONE_HOST_HINT" 2>/dev/null || echo 0)
    _now_ts=$(date +%s)
    _phone_age=$((_now_ts - _phone_ts))
    if [ "$_phone_age" -gt "$PHONE_HOST_MAX_AGE" ]; then
      _log "phone.host stale (${_phone_age}s) — triggering guardian refresh"
      touch "${RUNTIME_DIR}/portguard.refresh_request" 2>/dev/null || true
    fi
  else
    _log "phone.host missing — proceeding without tunnel restart"
  fi

  # Parse phone.host
  _phone_addr=$(cat "$PHONE_HOST_HINT" 2>/dev/null || echo "192.168.40.207:8022")
  _phone_ip=$(printf '%s\n' "$_phone_addr" | cut -d: -f1)
  _phone_port=$(printf '%s\n' "$_phone_addr" | cut -d: -f2)
  [ -z "$_phone_port" ] && _phone_port=8022

  if [ "$IS_TERMUX" -eq 1 ]; then
    _log "Phone-side: launching tunnel with port $TUNNEL_PORT..."
    export UOM_TUNNEL_PORT="$TUNNEL_PORT"
    export UOM_PHONE_SSH_PORT="$_phone_port"
    nohup sh "${UOM_DIR}/bin/uom-reverse-ssh.sh" start \
      >> "${LOG_DIR}/tunnel-start.log" 2>&1 &
    _tunnel_pid=$!
    _log "Tunnel PID: $_tunnel_pid"

    _waited=0
    while [ "$_waited" -lt 20 ]; do
      sleep 2; _waited=$((_waited + 2))
      ssh -o ConnectTimeout=2 -o BatchMode=yes -p "$TUNNEL_PORT" 127.0.0.1 true 2>/dev/null \
        && { _pass "Tunnel established after ${_waited}s"; break; }
    done
    [ "$_waited" -ge 20 ] && _warn "Tunnel not yet reachable — check phone connection"
  else
    _log "Laptop-side: tunnel is phone-initiated — waiting for phone to connect"
  fi

  # Re-check liveness
  if [ "$TUNNEL_ALIVE" -eq 0 ]; then
    ssh -o ConnectTimeout=3 -o BatchMode=yes -p "$TUNNEL_PORT" 127.0.0.1 true 2>/dev/null \
      && { TUNNEL_ALIVE=1; _pass "Tunnel re-established"; }
  fi
fi

# 3.6 Tunnel binding enforcement
if [ -f "${UOM_DIR}/bin/uom-reverse-ssh.sh" ]; then
  if grep -q '127\.0\.0\.1' "${UOM_DIR}/bin/uom-reverse-ssh.sh" 2>/dev/null; then
    _pass "Tunnel script uses 127.0.0.1 binding"
  else
    _warn "Tunnel script may not use 127.0.0.1 binding — verify manually"
  fi
  if grep -q 'UOM_TUNNEL_PORT' "${UOM_DIR}/bin/uom-reverse-ssh.sh" 2>/dev/null; then
    _pass "Tunnel script reads UOM_TUNNEL_PORT env"
  else
    _warn "Tunnel script does not reference UOM_TUNNEL_PORT — may use hardcoded port"
  fi
fi

# 3.7 Signal port-guardian (network change)
if [ "$NETWORK_CHANGED" -eq 1 ]; then
  touch "${RUNTIME_DIR}/portguard.network_changed" 2>/dev/null || true
  _pass "Signaled port-guardian of topology change"
fi

# ═══════════════════════════════════════════════════════════════════════════
# STEP 4: PORT GUARDIAN INITIALIZATION (ENHANCED)
# ═══════════════════════════════════════════════════════════════════════════
_step "4" "PORT GUARDIAN INITIALIZATION"

PG_SCRIPT=""
if [ -f "${UOM_DIR}/bin/uom-port-guardian.sh" ]; then
  PG_SCRIPT="${UOM_DIR}/bin/uom-port-guardian.sh"
elif [ -f "${UOM_DIR}/orchestrators/uom-port-guardian.sh" ]; then
  PG_SCRIPT="${UOM_DIR}/orchestrators/uom-port-guardian.sh"
fi

if [ -z "$PG_SCRIPT" ]; then
  _warn "Port guardian not found — skipping"
else
  # 4.1 Guardian liveness check
  _pg_out=$(sh "$PG_SCRIPT" status 2>/dev/null || echo "")
  if echo "$_pg_out" | grep -q RUNNING; then
    _pass "Port guardian already running"
  else
    _log "Starting port guardian..."

    # 4.3 Dynamic network-aware startup
    if grep -q 'net_fingerprint\|network.*change' "$PG_SCRIPT" 2>/dev/null; then
      _pass "Guardian supports dynamic network"
    else
      _warn "Guardian may not support dynamic network drift detection"
    fi

    export UOM_GATEWAY_IP="$_gw_ip"
    export UOM_LAPTOP_IP="$_laptop_ip"
    export UOM_PHONE_ADDR="$_phone_addr"
    export UOM_TUNNEL_PORT="$TUNNEL_PORT"

    sh "$PG_SCRIPT" start >/dev/null 2>&1 || true
    sleep 3

    _pg_out2=$(sh "$PG_SCRIPT" status 2>/dev/null || echo "")
    echo "$_pg_out2" | grep -q RUNNING && _pass "Port guardian started" \
      || _warn "Port guardian start may have failed"
  fi

  # 4.4 Guardian startup verification
  sleep 5
  _guardian_ok=1
  for _hint in "$PHONE_HOST_HINT" "$LAPTOP_HOST_HINT"; do
    if [ ! -f "$_hint" ]; then
      _warn "Guardian did not publish $(basename "$_hint")"
      _guardian_ok=0
    fi
  done
  [ "$_guardian_ok" -eq 1 ] && _pass "Guardian host hints present"

  # 4.5 Host hint validation
  for _hint_file in "$PHONE_HOST_HINT" "$LAPTOP_HOST_HINT"; do
    if [ -f "$_hint_file" ]; then
      _hint_ts=$(stat -c %Y "$_hint_file" 2>/dev/null || echo 0)
      _now_ts=$(date +%s)
      _hint_age=$((_now_ts - _hint_ts))
      if [ "$_hint_age" -gt 60 ]; then
        _warn "$(basename "$_hint_file") stale (${_hint_age}s)"
      fi
    fi
  done
fi

# ═══════════════════════════════════════════════════════════════════════════
# STEP 5: DUAL-AGENT ZEN LOOP WITH DYNAMIC MODEL
# ═══════════════════════════════════════════════════════════════════════════
_step "5" "DUAL-AGENT ZEN LOOP (DYNAMIC MODEL)"

if [ "$ARG_SKIP_ZEN" -eq 1 ]; then
  _pass "Zen loop skipped (--skip-zen)"
else
  # Kill stale agent processes
  for _f in gen ver; do
    _pid_file="${RUNTIME_DIR}/${_f}.pid"
    _lock_file="${RUNTIME_DIR}/${_f}.lock"
    _old=$(cat "$_pid_file" 2>/dev/null || echo "")
    [ -n "$_old" ] && kill "$_old" 2>/dev/null || true
    rm -f "$_lock_file" "$_pid_file" 2>/dev/null || true
  done

  # 5.4 Generator agent behavior (dynamic model)
  _gen_cmd="cd '${UOM_DIR}' && sh scripts/uom-generator.sh"
  if [ "$DEGRADED_MODE" -eq 1 ]; then
    _log "Degraded mode: generator will use stub code (no cloud model)"
  else
    _log "Generator model: $UOM_SELECTED_MODEL"
  fi

  # Launch generator
  if tmux list-windows -t "${SESSION_NAME}" 2>/dev/null | grep -q 'generator'; then
    tmux send-keys -t "${SESSION_NAME}:generator" "$_gen_cmd" C-m
    _pass "Generator agent launched in tmux window"
  else
    nohup sh -c "$_gen_cmd" >> "${LOG_DIR}/generator.log" 2>&1 &
    _pass "Generator background PID $!"
  fi

  # 5.5 Verifier agent behavior (dynamic model aware)
  _ver_cmd="cd '${UOM_DIR}' && sh scripts/uom-verifier.sh"

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
    _pid_file="${RUNTIME_DIR}/${_role}.pid"
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

# ═══════════════════════════════════════════════════════════════════════════
# STEP 6: SUPERVISOR WITH NETWORK AND MODEL MONITORING
# ═══════════════════════════════════════════════════════════════════════════
_step "6" "SUPERVISOR & FINAL VERIFICATION"

# 6.1 Status report (enhanced with dynamic state)
_model_age=0
if [ -f "$MODEL_FILE" ]; then
  _model_ts=$(stat -c %Y "$MODEL_FILE" 2>/dev/null || echo 0)
  _now_ts=$(date +%s)
  _model_age=$((_now_ts - _model_ts))
fi

_tunnel_alloc_age=0
if [ -f "$TUNNEL_PORT_FILE" ]; then
  _tp_ts=$(stat -c %Y "$TUNNEL_PORT_FILE" 2>/dev/null || echo 0)
  _now_ts=$(date +%s)
  _tunnel_alloc_age=$((_now_ts - _tp_ts))
fi

_phone_hint_age=0
if [ -f "$PHONE_HOST_HINT" ]; then
  _ph_ts=$(stat -c %Y "$PHONE_HOST_HINT" 2>/dev/null || echo 0)
  _now_ts=$(date +%s)
  _phone_hint_age=$((_now_ts - _ph_ts))
fi

_pass "Selected model:     $UOM_SELECTED_MODEL (age: ${_model_age}s)"
_pass "Network fingerprint: $(printf '%s' "$_current_fp" | head -c 16)..."
_pass "Tunnel port:        $TUNNEL_PORT (age: ${_tunnel_alloc_age}s)"
_pass "Phone address:      $_phone_addr (hint age: ${_phone_hint_age}s)"
_pass "Laptop address:     $_laptop_ip"
_pass "Degraded mode:      $([ "$DEGRADED_MODE" -eq 1 ] && echo yes || echo no)"

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
if [ "$TUNNEL_ALIVE" -eq 1 ]; then
  _pass "Tunnel: UP (127.0.0.1:${TUNNEL_PORT})"
else
  _warn "Tunnel: DOWN"
fi

# Zen output
if [ "$ARG_SKIP_ZEN" -eq 0 ]; then
  _rdy=$(find "${UOM_DIR}/.uom-agent/generated" -name '*.ready' 2>/dev/null | wc -l)
  _dne=$(find "${UOM_DIR}/.uom-agent/generated" -name '*.done' 2>/dev/null | wc -l)
  _vrf=$(find "${UOM_DIR}/.uom-agent/verified" -name '*.result' 2>/dev/null | wc -l)
  _pass "Zen: ${_rdy} awaiting, ${_dne} processed, ${_vrf} verified"
fi

# 6.3 Structured log summary
if check_binary jq; then
  jq -n \
    --arg model "$UOM_SELECTED_MODEL" \
    --argjson model_age "$_model_age" \
    --argjson degraded "$DEGRADED_MODE" \
    --argjson tunnel_port "$TUNNEL_PORT" \
    --arg net_fp "$(printf '%s' "$_current_fp" | head -c 16)" \
    --arg phone "$_phone_addr" \
    --arg laptop "$_laptop_ip" \
    '{
      selected_model: $model,
      model_age_seconds: $model_age,
      degraded_mode: ($degraded == 1),
      tunnel_port: $tunnel_port,
      network_fingerprint: $net_fp,
      phone_addr: $phone,
      laptop_ip: $laptop
    }' > "${RUNTIME_DIR}/last-reconcile.json" 2>/dev/null \
    && _pass "Structured log: last-reconcile.json"
fi

# ── Summary ──────────────────────────────────────────────────────────
printf '\n%s═══ RECONCILE COMPLETE (v0.32.0) ═══%s\n' "$GREEN" "$NC"
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
printf '  Window: generator     → Cloud LLM agent (%s)\n' "$UOM_SELECTED_MODEL"
printf '  Window: verifier      → Syntax/policy checker\n'
printf '  Window: status        → Live status watcher\n'
printf '\n'
printf '%sDynamic state:%s\n' "$BOLD" "$NC"
printf '  Model:        %s (cache: %ds)\n' "$UOM_SELECTED_MODEL" "$MODEL_CACHE_TTL"
printf '  Tunnel port:  %s (range: %d-%d)\n' "$TUNNEL_PORT" "$TUNNEL_PORT_START" "$TUNNEL_PORT_END"
printf '  Network FP:   %s\n' "$(printf '%s' "$_current_fp" | head -c 16)"
printf '  Degraded:     %s\n' "$([ "$DEGRADED_MODE" -eq 1 ] && echo YES || echo no)"
printf '\n'
printf '%sZen loop pipeline:%s\n' "$BOLD" "$NC"
printf '  queue.json (pending) → generator → generated/*.ready\n'
printf '                                        ↓\n'
printf '                                  verifier → verified/*.result → queue (verified/failed)\n'
printf '\n'
