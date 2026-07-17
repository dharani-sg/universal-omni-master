#!/bin/sh
# bin/uom-statectl.sh — Machine-readable state control CLI
# POSIX sh only. Sources tools/uom-state-lib.sh for state primitives.
# No bashisms. No eval. No arbitrary jq filter exposure.

set -u

# ── Locate and source state library ────────────────────────────────────────
_PROG="$0"
_SCRIPT_DIR="$(cd "$(dirname "$_PROG")" && pwd)"
_REPO_ROOT="$(cd "$_SCRIPT_DIR/.." && pwd)"

# Export OMNI_ROOT so the state library resolves paths correctly
# without relying on BASH_SOURCE (which is not POSIX).
export OMNI_ROOT="$_REPO_ROOT"

# Shellcheck: SC1091 — library is resolved at runtime
# shellcheck source=../tools/uom-state-lib.sh
. "${_REPO_ROOT}/tools/uom-state-lib.sh" || {
    printf 'FATAL: cannot source tools/uom-state-lib.sh\n' >&2
    exit 1
}

uom_state_init

# ── Constants ──────────────────────────────────────────────────────────────
_VALID_MODES="dual phone-solo dual-pending"
_VALID_ROLES="laptop phone none"
_VERSION="0.1.0"

# ── Helpers ────────────────────────────────────────────────────────────────

_ok() {
    printf '{"ok":true,"action":"%s"}\n' "$1"
    exit 0
}

_fail() {
    printf '{"ok":false,"action":"%s","error":"%s"}\n' "$1" "$2" >&2
    exit 1
}

require_arg() {
    _name="$1"; _val="$2"
    if [ -z "$_val" ] || [ "$_val" = "--" ]; then
        _fail "$_cmd" "missing required argument: $_name"
    fi
}

require_lock() {
    uom_state_lock_acquire 10 || _fail "$_cmd" "could not acquire lock (timeout)"
    trap 'uom_state_lock_release' 0 1 2 3 15
}

verify_active_agent() {
    _expected="$1"
    _actual=$(uom_state_get "active_agent")
    if [ "$_actual" != "$_expected" ]; then
        _fail "$_cmd" "active_agent mismatch: expected=$_expected actual=$_actual"
    fi
}

verify_ownership_epoch() {
    _expected="$1"
    _actual=$(uom_state_get "ownership_epoch")
    if [ "${_actual:-0}" != "$_expected" ] 2>/dev/null; then
        _fail "$_cmd" "ownership_epoch mismatch: expected=$_expected actual=$_actual"
    fi
}

validate_writer_authority() {
    _role="$1"
    if ! uom_state_can_write "$_role"; then
        _fail "$_cmd" "role '$_role' is not authorized to write in current state"
    fi
}

# ── Subcommands ────────────────────────────────────────────────────────────

