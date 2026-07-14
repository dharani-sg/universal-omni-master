#!/bin/sh
# src/deploy/state.sh — M16: Heuristic State Machine for crash-resume deploys.
# Format: key=value, one per line, # comments allowed.
# Atomic writes: temp-file + mv (POSIX-atomic, Btrfs-crash-safe).
# Locking: mkdir (POSIX-atomic, no flock dependency).
# NO JSON, NO eval, NO bashisms.

OMNI_DATA="${OMNI_DATA:-/var/lib/omni-master}"
OMNI_STATE_FILE="${OMNI_STATE_FILE:-$OMNI_DATA/deploy-state.conf}"
OMNI_STATE_LOCK="${OMNI_STATE_LOCK:-${OMNI_STATE_FILE}.lock}"
OMNI_STATE_SCHEMA=1
OMNI_STATE_LOCK_TIMEOUT="${OMNI_STATE_LOCK_TIMEOUT:-10}"

# Fixed ordered list of steps. Callers reference these names.
# Kept intentionally as a space-separated string, NOT a bash array.
OMNI_DEPLOY_STEPS="partitioning mounting bootstrap chroot_setup configure desktop policies initramfs bootloader verify"

_state_guard() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        printf 'state: REFUSING mutation — OMNI_SYSROOT set\n' >&2
        return 126
    fi
    return 0
}

# _state_lock — atomic mkdir lock with polling timeout.
# Returns 0 on lock acquired, 1 on timeout.
_state_lock() {
    _waited=0
    while [ "$_waited" -lt "$OMNI_STATE_LOCK_TIMEOUT" ]; do
        if mkdir "$OMNI_STATE_LOCK" 2>/dev/null; then
            return 0
        fi
        sleep 1
        _waited=$((_waited + 1))
    done
    printf 'state: lock timeout after %ss (%s)\n' "$OMNI_STATE_LOCK_TIMEOUT" "$OMNI_STATE_LOCK" >&2
    return 1
}

_state_unlock() {
    rmdir "$OMNI_STATE_LOCK" 2>/dev/null || true
}

# _state_valid_status — whitelist to reject arbitrary status values.
_state_valid_status() {
    case "$1" in
        pending|running|done|failed|skipped) return 0 ;;
        *) return 1 ;;
    esac
}

# _state_valid_key — reject keys with shell metacharacters.
_state_valid_key() {
    case "$1" in
        ''|*[!A-Za-z0-9_]*) return 1 ;;
        *) return 0 ;;
    esac
}

# _state_atomic_replace_line <key> <value>
# Reads state file, replaces (or appends) key=value, writes to temp, mv.
# Caller must hold the lock.
_state_atomic_replace_line() {
    _key="$1"
    _val="$2"
    _tmp="${OMNI_STATE_FILE}.tmp.$$"

    if [ -f "$OMNI_STATE_FILE" ]; then
        # Emit every line except the existing key= line
        grep -v "^${_key}=" "$OMNI_STATE_FILE" > "$_tmp" 2>/dev/null || :
    else
        mkdir -p "$(dirname "$OMNI_STATE_FILE")" 2>/dev/null || true
        : > "$_tmp"
    fi
    printf '%s=%s\n' "$_key" "$_val" >> "$_tmp"
    mv "$_tmp" "$OMNI_STATE_FILE"
}

# deploy_state_init [distro] [disk] [fs] — fresh state file.
# All steps set to pending. Records session_id + start time.
deploy_state_init() {
    _state_guard || return $?
    _distro="${1:-}"
    _disk="${2:-}"
    _fs="${3:-}"

    _state_lock || return 1

    _session_id="$(date +%s).$$"
    _now="$(date +%s)"
    _tmp="${OMNI_STATE_FILE}.tmp.$$"

    mkdir -p "$(dirname "$OMNI_STATE_FILE")" 2>/dev/null || true

    {
        printf '# omni-deploy state — do not edit manually\n'
        printf 'schema_version=%s\n' "$OMNI_STATE_SCHEMA"
        printf 'session_id=%s\n' "$_session_id"
        printf 'started=%s\n' "$_now"
        printf 'distro=%s\n' "$_distro"
        printf 'disk=%s\n' "$_disk"
        printf 'fs=%s\n' "$_fs"
        printf 'last_error=\n'
        for _step in $OMNI_DEPLOY_STEPS; do
            printf 'step_%s=pending\n' "$_step"
        done
    } > "$_tmp"

    mv "$_tmp" "$OMNI_STATE_FILE"
    _state_unlock
    return 0
}

# deploy_state_set <step> <status>
deploy_state_set() {
    _state_guard || return $?
    _step="${1:?deploy_state_set: step required}"
    _status="${2:?deploy_state_set: status required}"

    _state_valid_key "$_step" || {
        printf 'state: invalid step name: %s\n' "$_step" >&2; return 2; }
    _state_valid_status "$_status" || {
        printf 'state: invalid status: %s\n' "$_status" >&2; return 2; }

    _state_lock || return 1
    _state_atomic_replace_line "step_${_step}" "$_status"
    _state_unlock
    return 0
}

# deploy_state_get <step> — prints status; returns 1 if step not found.
deploy_state_get() {
    _step="${1:?deploy_state_get: step required}"
    [ -f "$OMNI_STATE_FILE" ] || { printf 'pending\n'; return 1; }
    _line=$(grep "^step_${_step}=" "$OMNI_STATE_FILE" 2>/dev/null | head -1)
    if [ -z "$_line" ]; then
        printf 'pending\n'
        return 1
    fi
    printf '%s\n' "${_line#step_${_step}=}"
    return 0
}

