#!/bin/sh
# orchestrators/uom-trident-supervisor.sh — Meta-supervisor for triple orchestrator
# Monitors SUPER, COORD, GUARD, ANTI-SL processes.
# Heuristically revives dead ones (never kills live ones).
# Wires model-rotate, api_wrapper concepts, port-guardian, ip-discover, feedback-aggregator.
# POSIX sh. No bashisms.
#
# Usage:
#   sh orchestrators/uom-trident-supervisor.sh            # foreground (for tmux)
#   sh orchestrators/uom-trident-supervisor.sh --daemon   # fork to background
#
# Environment:
#   UOM_STATE_DIR    — state directory (default: .uom-agent)
#   UOM Trident cycle interval in seconds (default: 60)

set -u

# ══════════════════════════════════════════════════════════════════════════
# PATHS
# ══════════════════════════════════════════════════════════════════════════
_SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
_UOM_DIR="$(cd "$_SELF_DIR/.." 2>/dev/null && pwd)"
UOM_DIR="${UOM_DIR:-$_UOM_DIR}"
UOM_STATE_DIR="${UOM_STATE_DIR:-${UOM_DIR}/.uom-agent}"
UOM_RUNTIME_DIR="${UOM_RUNTIME_DIR:-${UOM_STATE_DIR}/runtime}"
UOM_LOG_DIR="${UOM_LOG_DIR:-${UOM_STATE_DIR}/logs}"
UOM_JOURNAL="${UOM_STATE_DIR}/journal.jsonl"
IDENTITY_FILE="${UOM_STATE_DIR}/coordinator-identity.json"
REGISTRY_FILE="${UOM_STATE_DIR}/endpoint-registry.json"
HEARTBEAT_DIR="${UOM_RUNTIME_DIR}/heartbeat"
LOCK_DIR="${UOM_RUNTIME_DIR}/trident.lock"
PID_FILE="${UOM_RUNTIME_DIR}/trident.pid"
STATUS_FILE="${UOM_RUNTIME_DIR}/trident-status.json"

# Cycle interval
TRIDENT_CYCLE="${TRIDENT_CYCLE:-60}"

# Sub-intervals (in cycles)
MODEL_CHECK_INTERVAL=10    # every 10 min
PHONE_CHECK_INTERVAL=5     # every 5 min
NET_CHECK_INTERVAL=3       # every 3 min
FEEDBACK_INTERVAL=2        # every 2 min
PORT_CHECK_INTERVAL=1      # every cycle

mkdir -p "$UOM_RUNTIME_DIR" "$UOM_LOG_DIR" "$HEARTBEAT_DIR"

# ══════════════════════════════════════════════════════════════════════════
# LOGGING
# ══════════════════════════════════════════════════════════════════════════
_tlog() {
    _ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)"
    printf '[trident] %s %s\n' "$_ts" "$*" >&2
    printf '[trident] %s %s\n' "$_ts" "$*" >> "${UOM_LOG_DIR}/trident.log" 2>/dev/null || true
}

_journal() {
    _ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)"
    printf '{"ts":"%s","src":"trident","evt":"%s","data":%s}\n' \
        "$_ts" "$1" "$2" >> "$UOM_JOURNAL" 2>/dev/null || true
}

# ══════════════════════════════════════════════════════════════════════════
# LOCK / SINGLETON
# ══════════════════════════════════════════════════════════════════════════
_acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo "$$" > "$LOCK_DIR/pid"
        return 0
    fi
    _old_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
    if [ -n "$_old_pid" ] && kill -0 "$_old_pid" 2>/dev/null; then
        _tlog "already running (PID $_old_pid)"
        exit 0
    fi
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    mkdir "$LOCK_DIR" 2>/dev/null || { _tlog "cannot acquire lock"; exit 1; }
    echo "$$" > "$LOCK_DIR/pid"
}

_release_lock() {
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    rm -f "$PID_FILE" 2>/dev/null || true
}