cmd_status() {
    _cmd="status"
    if ! uom_state_validate; then
        _fail "status" "state.json is invalid or missing"
    fi

    # Read-only: output all fields as key=value
    jq -r '
        "schema_version=" + (.schema_version // 0 | tostring),
        "active_agent=" + (.active_agent // ""),
        "writer_role=" + (.writer_role // ""),
        "ownership_epoch=" + (.ownership_epoch // 0 | tostring),
        "lease_id=" + (.lease_id // ""),
        "lease_expires_epoch=" + (.lease_expires_epoch // 0 | tostring),
        "task_status=" + (.task_status // ""),
        "current_task_id=" + (.current_task_id // ""),
        "current_task_desc=" + (.current_task_desc // ""),
        "checkpoint_ref=" + (.checkpoint_ref // ""),
        "takeover_count=" + (.takeover_count // 0 | tostring),
        "last_transition=" + (.last_transition // ""),
        "last_transition_at=" + (.last_transition_at // ""),
        "last_commit=" + (.last_commit // "")
    ' "$UOM_STATE_FILE" 2>/dev/null

    if [ $? -eq 0 ]; then
        exit 0
    else
        _fail "status" "failed to read state"
    fi
}

cmd_get() {
    _cmd="get"
    _field="${1:-}"
    require_arg "FIELD" "$_field"

    if ! uom_state_validate; then
        _fail "get" "state.json is invalid or missing"
    fi

    _val=$(uom_state_get "$_field")
    if [ -z "$_val" ]; then
        # Field exists but is empty string, or doesn't exist — distinguish
        if jq -e "has(\"$_field\")" "$UOM_STATE_FILE" >/dev/null 2>&1; then
            printf '%s\n' ""
            exit 0
        else
            _fail "get" "field '$_field' not found in state"
        fi
    fi
    printf '%s\n' "$_val"
    exit 0
}

cmd_can_write() {
    _cmd="can-write"
    _role="${1:-}"
    require_arg "ROLE" "$_role"

    # Validate role string (no user-controlled filter)
    case "$_role" in
        laptop|phone|none) ;;
        *) _fail "can-write" "invalid role: $_role (expected laptop|phone|none)" ;;
    esac

    if ! uom_state_validate; then
        _fail "can-write" "state.json is invalid or missing"
    fi

    if uom_state_can_write "$_role"; then
        _ok "can-write"
    else
        _fail "can-write" "role '$_role' not authorized to write"
    fi
}

cmd_lease_renew() {
    _cmd="lease-renew"
    _role="${1:-}"
    require_arg "ROLE" "$_role"

    case "$_role" in
        laptop|phone|none) ;;
        *) _fail "lease-renew" "invalid role: $_role" ;;
    esac

    require_lock
    verify_active_agent "dual"
    validate_writer_authority "$_role"

    _epoch=$(uom_state_get "ownership_epoch")
    _now=$(uom_now_epoch)
    _lease_duration=120

    _tmp="${UOM_STATE_FILE}.lr.$$.tmp"
    jq \
        --arg role "$_role" \
        --arg id "$(_now)-$$" \
        --argjson exp "$((_now + _lease_duration))" \
        --argjson epoch "$((_epoch + 1))" \
        '.writer_role = $role | .lease_id = $id | .lease_expires_epoch = $exp | .ownership_epoch = $epoch' \
        "$UOM_STATE_FILE" > "$_tmp" 2>/dev/null

    if ! jq empty "$_tmp" 2>/dev/null; then
        rm -f "$_tmp"
        _fail "lease-renew" "update produced invalid JSON"
    fi

    mv "$_tmp" "$UOM_STATE_FILE"
    chmod 644 "$UOM_STATE_FILE" 2>/dev/null || true
    _ok "lease-renew"
}

cmd_handoff_request() {
    _cmd="handoff-request"

    require_lock

    _cur_mode=$(uom_state_get "active_agent")
    if [ "$_cur_mode" != "dual" ]; then
        _fail "handoff-request" "can only request handoff from dual mode, current=$_cur_mode"
    fi

    _epoch=$(uom_state_get "ownership_epoch")
    _now_utc=$(uom_now_utc)

    _tmp="${UOM_STATE_FILE}.ho.$$.tmp"
    jq \
        --arg mode "dual-pending" \
        --arg ts "$_now_utc" \
        --argjson epoch "$((_epoch + 1))" \
        '.active_agent = $mode | .last_transition = "handoff-request" | .last_transition_at = $ts | .ownership_epoch = $epoch' \
        "$UOM_STATE_FILE" > "$_tmp" 2>/dev/null

    if ! jq empty "$_tmp" 2>/dev/null; then
        rm -f "$_tmp"
        _fail "handoff-request" "update produced invalid JSON"
    fi

    mv "$_tmp" "$UOM_STATE_FILE"
    chmod 644 "$UOM_STATE_FILE" 2>/dev/null || true
    _ok "handoff-request"
}

cmd_transition() {
    _cmd="transition"
    _from="${1:-}"
    _to="${2:-}"
    require_arg "FROM_MODE" "$_from"
    require_arg "TO_MODE" "$_to"

    # Validate mode strings against whitelist (no user-controlled jq)
    case "$_from" in
        dual|phone-solo|dual-pending) ;;
        *) _fail "transition" "invalid FROM_MODE: $_from (expected dual|phone-solo|dual-pending)" ;;
    esac
    case "$_to" in
        dual|phone-solo|dual-pending) ;;
        *) _fail "transition" "invalid TO_MODE: $_to (expected dual|phone-solo|dual-pending)" ;;
    esac

    require_lock

    if ! uom_state_compare_and_update "$_from" "$(uom_state_get "ownership_epoch")" \
        '.active_agent = $to | .last_transition = $trans | .last_transition_at = $ts' \
        --arg to "$_to" --arg trans "$_from→$_to" --arg ts "$(uom_now_utc)"; then
        _fail "transition" "active_agent or epoch mismatch (from=$_from)"
    fi

    _ok "transition"
}

cmd_checkpoint_status() {
    _cmd="checkpoint-status"

    if ! uom_state_validate; then
        _fail "checkpoint-status" "state.json is invalid or missing"
    fi

    # Read-only: emit checkpoint-related fields
    jq -r '
        "checkpoint_ref=" + (.checkpoint_ref // ""),
        "last_commit=" + (.last_commit // ""),
        "current_task_id=" + (.current_task_id // ""),
        "current_task_desc=" + (.current_task_desc // ""),
        "task_status=" + (.task_status // "")
    ' "$UOM_STATE_FILE" 2>/dev/null

    if [ $? -eq 0 ]; then
        exit 0
    else
        _fail "checkpoint-status" "failed to read state"
    fi
}

# ── Usage ──────────────────────────────────────────────────────────────────

usage() {
    cat <<'EOF'
uom-statectl.sh v0.1.0 — UOM machine-readable state control

Usage: uom-statectl.sh <subcommand> [args...]

Read-only subcommands:
  status                  Output all state fields as key=value
  get FIELD               Output a single field value
  can-write ROLE          Check if ROLE is authorized to write (exit 0/1)
  checkpoint-status       Output checkpoint-related state fields

Mutating subcommands:
  lease-renew ROLE        Renew writer lease for ROLE (dual mode only)
  handoff-request         Request transition to dual-pending mode
  transition FROM TO      Atomic mode transition (validates active_agent and epoch)

EOF
    exit 0
}

# ── Dispatch ───────────────────────────────────────────────────────────────

case "${1:-}" in
    status)
        cmd_status
        ;;
    get)
        shift
        cmd_get "$@"
        ;;
    can-write)
        shift
        cmd_can_write "$@"
        ;;
    lease-renew)
        shift
        cmd_lease_renew "$@"
        ;;
    handoff-request)
        cmd_handoff_request
        ;;
    transition)
        shift
        cmd_transition "$@"
        ;;
    checkpoint-status)
        cmd_checkpoint_status
        ;;
    --help|-h|help|"")
        usage
        ;;
    *)
        _fail "dispatch" "unknown subcommand: $1 (run with --help)"
        ;;
esac
