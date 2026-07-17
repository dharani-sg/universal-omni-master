#!/bin/sh
# tools/uom-state-lib.sh — POSIX shared state library with atomic locking
# Safe to source multiple times. No bashisms. No eval.
# Use jq --arg/--argjson for all data. Never raw-filter user input.

# ── Guard: source-safe ────────────────────────────────────────────────────
if [ -n "${_UOM_STATE_LIB_LOADED:-}" ]; then
    return 0 2>/dev/null || true
fi
_UOM_STATE_LIB_LOADED=1

# ── Resolve repo root ─────────────────────────────────────────────────────
# Prefer OMNI_ROOT if set, else resolve relative to this file.
_uom_resolve_root() {
    if [ -n "${OMNI_ROOT:-}" ] && [ -d "${OMNI_ROOT}/.uom-agent" ]; then
        printf '%s\n' "$OMNI_ROOT"
        return
    fi
    _self="${0}"
    _dir="$(cd "$(dirname "$_self")/.." 2>/dev/null && pwd)"
    if [ -d "${_dir}/.uom-agent" ]; then
        printf '%s\n' "$_dir"
        return
    fi
    # Fallback: search upward from cwd
    _d="$(pwd)"
    while [ "$_d" != "/" ]; do
        if [ -d "${_d}/.uom-agent" ]; then
            printf '%s\n' "$_d"
            return
        fi
        _d="$(dirname "$_d")"
    done
    printf '%s\n' "$(pwd)"
}

UOM_REPO_ROOT="${OMNI_ROOT:-$(_uom_resolve_root)}"
export OMNI_ROOT="$UOM_REPO_ROOT"

# ── Derived paths ──────────────────────────────────────────────────────────
UOM_STATE_DIR="${UOM_REPO_ROOT}/.uom-agent"
UOM_STATE_FILE="${UOM_STATE_DIR}/state.json"
UOM_QUEUE_FILE="${UOM_STATE_DIR}/queue.json"
UOM_DONE_FILE="${UOM_STATE_DIR}/done.json"
UOM_RUNTIME_DIR="${UOM_STATE_DIR}/runtime"
UOM_LOG_DIR="${UOM_STATE_DIR}/logs"
UOM_RECOVERY_DIR="${UOM_STATE_DIR}/recovery"

# ── Helpers ────────────────────────────────────────────────────────────────

_uom_log() {
    _ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)"
    printf '[uom-state] %s %s\n' "$_ts" "$*"
}

# Safe error logging to file
_uom_log_file() {
    _logfile="${UOM_LOG_DIR}/state-lib.log"
    [ -d "$(dirname "$_logfile")" ] || mkdir -p "$(dirname "$_logfile")"
    _ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)"
    printf '[uom-state] %s %s\n' "$_ts" "$*" >> "$_logfile" 2>/dev/null || true
}

# ── uom_tmpdir ─────────────────────────────────────────────────────────────
# Returns path to safe temporary directory (same filesystem as state).
uom_tmpdir() {
    _uom_td="${TMPDIR:-$HOME/tmp}"
    mkdir -p "$_uom_td" 2>/dev/null || true
    chmod 700 "$_uom_td" 2>/dev/null || true
    printf '%s\n' "$_uom_td"
}

# ── uom_now_epoch ──────────────────────────────────────────────────────────
uom_now_epoch() {
    date -u +%s 2>/dev/null || echo 0
}

# ── uom_now_utc ────────────────────────────────────────────────────────────
uom_now_utc() {
    date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u
}

# ── uom_state_init ─────────────────────────────────────────────────────────
# Create state directories and default state files if missing.
# Does not overwrite existing files.
uom_state_init() {
    mkdir -p "$UOM_STATE_DIR" "$UOM_RUNTIME_DIR" "$UOM_LOG_DIR" "$UOM_RECOVERY_DIR"
    chmod 700 "$UOM_RUNTIME_DIR" 2>/dev/null || true

    if [ ! -f "$UOM_STATE_FILE" ]; then
        printf '%s\n' '{"schema_version":2,"active_agent":"dual","writer_role":"laptop","ownership_epoch":0,"lease_id":"","lease_expires_epoch":0,"task_status":"idle","current_task_id":"","current_task_desc":"","checkpoint_ref":"","takeover_count":0,"last_transition":"","last_transition_at":"","last_commit":""}' > "$UOM_STATE_FILE"
        chmod 644 "$UOM_STATE_FILE" 2>/dev/null || true
    fi
    if [ ! -f "$UOM_QUEUE_FILE" ]; then
        printf '%s\n' '[]' > "$UOM_QUEUE_FILE"
    fi
    if [ ! -f "$UOM_DONE_FILE" ]; then
        printf '%s\n' '[]' > "$UOM_DONE_FILE"
    fi

    # Migrate schema if needed
    uom_state_migrate
}