# ══════════════════════════════════════════════════════════════════════════
# SIGNAL HANDLING
# ══════════════════════════════════════════════════════════════════════════
_SHUTDOWN=0
_cleanup() {
    _tlog "graceful shutdown (PID=$$)"
    _journal "TRIDENT_STOPPED" '{"pid":'$$'}'
    _release_lock
}
_trap_exit() { _SHUTDOWN=1; _cleanup; exit 0; }
trap '_trap_exit' INT TERM
trap '_cleanup' EXIT

# ══════════════════════════════════════════════════════════════════════════
# PROCESS TABLE — the 4 guardians
# ══════════════════════════════════════════════════════════════════════════
# Each entry: NAME|PID_FILE_OR_CMD|REVIVE_CMD|CAN_DIE_ON_POWER_CUT
# CAN_DIE_ON_POWER_CUT: 1=yes (laptop), 0=no (phones)

_init_process_table() {
    # Auto-discover latest overnight state directory
    _OVERNIGHT_BASE="${HOME}/.local/state/uom-overnight"
    _OVERNIGHT_DIR=""
    if [ -d "$_OVERNIGHT_BASE" ]; then
        _OVERNIGHT_DIR=$(ls -1td "$_OVERNIGHT_BASE"/overnight-triple-* 2>/dev/null | head -1)
    fi

    # SUPER — the existing supervisor.sh
    P_SUPER_NAME="SUPER"
    if [ -n "$_OVERNIGHT_DIR" ] && [ -f "${_OVERNIGHT_DIR}/supervisor/supervisor.pid" ]; then
        P_SUPER_IDENTITY="${_OVERNIGHT_DIR}/supervisor/supervisor.pid"
    else
        P_SUPER_IDENTITY="${UOM_STATE_DIR}/supervisor/supervisor.pid"
    fi
    P_SUPER_CAN_DIE=1  # laptop process, acceptable on power cut

    # COORD — the coordinator/opencode orchestrator
    P_COORD_NAME="COORD"
    if [ -n "$_OVERNIGHT_DIR" ] && [ -f "${_OVERNIGHT_DIR}/supervisor/coordinator-identity.json" ]; then
        P_COORD_IDENTITY="${_OVERNIGHT_DIR}/supervisor/coordinator-identity.json"
    else
        P_COORD_IDENTITY="$IDENTITY_FILE"
    fi
    P_COORD_CAN_DIE=0  # must survive power cut (phones keep running)

    # GUARD — port guardian
    P_GUARD_NAME="GUARD"
    P_GUARD_IDENTITY="${UOM_STATE_DIR}/port-guardian.pid"
    P_GUARD_CAN_DIE=1

    # ANTI-SL — anti-sleep (phone keepalive)
    P_ANTISL_NAME="ANTI-SL"
    P_ANTISL_IDENTITY="${UOM_STATE_DIR}/anti-sleep.pid"
    P_ANTISL_CAN_DIE=0
}

# ══════════════════════════════════════════════════════════════════════════
# PROCESS LIVENESS CHECK
# ══════════════════════════════════════════════════════════════════════════
# Reads PID from identity file or pid file, checks if alive.

_read_pid() {
    _file="$1"
    [ -f "$_file" ] || { echo ""; return 1; }
    # Try JSON first (coordinator-identity.json has "pid": N)
    _pid=$(grep -o '"pid"[[:space:]]*:[[:space:]]*[0-9]*' "$_file" 2>/dev/null \
        | head -1 | grep -o '[0-9]*$')
    if [ -n "$_pid" ] && [ "$_pid" -gt 0 ] 2>/dev/null; then
        echo "$_pid"; return 0
    fi
    # Try plain PID file
    _pid=$(cat "$_file" 2>/dev/null | tr -d '[:space:]')
    case "$_pid" in
        ''|*[!0-9]*) echo ""; return 1 ;;
    esac
    echo "$_pid"; return 0
}