# deploy_state_get_meta <key> — read a non-step metadata field.
deploy_state_get_meta() {
    _key="${1:?deploy_state_get_meta: key required}"
    [ -f "$OMNI_STATE_FILE" ] || return 1
    _line=$(grep "^${_key}=" "$OMNI_STATE_FILE" 2>/dev/null | head -1)
    [ -z "$_line" ] && return 1
    printf '%s\n' "${_line#${_key}=}"
    return 0
}

# deploy_state_is_resumable — 0 if a valid prior session exists.
# "Valid" = file exists AND has schema_version=$OMNI_STATE_SCHEMA
# AND at least one step is NOT pending (i.e., real work started).
deploy_state_is_resumable() {
    [ -f "$OMNI_STATE_FILE" ] || return 1
    _schema=$(deploy_state_get_meta schema_version)
    [ "$_schema" = "$OMNI_STATE_SCHEMA" ] || return 1
    # Check if ANY step is not pending
    for _step in $OMNI_DEPLOY_STEPS; do
        _s=$(deploy_state_get "$_step")
        case "$_s" in
            done|running|failed|skipped) return 0 ;;
        esac
    done
    return 1
}

# deploy_state_resume — prints the next step name to execute.
# Semantics: return the FIRST step that is not "done" or "skipped".
# A "running" step is treated as interrupted → resume there.
# A "failed" step is treated as needing retry → resume there.
# Prints "COMPLETE" and returns 0 if all steps are done/skipped.
deploy_state_resume() {
    if [ ! -f "$OMNI_STATE_FILE" ]; then
        for _step in $OMNI_DEPLOY_STEPS; do
            printf '%s\n' "$_step"
            return 0
        done
        printf 'COMPLETE\n'
        return 0
    fi
    for _step in $OMNI_DEPLOY_STEPS; do
        _s=$(deploy_state_get "$_step")
        case "$_s" in
            done|skipped) continue ;;
            *) printf '%s\n' "$_step"; return 0 ;;
        esac
    done
    printf 'COMPLETE\n'
    return 0
}

# deploy_state_fail <step> <reason>
deploy_state_fail() {
    _state_guard || return $?
    _step="${1:?}"
    _reason="${2:-unspecified}"

    _state_valid_key "$_step" || return 2
    _state_lock || return 1
    _state_atomic_replace_line "step_${_step}" "failed"
    _state_atomic_replace_line "last_error" "step=${_step} reason=${_reason}"
    _state_unlock
    return 0
}

# deploy_state_clear — remove state file (call after full success).
deploy_state_clear() {
    _state_guard || return $?
    _state_lock || return 1
    rm -f "$OMNI_STATE_FILE"
    _state_unlock
    return 0
}

# deploy_state_summary — human-readable snapshot.
deploy_state_summary() {
    [ -f "$OMNI_STATE_FILE" ] || {
        printf 'no active deployment state\n'
        return 0
    }
    printf '== OMNI DEPLOY STATE ==\n'
    printf 'session:  %s\n' "$(deploy_state_get_meta session_id)"
    printf 'started:  %s\n' "$(deploy_state_get_meta started)"
    printf 'distro:   %s\n' "$(deploy_state_get_meta distro)"
    printf 'disk:     %s\n' "$(deploy_state_get_meta disk)"
    printf 'fs:       %s\n' "$(deploy_state_get_meta fs)"
    printf '\nSteps:\n'
    for _step in $OMNI_DEPLOY_STEPS; do
        _s=$(deploy_state_get "$_step")
        printf '  %-12s %s\n' "$_step" "$_s"
    done
    _err=$(deploy_state_get_meta last_error)
    if [ -n "$_err" ]; then
        printf '\nlast_error: %s\n' "$_err"
    fi
    _next=$(deploy_state_resume)
    printf '\nresume-at: %s\n' "$_next"
}

# deploy_checkpoint_mirror — M18-B: durable state persistence across power
# cycles. /tmp (or $OMNI_STATE_FILE's default location) does not survive
# reboot; this mirrors the canonical state file to durable storage in a
# priority chain: target ESP first, then target filesystem root.
# Uses $DEPLOY_TARGET (default /mnt) — the LIVE ISO's own /boot/efi is
# NEVER a valid target; only the deployment target's mounted ESP is.
deploy_checkpoint_mirror() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        printf 'checkpoint: REFUSING mirror — OMNI_SYSROOT set\n' >&2
        return 126
    fi

    [ -f "$OMNI_STATE_FILE" ] || {
        printf 'checkpoint: no state file to mirror\n' >&2
        return 1
    }

    _cp_target="${DEPLOY_TARGET:-/mnt}"
    _cp_esp="${_cp_target}/boot/efi"
    _cp_root_mirror="${_cp_target}/.omni-checkpoint.state"

    if [ -d "$_cp_esp" ]; then
        mkdir -p "$_cp_esp/EFI/omni" 2>/dev/null
        if cp "$OMNI_STATE_FILE" "$_cp_esp/EFI/omni/checkpoint.state" 2>/dev/null; then
            printf 'checkpoint: mirrored to ESP (%s)\n' "$_cp_esp/EFI/omni/checkpoint.state" >&2
            return 0
        fi
    fi

    if [ -d "$_cp_target" ]; then
        if cp "$OMNI_STATE_FILE" "$_cp_root_mirror" 2>/dev/null; then
            printf 'checkpoint: mirrored to target root (%s)\n' "$_cp_root_mirror" >&2
            return 0
        fi
    fi

    printf 'checkpoint: FAILED — could not mirror to ESP or target root\n' >&2
    return 1
}