# ── uom_state_validate ─────────────────────────────────────────────────────
# Returns 0 if state.json is valid JSON with required keys.
uom_state_validate() {
    [ -f "$UOM_STATE_FILE" ] || return 1
    jq -e '.active_agent' "$UOM_STATE_FILE" >/dev/null 2>&1 || return 1
    # Check it's valid JSON
    jq empty "$UOM_STATE_FILE" 2>/dev/null || return 1
    return 0
}

# ── uom_state_migrate ──────────────────────────────────────────────────────
# Additively migrate state to schema v2. Preserves unknown keys.
uom_state_migrate() {
    [ -f "$UOM_STATE_FILE" ] || return 1
    jq empty "$UOM_STATE_FILE" 2>/dev/null || return 1

    _cur_schema=$(jq -r '.schema_version // .schema // 0' "$UOM_STATE_FILE" 2>/dev/null)
    if [ "$_cur_schema" -ge 2 ] 2>/dev/null; then
        return 0
    fi

    _tmp="${UOM_STATE_FILE}.migration.$$.tmp"
    jq '
        .schema_version = 2 |
        .active_agent = (.active_agent // "dual") |
        .writer_role = (.writer_role // "laptop") |
        .ownership_epoch = (.ownership_epoch // 0) |
        .lease_id = (.lease_id // "") |
        .lease_expires_epoch = (.lease_expires_epoch // 0) |
        .task_status = (.task_status // "idle") |
        .current_task_id = (.current_task_id // "") |
        .current_task_desc = (.current_task_desc // "") |
        .checkpoint_ref = (.checkpoint_ref // "") |
        .takeover_count = (.takeover_count // 0) |
        .last_transition = (.last_transition // "") |
        .last_transition_at = (.last_transition_at // "") |
        .last_commit = (.last_commit // "")
    ' "$UOM_STATE_FILE" > "$_tmp" 2>/dev/null

    if jq empty "$_tmp" 2>/dev/null; then
        mv "$_tmp" "$UOM_STATE_FILE"
        chmod 644 "$UOM_STATE_FILE" 2>/dev/null || true
        _uom_log "state migrated to schema v2"
    else
        rm -f "$_tmp"
        _uom_log "WARNING: migration produced invalid JSON, skipping"
        return 1
    fi
}

# ── uom_state_get ──────────────────────────────────────────────────────────
# Get a value from state.json. Returns empty string on missing.
uom_state_get() {
    _field="$1"
    jq -r ".$_field // empty" "$UOM_STATE_FILE" 2>/dev/null
}

# ── uom_state_lock_acquire ─────────────────────────────────────────────────
# Acquire an atomic mkdir-based lock adjacent to the state file.
# Sets _UOM_LOCK_DIR for later release.
# Returns 0 on success, 1 on timeout/failure.
# Usage: uom_state_lock_acquire [timeout_seconds]
uom_state_lock_acquire() {
    _timeout="${1:-30}"
    _lock_dir="${UOM_STATE_FILE}.lock"
    _start=$(uom_now_epoch)

    while true; do
        if mkdir "$_lock_dir" 2>/dev/null; then
            _UOM_LOCK_DIR="$_lock_dir"
            # Write lock metadata
            printf '%s\n' "$(id -un)@$(hostname 2>/dev/null || echo unknown)" > "$_lock_dir/who"
            printf '%s\n' "$$" > "$_lock_dir/pid"
            printf '%s\n' "$(uom_now_epoch)" > "$_lock_dir/acquired"
            printf '%s\n' "$UOM_STATE_FILE" > "$_lock_dir/state_path"
            chmod 700 "$_lock_dir" 2>/dev/null || true
            return 0
        fi

        # Lock exists — check if stale
        _lock_pid=""
        [ -f "$_lock_dir/pid" ] && _lock_pid=$(cat "$_lock_dir/pid" 2>/dev/null)
        _lock_acquired=""
        [ -f "$_lock_dir/acquired" ] && _lock_acquired=$(cat "$_lock_dir/acquired" 2>/dev/null)

        # Check if same-host PID is dead
        if [ -n "$_lock_pid" ]; then
            if kill -0 "$_lock_pid" 2>/dev/null; then
                # Lock is held by a live process on this host
                :
            else
                # PID is dead — safe to reclaim after brief grace
                _age=$(($(uom_now_epoch) - ${_lock_acquired:-0}))
                if [ "${_age:-0}" -ge 2 ] 2>/dev/null; then
                    _uom_log "reclaiming dead-PID lock (pid=$_lock_pid, age=${_age}s)"
                    _uom_log_file "reclaim dead-PID lock pid=$_lock_pid"
                    rm -rf "$_lock_dir" 2>/dev/null || true
                    continue
                fi
            fi
        else
            # No PID file — metadata malformed
            _age=$(($(uom_now_epoch) - ${_lock_acquired:-0}))
            if [ "${_age:-0}" -ge 10 ] 2>/dev/null; then
                _uom_log "reclaiming malformed lock (age=${_age}s)"
                _uom_log_file "reclaim malformed lock age=$_age"
                rm -rf "$_lock_dir" 2>/dev/null || true
                continue
            fi
        fi

        # Check timeout
        _elapsed=$(($(uom_now_epoch) - _start))
        if [ "$_elapsed" -ge "$_timeout" ] 2>/dev/null; then
            _uom_log "lock acquisition timeout after ${_elapsed}s"
            return 1
        fi

        sleep 1 2>/dev/null || true
    done
}

# ── uom_state_lock_release ─────────────────────────────────────────────────
# Release the lock we acquired. Only removes our own lock.
uom_state_lock_release() {
    _lock_dir="${_UOM_LOCK_DIR:-${UOM_STATE_FILE}.lock}"
    [ ! -d "$_lock_dir" ] && return 0

    # Verify we own it
    _our_pid=""
    [ -f "$_lock_dir/pid" ] && _our_pid=$(cat "$_lock_dir/pid" 2>/dev/null)
    if [ "$_our_pid" = "$$" ]; then
        rm -rf "$_lock_dir" 2>/dev/null || true
        _UOM_LOCK_DIR=""
        return 0
    fi
    _uom_log "WARNING: not removing lock owned by pid=$_our_pid (ours=$$)"
    return 1
}

# ── uom_state_update_filter ────────────────────────────────────────────────
# Atomically update state.json with a jq filter.
# Usage: uom_state_update_filter FILTER [JQ_ARGS...]
# Example: uom_state_update_filter '.active_agent = $mode' --arg mode phone-solo
uom_state_update_filter() {
    _filter="$1"; shift
    _tmp="${UOM_STATE_FILE}.update.$$.tmp"

    jq "$_filter" "$@" "$UOM_STATE_FILE" > "$_tmp" 2>/dev/null

    if ! jq empty "$_tmp" 2>/dev/null; then
        rm -f "$_tmp"
        _uom_log "ERROR: update produced invalid JSON, state unchanged"
        _uom_log_file "invalid JSON from filter: $_filter"
        return 1
    fi

    # Validate state structure
    if ! jq -e '.active_agent' "$_tmp" >/dev/null 2>&1; then
        rm -f "$_tmp"
        _uom_log "ERROR: update missing active_agent, state unchanged"
        return 1
    fi

    mv "$_tmp" "$UOM_STATE_FILE"
    chmod 644 "$UOM_STATE_FILE" 2>/dev/null || true
    return 0
}

# ── uom_state_compare_and_update ───────────────────────────────────────────
# Update state only if current active_agent and ownership_epoch match expected.
# Usage: uom_state_compare_and_update EXPECTED_MODE EXPECTED_EPOCH FILTER [JQ_ARGS...]
# Returns 0 on success, 1 if expected values don't match.
uom_state_compare_and_update() {
    _exp_mode="$1"; _exp_epoch="$2"; _filter="$3"; shift 3

    _cur_mode=$(uom_state_get "active_agent")
    _cur_epoch=$(uom_state_get "ownership_epoch")

    if [ "$_cur_mode" != "$_exp_mode" ]; then
        _uom_log "compare-and-update rejected: expected mode=$_exp_mode, got=$_cur_mode"
        return 1
    fi
    if [ "${_cur_epoch:-0}" != "${_exp_epoch:-0}" ] 2>/dev/null; then
        _uom_log "compare-and-update rejected: expected epoch=$_exp_epoch, got=$_cur_epoch"
        return 1
    fi

    # Apply the update with new epoch
    _tmp="${UOM_STATE_FILE}.cau.$$.tmp"
    jq "$_filter" --argjson epoch "$((_exp_epoch + 1))" "$@" "$UOM_STATE_FILE" > "$_tmp" 2>/dev/null

    if ! jq empty "$_tmp" 2>/dev/null; then
        rm -f "$_tmp"
        _uom_log "ERROR: compare-and-update produced invalid JSON"
        return 1
    fi

    # Re-check that epoch was incremented correctly (filter changes mode, so don't check it)
    _recheck_epoch=$(jq -r '.ownership_epoch // 0' "$_tmp" 2>/dev/null)
    if [ "${_recheck_epoch:-0}" != "$((_exp_epoch + 1))" ]; then
        rm -f "$_tmp"
        _uom_log "ERROR: compare-and-update post-check failed: epoch not incremented"
        return 1
    fi

    mv "$_tmp" "$UOM_STATE_FILE"
    chmod 644 "$UOM_STATE_FILE" 2>/dev/null || true
    _uom_log "compare-and-update succeeded: mode=$_exp_mode epoch=$((_exp_epoch + 1))"
    return 0
}

# ── uom_state_can_write ────────────────────────────────────────────────────
# Returns 0 if the specified role is authorized to write tasks.
# Usage: uom_state_can_write [laptop|phone|none]
uom_state_can_write() {
    _role="${1:-laptop}"
    _mode=$(uom_state_get "active_agent")
    _writer=$(uom_state_get "writer_role")
    _lease_exp=$(uom_state_get "lease_expires_epoch")
    _now=$(uom_now_epoch)

    case "$_mode" in
        dual)
            if [ "$_role" = "laptop" ] && [ "$_writer" = "laptop" ]; then
                # Check lease validity
                if [ "${_lease_exp:-0}" -gt "$_now" ] 2>/dev/null; then
                    return 0
                fi
            fi
            return 1
            ;;
        phone-solo)
            if [ "$_role" = "phone" ] && [ "$_writer" = "phone" ]; then
                return 0
            fi
            return 1
            ;;
        dual-pending)
            # No new task writes allowed
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# ── uom_heartbeat_write ────────────────────────────────────────────────────
# Write heartbeat to runtime file (not state.json, avoids Git churn).
# Usage: uom_heartbeat_write laptop
uom_heartbeat_write() {
    _agent="$1"
    _now=$(uom_now_epoch)
    _utc=$(uom_now_utc)
    mkdir -p "$UOM_RUNTIME_DIR"
    printf '%s\n' "$_now" > "${UOM_RUNTIME_DIR}/${_agent}.heartbeat"
    printf '%s\n' "${_now}|${_utc}" >> "${UOM_RUNTIME_DIR}/${_agent}.heartbeat.log"
    # Also update state.json heartbeat field for compatibility
    uom_state_update_filter ".${_agent}_heartbeat = \$hb" --arg hb "$_utc"
}

# ── uom_heartbeat_read ─────────────────────────────────────────────────────
# Read heartbeat epoch for an agent. Returns 0 if fresh, 1 if stale/missing.
# Usage: uom_heartbeat_read laptop [max_age_seconds]
uom_heartbeat_read() {
    _agent="$1"
    _max_age="${2:-300}"
    _hb_file="${UOM_RUNTIME_DIR}/${_agent}.heartbeat"

    if [ ! -f "$_hb_file" ]; then
        return 1
    fi

    _hb_epoch=$(head -1 "$_hb_file" 2>/dev/null)
    _now=$(uom_now_epoch)
    _age=$(($_now - ${_hb_epoch:-0}))

    if [ "$_age" -le "$_max_age" ] 2>/dev/null; then
        return 0
    fi
    return 1
}

# ── Convenience: state_update (thin wrapper) ───────────────────────────────
# Usage: state_update field value (for simple string updates)
state_update() {
    _field="$1"; _val="$2"
    uom_state_update_filter ".$_field = \$val" --arg val "$_val"
}

# Backward-compatible aliases for scripts that source this via orch-state
state_get() { uom_state_get "$@"; }
state_init() { uom_state_init; }
state_set() { state_update "$@"; }

# ── Cleanup on trap ────────────────────────────────────────────────────────
# Call from caller: trap 'uom_state_lock_release' 0 HUP INT TERM
# Do NOT install traps automatically here.