_is_alive() {
    _pid="$1"
    [ -n "$_pid" ] && [ "$_pid" -gt 0 ] 2>/dev/null && kill -0 "$_pid" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════════════════
# REVIVE FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════

_revive_super() {
    _tlog "REVIVE SUPER: restarting supervisor.sh in tmux"
    _journal "REVIVE_SUPER" '{"reason":"process_dead"}'
    # Find the supervisor script — prefer overnight dir, fallback to state dir
    _sup=""
    if [ -n "$_OVERNIGHT_DIR" ] && [ -f "${_OVERNIGHT_DIR}/supervisor/supervisor.sh" ]; then
        _sup="${_OVERNIGHT_DIR}/supervisor/supervisor.sh"
    elif [ -f "${UOM_STATE_DIR}/supervisor/supervisor.sh" ]; then
        _sup="${UOM_STATE_DIR}/supervisor/supervisor.sh"
    fi
    if [ -n "$_sup" ]; then
        tmux new-session -d -s uom-sup "bash $_sup" 2>/dev/null || \
            nohup bash "$_sup" >> "${UOM_LOG_DIR}/supervisor-revive.log" 2>&1 &
        _tlog "SUPER revive launched: $_sup"
    else
        _tlog "SUPER revive FAILED: no supervisor.sh found"
    fi
}

_revive_coord() {
    _tlog "REVIVE COORD: restarting coordinator in tmux"
    _journal "REVIVE_COORD" '{"reason":"process_dead"}'
    # Check if state machine is COMPLETE — don't revive if done
    if [ -n "$_OVERNIGHT_DIR" ] && [ -f "${_OVERNIGHT_DIR}/state.json" ]; then
        _sm=$(grep -o '"state_machine"[[:space:]]*:[[:space:]]*"[^"]*"' "${_OVERNIGHT_DIR}/state.json" 2>/dev/null | grep -o '"[A-Z]*"' | tr -d '"')
        if [ "$_sm" = "COMPLETE" ]; then
            _tlog "COORD revive SKIPPED: state machine is COMPLETE"
            return 0
        fi
    fi
    # Find the coordinator orchestrator
    _orch=""
    # Check for overnight resume prompt
    if [ -f "/tmp/RESUME-COORDINATOR.md" ]; then
        _orch="${UOM_DIR}/bin/uom-resume.sh"
    fi
    if [ -z "$_orch" ]; then
        _orch=$(find "${UOM_DIR}/orchestrators" -name '*coordinator*' -o -name '*triple*' 2>/dev/null | head -1)
    fi
    if [ -z "$_orch" ]; then
        _orch="${UOM_DIR}/orchestrators/uom-solo-orchestrator.sh"
    fi
    if [ -f "$_orch" ]; then
        tmux new-session -d -s coord "sh $_orch" 2>/dev/null || \
            nohup sh "$_orch" >> "${UOM_LOG_DIR}/coord-revive.log" 2>&1 &
        _tlog "COORD revive launched: $_orch"
    else
        _tlog "COORD revive FAILED: no orchestrator found"
    fi
}

_revive_guard() {
    _tlog "REVIVE GUARD: restarting port-guardian"
    _journal "REVIVE_GUARD" '{"reason":"process_dead"}'
    _guard="${UOM_DIR}/orchestrators/uom-port-guardian.sh"
    if [ -f "$_guard" ]; then
        nohup sh "$_guard" >> "${UOM_LOG_DIR}/guard-revive.log" 2>&1 &
        _tlog "GUARD revive launched"
    else
        _tlog "GUARD revive FAILED: $_guard not found"
    fi
}

_revive_antisleep() {
    _tlog "REVIVE ANTI-SL: restarting anti-sleep"
    _journal "REVIVE_ANTISL" '{"reason":"process_dead"}'
    # Anti-sleep is typically a small keepalive script
    _asl=$(find "${UOM_DIR}" -name '*anti-sleep*' -o -name '*antisleep*' 2>/dev/null | head -1)
    if [ -n "$_asl" ] && [ -f "$_asl" ]; then
        nohup sh "$_asl" >> "${UOM_LOG_DIR}/antisleep-revive.log" 2>&1 &
        _tlog "ANTI-SL revive launched"
    else
        _tlog "ANTI-SL revive: no script found, skipping"
    fi
}

# ══════════════════════════════════════════════════════════════════════════
# MODEL HEALTH — wired from uom-model-rotate.sh
# ══════════════════════════════════════════════════════════════════════════
_MODEL_ROTATE="${UOM_DIR}/tools/uom-model-rotate.sh"
_MODEL_STATUS="ok"
_MODEL_LAST_CHECK=0
_MODEL_CONSECUTIVE_FAILS=0

_model_health_check() {
    _now=$(date +%s)
    _elapsed=$((_now - _MODEL_LAST_CHECK))
    _interval=$((MODEL_CHECK_INTERVAL * TRIDENT_CYCLE))
    [ "$_elapsed" -lt "$_interval" ] && return 0

    _MODEL_LAST_CHECK=$_now
    _tlog "MODEL HEALTH CHECK"

    if [ ! -f "$_MODEL_ROTATE" ]; then
        _tlog "model-rotate.sh not found at $_MODEL_ROTATE"
        return 1
    fi

    # Verify current model
    _result=$(sh "$_MODEL_ROTATE" verify 2>&1)
    case "$_result" in
        *VERIFIED*)
            _tlog "MODEL OK: $_result"
            _MODEL_STATUS="ok"
            _MODEL_CONSECUTIVE_FAILS=0
            _journal "MODEL_OK" "{\"detail\":\"$_result\"}"
            ;;
        *FAILED*|*error*|*NONE*)
            _tlog "MODEL FAIL: $_result"
            _MODEL_STATUS="degraded"
            _MODEL_CONSECUTIVE_FAILS=$((_MODEL_CONSECUTIVE_FAILS + 1))
            _journal "MODEL_FAIL" "{\"detail\":\"$_result\",\"consecutive\":$_MODEL_CONSECUTIVE_FAILS}"

            # Auto-rotate if consecutive fails >= 2
            if [ "$_MODEL_CONSECUTIVE_FAILS" -ge 2 ]; then
                _tlog "MODEL AUTO-ROTATE (consecutive fails: $_MODEL_CONSECUTIVE_FAILS)"
                _rotated=$(sh "$_MODEL_ROTATE" next 2>&1)
                _tlog "ROTATE RESULT: $_rotated"
                _journal "MODEL_ROTATE" "{\"result\":\"$_rotated\"}"
                _MODEL_CONSECUTIVE_FAILS=0
            fi
            ;;
        *)
            _tlog "MODEL VERIFY UNEXPECTED: $_result"
            ;;
    esac
}

# ══════════════════════════════════════════════════════════════════════════
# RATE LIMIT TRACKING — inspired by api_wrapper.py
# ══════════════════════════════════════════════════════════════════════════
# Mirrors api_wrapper.py's pacing logic:
#   - MIN_REQUEST_INTERVAL: 100ms between requests
#   - MAX_REQUESTS_PER_MINUTE: 100
#   - Exponential backoff on 429: 1s, 2s, 4s
#   - Retry-After header respect

_RATE_LIMIT_FILE="${UOM_RUNTIME_DIR}/rate-limited-until"
_REQUEST_TIMES_FILE="${UOM_RUNTIME_DIR}/request-times"

_rate_limit_check() {
    # Check if currently rate-limited
    if [ -f "$_RATE_LIMIT_FILE" ]; then
        _until=$(cat "$_RATE_LIMIT_FILE" 2>/dev/null || echo "0")
        _now=$(date +%s)
        if [ "$_now" -lt "$_until" ] 2>/dev/null; then
            _remaining=$((_until - _now))
            _tlog "RATE LIMITED: ${_remaining}s remaining"
            return 0  # is rate limited
        fi
        rm -f "$_RATE_LIMIT_FILE" 2>/dev/null || true
    fi
    return 1  # not rate limited
}

_rate_limit_set() {
    _retry_after="${1:-60}"
    case "$_retry_after" in
        ''|*[!0-9]*) _retry_after=60 ;;
    esac
    _now=$(date +%s)
    _until=$((_now + _retry_after))
    printf '%s\n' "$_until" > "$_RATE_LIMIT_FILE"
    _tlog "RATE LIMIT SET: ${_retry_after}s (until $_until)"
    _journal "RATE_LIMITED" "{\"retry_after\":$_retry_after}"
}

_rate_limit_check_and_warn() {
    if _rate_limit_check; then
        _tlog "⚠ API rate-limited — backing off model probes"
        return 0
    fi
    return 1
}

# ══════════════════════════════════════════════════════════════════════════
# PORT HEALTH — wired from uom-port-watch.sh / uom-canary-sync.sh
# ══════════════════════════════════════════════════════════════════════════
_port_health_check() {
    # Check key ports are responsive
    _ports="3000 8080 8022"
    _any_down=0
    for _port in $_ports; do
        if ! nc -z 127.0.0.1 "$_port" 2>/dev/null; then
            _tlog "PORT DOWN: $_port"
            _any_down=1
        fi
    done
    if [ "$_any_down" -eq 1 ]; then
        _journal "PORT_DEGRADED" '{"detail":"some ports unreachable"}'
    fi
}

# ══════════════════════════════════════════════════════════════════════════
# PHONE HEALTH — wired from uom-ip-discover.sh / endpoint-registry
# ══════════════════════════════════════════════════════════════════════════
_PHONE1_OK=0
_PHONE2_OK=0
_PHONE_LAST_CHECK=0

_phone_health_check() {
    _now=$(date +%s)
    _elapsed=$((_now - _PHONE_LAST_CHECK))
    _interval=$((PHONE_CHECK_INTERVAL * TRIDENT_CYCLE))
    [ "$_elapsed" -lt "$_interval" ] && return 0

    _PHONE_LAST_CHECK=$_now
    _tlog "PHONE HEALTH CHECK"

    # Read registry for phone addresses
    _p1_host=""; _p1_port=""
    _p2_host=""; _p2_port=""
    if [ -f "$REGISTRY_FILE" ] && command -v jq >/dev/null 2>&1; then
        _p1_host=$(jq -r '.phones.phone1.host // empty' "$REGISTRY_FILE" 2>/dev/null)
        _p1_port=$(jq -r '.phones.phone1.port // empty' "$REGISTRY_FILE" 2>/dev/null)
        _p2_host=$(jq -r '.phones.phone2.host // empty' "$REGISTRY_FILE" 2>/dev/null)
        _p2_port=$(jq -r '.phones.phone2.port // empty' "$REGISTRY_FILE" 2>/dev/null)
    fi
    # Fallback defaults
    [ -z "$_p1_host" ] && _p1_host="192.168.40.207"
    [ -z "$_p1_port" ] && _p1_port="8022"
    [ -z "$_p2_host" ] && _p2_host="192.168.40.157"
    [ -z "$_p2_port" ] && _p2_port="8022"

    # Phone1: SSH check
    if ssh -o ConnectTimeout=5 -o BatchMode=yes \
        -i "${HOME}/.ssh/id_ed25519_phone" \
        -p "$_p1_port" "u0_a608@$_p1_host" true 2>/dev/null; then
        _PHONE1_OK=1
        _tlog "PHONE1 OK: $_p1_host:$_p1_port"
    else
        _PHONE1_OK=0
        _tlog "PHONE1 DOWN: $_p1_host:$_p1_port"
    fi

    # Phone2: SSH check
    if ssh -o ConnectTimeout=5 -o BatchMode=yes \
        -i "${HOME}/.ssh/id_ed25519_phone" \
        -p "$_p2_port" "u0_a608@$_p2_host" true 2>/dev/null; then
        _PHONE2_OK=1
        _tlog "PHONE2 OK: $_p2_host:$_p2_port"
    else
        _PHONE2_OK=0
        _tlog "PHONE2 DOWN: $_p2_host:$_p2_port"
    fi

    _journal "PHONE_CHECK" "{\"phone1\":$_PHONE1_OK,\"phone2\":$_PHONE2_OK}"

    # Update heartbeat files
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)
    printf '{"ts":"%s","phone1":%s,"phone2":%s}\n' \
        "$_ts" "$_PHONE1_OK" "$_PHONE2_OK" > "${HEARTBEAT_DIR}/phones.json"
}

# ══════════════════════════════════════════════════════════════════════════
# NETWORK DRIFT — wired from uom-ip-discover.sh
# ══════════════════════════════════════════════════════════════════════════
_NET_OK=1
_NET_LAST_CHECK=0
_LAST_TOPOLOGY=""

_network_drift_check() {
    _now=$(date +%s)
    _elapsed=$((_now - _NET_LAST_CHECK))
    _interval=$((NET_CHECK_INTERVAL * TRIDENT_CYCLE))
    [ "$_elapsed" -lt "$_interval" ] && return 0

    _NET_LAST_CHECK=$_now

    # Source ip-discover functions
    _ipd="${UOM_DIR}/tools/uom-ip-discover.sh"
    if [ -f "$_ipd" ]; then
        . "$_ipd" 2>/dev/null || true
        if net_ok 2>/dev/null; then
            _NET_OK=1
            _my_ip=$(get_my_ip 2>/dev/null || echo "unknown")
            _topo="$_my_ip"
            if [ "$_topo" != "$_LAST_TOPOLOGY" ]; then
                _tlog "NETWORK DRIFT: topology changed to $_topo (was $_LAST_TOPOLOGY)"
                _journal "NET_DRIFT" "{\"old\":\"$_LAST_TOPOLOGY\",\"new\":\"$_topo\"}"
                _LAST_TOPOLOGY="$_topo"
                # Signal port guardian to re-check
                _port_health_check
            fi
        else
            _NET_OK=0
            _tlog "NETWORK DOWN: no connectivity"
            _journal "NET_DOWN" '{}'
        fi
    fi
}

# ══════════════════════════════════════════════════════════════════════════
# FEEDBACK AGGREGATOR — wired from uom-feedback-aggregator.sh
# ══════════════════════════════════════════════════════════════════════════
_FEEDBACK_LAST_RUN=0

_feedback_check() {
    _now=$(date +%s)
    _elapsed=$((_now - _FEEDBACK_LAST_RUN))
    _interval=$((FEEDBACK_INTERVAL * TRIDENT_CYCLE))
    [ "$_elapsed" -lt "$_interval" ] && return 0

    _FEEDBACK_LAST_RUN=$_now
    _fb="${UOM_DIR}/tools/uom-feedback-aggregator.sh"
    if [ -f "$_fb" ]; then
        _result=$(sh "$_fb" --dryrun 2>&1 || true)
        _tlog "FEEDBACK AGGREGATOR: $_result"
    fi
}

# ══════════════════════════════════════════════════════════════════════════
# MAIN SUPERVISION CYCLE
# ══════════════════════════════════════════════════════════════════════════

_supervise_cycle() {
    _cycle_count=$((_cycle_count + 1))
    _now=$(date +%s)
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)

    _tlog "═══ CYCLE $_cycle_count ═══"

    # ── 1. Process liveness ──────────────────────────────────────────────

    # SUPER
    _super_pid=$(_read_pid "$P_SUPER_IDENTITY" 2>/dev/null || echo "")
    if _is_alive "$_super_pid"; then
        _tlog "SUPER: alive (PID $_super_pid)"
    else
        _tlog "SUPER: DEAD (was PID $_super_pid)"
        _journal "SUPER_DEAD" '{"pid":"'$_super_pid'"}'
        _revive_super
    fi

    # COORD
    _coord_pid=$(_read_pid "$P_COORD_IDENTITY" 2>/dev/null || echo "")
    if _is_alive "$_coord_pid"; then
        _tlog "COORD: alive (PID $_coord_pid)"
    else
        _tlog "COORD: DEAD (was PID $_coord_pid)"
        _journal "COORD_DEAD" '{"pid":"'$_coord_pid'"}'
        # Heuristic: if laptop is down (we can't even run), it's a power cut
        # Since we're running, the laptop is alive — revive
        _revive_coord
    fi

    # GUARD
    _guard_pid=$(_read_pid "$P_GUARD_IDENTITY" 2>/dev/null || echo "")
    if _is_alive "$_guard_pid"; then
        _tlog "GUARD: alive (PID $_guard_pid)"
    else
        _tlog "GUARD: DEAD (was PID $_guard_pid)"
        _journal "GUARD_DEAD" '{"pid":"'$_guard_pid'"}'
        _revive_guard
    fi

    # ANTI-SL
    _antisl_pid=$(_read_pid "$P_ANTISL_IDENTITY" 2>/dev/null || echo "")
    if _is_alive "$_antisl_pid"; then
        _tlog "ANTI-SL: alive (PID $_antisl_pid)"
    else
        _tlog "ANTI-SL: DEAD (was PID $_antisl_pid)"
        _journal "ANTISL_DEAD" '{"pid":"'$_antisl_pid'"}'
        _revive_antisleep
    fi

    # ── 2. Rate limit gate ──────────────────────────────────────────────
    _rate_limit_check_and_warn

    # ── 3. Model health (periodic) ──────────────────────────────────────
    _model_health_check

    # ── 4. Port health (every cycle) ────────────────────────────────────
    _port_health_check

    # ── 5. Phone health (periodic) ──────────────────────────────────────
    _phone_health_check

    # ── 6. Network drift (periodic) ─────────────────────────────────────
    _network_drift_check

    # ── 7. Feedback aggregation (periodic) ──────────────────────────────
    _feedback_check

    # ── 8. Write status file ────────────────────────────────────────────
    _write_status

    _tlog "═══ CYCLE $_cycle_count DONE ═══"
}

# ══════════════════════════════════════════════════════════════════════════
# STATUS FILE — machine-readable snapshot
# ══════════════════════════════════════════════════════════════════════════
_write_status() {
    if ! command -v jq >/dev/null 2>&1; then
        return 0
    fi
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)
    jq -n \
        --arg ts "$_ts" \
        --argjson cycle "$_cycle_count" \
        --arg super_pid "${_super_pid:-}" \
        --arg coord_pid "${_coord_pid:-}" \
        --arg guard_pid "${_guard_pid:-}" \
        --arg antisl_pid "${_antisl_pid:-}" \
        --arg model_status "$_MODEL_STATUS" \
        --argjson phone1 "$_PHONE1_OK" \
        --argjson phone2 "$_PHONE2_OK" \
        --argjson net_ok "$_NET_OK" \
        '{
            timestamp: $ts,
            cycle: $cycle,
            processes: {
                SUPER: {pid: $super_pid},
                COORD: {pid: $coord_pid},
                GUARD: {pid: $guard_pid},
                ANTI_SL: {pid: $antisl_pid}
            },
            model_status: $model_status,
            phones: {phone1: $phone1, phone2: $phone2},
            network_ok: $net_ok
        }' > "$STATUS_FILE" 2>/dev/null || true
}

# ══════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════
main() {
    _acquire_lock
    echo "$$" > "$PID_FILE"
    _cycle_count=0

    _init_process_table

    _tlog "trident supervisor started (PID=$$, cycle=${TRIDENT_CYCLE}s)"
    _journal "TRIDENT_STARTED" '{"pid":'$$',"cycle":'$TRIDENT_CYCLE'}'

    # Daemon mode: fork to background
    if [ "${1:-}" = "--daemon" ]; then
        _tlog "running in daemon mode"
    fi

    while [ "$_SHUTDOWN" -eq 0 ]; do
        _supervise_cycle
        # Sleep in small increments so we can catch signals
        _slept=0
        while [ "$_slept" -lt "$TRIDENT_CYCLE" ] && [ "$_SHUTDOWN" -eq 0 ]; do
            _remain=$((TRIDENT_CYCLE - _slept))
            _chunk=5
            [ "$_remain" -lt "$_chunk" ] && _chunk=$_remain
            sleep "$_chunk" & wait $! 2>/dev/null || true
            _slept=$((_slept + _chunk))
        done
    done

    _cleanup
}

main "$@"
