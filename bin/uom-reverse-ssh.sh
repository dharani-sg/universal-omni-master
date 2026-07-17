#!/bin/sh
# bin/uom-reverse-ssh.sh — Phone-initiated reverse SSH tunnel to laptop
# Runs on the phone (Termux). Creates: laptop:31415 -> phone:8022
# POSIX sh compatible. No bashisms. No Termux-specific shebang.
#
# Subcommands: start (default), stop, restart, status, foreground

set -eu

# ── Defaults ────────────────────────────────────────────────────────────
UOM_LAPTOP_HOST="${UOM_LAPTOP_HOST:-}"
UOM_LAPTOP_USER="${UOM_LAPTOP_USER:-alpine}"
UOM_LAPTOP_SSH_PORT="${UOM_LAPTOP_SSH_PORT:-22}"
UOM_PHONE_USER="${UOM_PHONE_USER:-$(id -un 2>/dev/null || echo user)}"
UOM_TUNNEL_PORT="${UOM_TUNNEL_PORT:-31415}"
UOM_PHONE_SSH_PORT="${UOM_PHONE_SSH_PORT:-8022}"
UOM_SSH_KEY="${UOM_SSH_KEY:-}"
UOM_SERVER_ALIVE_INTERVAL="${UOM_SERVER_ALIVE_INTERVAL:-30}"
UOM_SERVER_ALIVE_COUNT_MAX="${UOM_SERVER_ALIVE_COUNT_MAX:-3}"
UOM_AUTOSSH_MONITOR_PORT="${UOM_AUTOSSH_MONITOR_PORT:-0}"
UOM_LOG_MAX_BYTES="${UOM_LOG_MAX_BYTES:-1048576}"

# ── Paths ───────────────────────────────────────────────────────────────
SCRIPT_DIR="${0%/*}"
UOM_ROOT="${SCRIPT_DIR}/.."
UOM_STATE_DIR="${UOM_ROOT}/.uom-agent"
UOM_LOCK_DIR="${UOM_STATE_DIR}/locks"
UOM_RUNTIME_DIR="${UOM_STATE_DIR}/runtime"
UOM_LOG_DIR="${UOM_STATE_DIR}/logs"
UOM_LOG="${UOM_LOG_DIR}/tunnel.log"
UOM_PID_FILE="${UOM_RUNTIME_DIR}/tunnel.pid"
LOCK_DIR="${UOM_LOCK_DIR}/reverse-ssh"

# Fallback log location if state dir is not writable
FALLBACK_LOG="${TMPDIR:-${HOME}/tmp}/uom-tunnel.log"

# ── Logging ─────────────────────────────────────────────────────────────
_log() {
    _ts=$(date +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
    _msg="[uom-rev-ssh] ${_ts} $*"
    printf '%s\n' "$_msg" >> "${ACTIVE_LOG}" 2>/dev/null || true
    printf '%s\n' "$_msg" >&2
}

_init_log() {
    if [ -d "${UOM_LOG_DIR}" ] && [ -w "${UOM_LOG_DIR}" ]; then
        ACTIVE_LOG="${UOM_LOG}"
    else
        mkdir -p "${TMPDIR:-${HOME}/tmp}" 2>/dev/null || true
        ACTIVE_LOG="${FALLBACK_LOG}"
    fi
    _rotate_log
}

_rotate_log() {
    [ ! -f "${ACTIVE_LOG}" ] && return 0
    _size=$(wc -c < "${ACTIVE_LOG}" 2>/dev/null || echo 0)
    # Strip leading whitespace from size
    _size=$(echo "$_size" | tr -d '[:space:]')
    if [ "$_size" -gt "$UOM_LOG_MAX_BYTES" ] 2>/dev/null; then
        _half=$((UOM_LOG_MAX_BYTES / 2))
        if command -v tail >/dev/null 2>&1; then
            tail -c "${_half}" "${ACTIVE_LOG}" > "${ACTIVE_LOG}.tmp" 2>/dev/null && \
                mv "${ACTIVE_LOG}.tmp" "${ACTIVE_LOG}" 2>/dev/null || true
        else
            : > "${ACTIVE_LOG}"
        fi
    fi
}

# ── Directory setup ─────────────────────────────────────────────────────
_ensure_dirs() {
    mkdir -p "${UOM_STATE_DIR}" 2>/dev/null || true
    mkdir -p "${UOM_LOCK_DIR}" 2>/dev/null || true
    mkdir -p "${UOM_RUNTIME_DIR}" 2>/dev/null || true
    mkdir -p "${UOM_LOG_DIR}" 2>/dev/null || true
    mkdir -p "${TMPDIR:-${HOME}/tmp}" 2>/dev/null || true
}

# ── Locking (single-instance via mkdir) ─────────────────────────────────
_acquire_lock() {
    if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
        # Lock exists — check if holder is still alive
        if [ -f "${LOCK_DIR}/pid" ]; then
            _old_pid=$(cat "${LOCK_DIR}/pid" 2>/dev/null || echo "")
            if [ -n "$_old_pid" ] && _pid_is_tunnel "$_old_pid"; then
                _log "ERROR: Another instance is running (PID ${_old_pid})."
                exit 1
            fi
            _log "Stale lock from PID ${_old_pid}. Cleaning up."
            _release_lock
            if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
                _log "ERROR: Could not acquire lock after cleanup."
                exit 1
            fi
        else
            _log "ERROR: Lock directory exists but no PID file. Manual cleanup needed: rm -rf ${LOCK_DIR}"
            exit 1
        fi
    fi
    echo "$$" > "${LOCK_DIR}/pid"
}

_release_lock() {
    rm -f "${LOCK_DIR}/pid" 2>/dev/null || true
    rmdir "${LOCK_DIR}" 2>/dev/null || true
}

# ── PID management (safe, validated) ────────────────────────────────────
_pid_is_tunnel() {
    _pid="$1"
    # Must be a number
    case "${_pid}" in
        ''|*[!0-9]*) return 1 ;;
    esac
    # Must be running
    if ! kill -0 "$_pid" 2>/dev/null; then
        return 1
    fi
    # Must be an actual ssh or autossh process
    _cmd=$(ps -p "$_pid" -o args= 2>/dev/null || true)
    case "$_cmd" in
        *ssh*|*autossh*) return 0 ;;
    esac
    return 1
}

_write_pid() {
    echo "$$" > "${UOM_PID_FILE}"
}

_clear_pid() {
    rm -f "${UOM_PID_FILE}" 2>/dev/null || true
}

_validate_running() {
    if [ -f "${UOM_PID_FILE}" ]; then
        _pid=$(cat "${UOM_PID_FILE}" 2>/dev/null || echo "")
        if _pid_is_tunnel "$_pid"; then
            return 0
        fi
    fi
    return 1
}

# ── Laptop host discovery ───────────────────────────────────────────────
_discover_laptop_host() {
    # Priority 1: Explicit environment variable
    if [ -n "${UOM_LAPTOP_HOST}" ]; then
        echo "${UOM_LAPTOP_HOST}"
        return 0
    fi

    # Priority 2: Stored host files
    _host_file=""
    for _f in "${UOM_STATE_DIR}/laptop.host" "${UOM_STATE_DIR}/laptop.ip"; do
        if [ -f "$_f" ]; then
            _host_file="$_f"
            break
        fi
    done
    if [ -n "${_host_file}" ]; then
        _stored=$(cat "${_host_file}" 2>/dev/null | tr -d '[:space:]')
        if [ -n "${_stored}" ]; then
            echo "${_stored}"
            return 0
        fi
    fi

    # Priority 3: Source and call uom-ip-discover.sh
    for _d in "${SCRIPT_DIR}/../tools" "${SCRIPT_DIR}"; do
        if [ -f "${_d}/uom-ip-discover.sh" ]; then
            _found=""
            # Source the file to get functions, suppress errors
            . "${_d}/uom-ip-discover.sh" 2>/dev/null || true
            if command -v discover_laptop_ip >/dev/null 2>&1; then
                _found=$(discover_laptop_ip 2>/dev/null || true)
            fi
            if [ -n "${_found}" ]; then
                echo "${_found}"
                return 0
            fi
        fi
    done

    # Priority 4: Error
    return 1
}

# ── Preflight checks ────────────────────────────────────────────────────
_preflight() {
    _errors=0

    # ssh binary
    if ! command -v ssh >/dev/null 2>&1; then
        _log "FATAL: ssh not found in PATH."
        _errors=$((_errors + 1))
    fi

    # Key file
    if [ -n "${UOM_SSH_KEY}" ]; then
        if [ ! -f "${UOM_SSH_KEY}" ]; then
            _log "WARNING: SSH key ${UOM_SSH_KEY} does not exist."
        fi
    fi

    # Laptop host
    LAPTOP_HOST=$(_discover_laptop_host) || {
        _log "FATAL: Cannot determine laptop host."
        _log "  Set UOM_LAPTOP_HOST, create ${UOM_STATE_DIR}/laptop.host, or ensure uom-ip-discover.sh is available."
        exit 1
    }

    # Port must be numeric
    case "${UOM_TUNNEL_PORT}" in
        ''|*[!0-9]*)
            _log "FATAL: UOM_TUNNEL_PORT must be numeric, got '${UOM_TUNNEL_PORT}'."
            exit 1
            ;;
    esac
    case "${UOM_PHONE_SSH_PORT}" in
        ''|*[!0-9]*)
            _log "FATAL: UOM_PHONE_SSH_PORT must be numeric, got '${UOM_PHONE_SSH_PORT}'."
            exit 1
            ;;
    esac

    # Already running?
    if _validate_running; then
        _log "ERROR: Tunnel is already running (PID $(cat "${UOM_PID_FILE}" 2>/dev/null))."
        _log "  Use '$0 restart' or '$0 stop' first."
        exit 1
    fi
}

# ── Build SSH command ───────────────────────────────────────────────────
_build_ssh_opts() {
    _opts="-N -T -o ServerAliveInterval=${UOM_SERVER_ALIVE_INTERVAL}"
    _opts="${_opts} -o ServerAliveCountMax=${UOM_SERVER_ALIVE_COUNT_MAX}"
    _opts="${_opts} -o ExitOnForwardFailure=yes"
    _opts="${_opts} -o StrictHostKeyChecking=accept-new"
    _opts="${_opts} -o ConnectTimeout=15"
    _opts="${_opts} -o BatchMode=yes"
    if [ -n "${UOM_SSH_KEY}" ] && [ -f "${UOM_SSH_KEY}" ]; then
        _opts="${_opts} -i ${UOM_SSH_KEY}"
    fi
    echo "${_opts}"
}

# ── Build forwarding argument ───────────────────────────────────────────
_build_forward_arg() {
    echo "-R 127.0.0.1:${UOM_TUNNEL_PORT}:127.0.0.1:${UOM_PHONE_SSH_PORT}"
}

# ── Start tunnel ────────────────────────────────────────────────────────
_cmd_start() {
    _ensure_dirs
    _init_log
    _preflight

    _acquire_lock
    # Release lock on exit
    trap '_release_lock; _clear_pid; exit 0' HUP INT TERM

    _ssh_opts=$(_build_ssh_opts)
    _fwd=$(_build_forward_arg)
    _target="${UOM_LAPTOP_USER}@${LAPTOP_HOST}"

    _log "Starting reverse tunnel: laptop:${UOM_TUNNEL_PORT} -> phone:${UOM_PHONE_SSH_PORT}"
    _log "Target: ${_target} (SSH port ${UOM_LAPTOP_SSH_PORT})"
    _log "Forward: ${_fwd}"

    _write_pid

    if command -v autossh >/dev/null 2>&1; then
        _log "Using autossh for auto-reconnect."
        export AUTOSSH_LOGFILE="${ACTIVE_LOG}"
        export AUTOSSH_LOGLEVEL=4
        export AUTOSSH_POLL=30
        export AUTOSSH_GATETIME=0
        export AUTOSSH_PORT="${UOM_AUTOSSH_MONITOR_PORT}"

        exec autossh -M "${UOM_AUTOSSH_MONITOR_PORT}" \
            -p "${UOM_LAPTOP_SSH_PORT}" \
            ${_ssh_opts} \
            ${_fwd} \
            "${_target}"
    else
        _log "autossh not found. Using ssh with manual retry loop."
        while true; do
            _write_pid
            ssh -p "${UOM_LAPTOP_SSH_PORT}" \
                ${_ssh_opts} \
                ${_fwd} \
                "${_target}"
            _rc=$?
            _log "Tunnel exited (RC=${_rc}). Reconnecting in 10s..."
            sleep 10
            # Re-check host discovery in case IP changed
            LAPTOP_HOST=$(_discover_laptop_host) || {
                _log "WARNING: Lost laptop host. Retrying discovery..."
                sleep 30
                continue
            }
            _target="${UOM_LAPTOP_USER}@${LAPTOP_HOST}"
        done
    fi
}

# ── Stop tunnel ─────────────────────────────────────────────────────────
_cmd_stop() {
    _ensure_dirs
    _init_log

    if [ ! -f "${UOM_PID_FILE}" ]; then
        _log "No PID file found. Tunnel may not be running."
        # Try to clean lock anyway
        _release_lock 2>/dev/null || true
        return 0
    fi

    _pid=$(cat "${UOM_PID_FILE}" 2>/dev/null || echo "")
    if [ -z "${_pid}" ]; then
        _log "PID file is empty. Cleaning up."
        _clear_pid
        _release_lock 2>/dev/null || true
        return 0
    fi

    if _pid_is_tunnel "${_pid}"; then
        _log "Stopping tunnel (PID ${_pid})..."
        kill "${_pid}" 2>/dev/null || true
        # Wait for process to exit
        _wait=0
        while [ "${_wait}" -lt 10 ]; do
            kill -0 "${_pid}" 2>/dev/null || break
            sleep 1
            _wait=$((_wait + 1))
        done
        if kill -0 "${_pid}" 2>/dev/null; then
            _log "Force killing PID ${_pid}..."
            kill -9 "${_pid}" 2>/dev/null || true
            sleep 1
        fi
        _log "Tunnel stopped."
    else
        _log "PID ${_pid} is not a running ssh/autossh process. Cleaning stale PID file."
    fi

    _clear_pid
    _release_lock 2>/dev/null || true
}

# ── Status ──────────────────────────────────────────────────────────────
_cmd_status() {
    _ensure_dirs
    _init_log

    if [ -f "${UOM_PID_FILE}" ]; then
        _pid=$(cat "${UOM_PID_FILE}" 2>/dev/null || echo "")
        if _pid_is_tunnel "${_pid}"; then
            echo "RUNNING (PID ${_pid})"
            echo "  Forward: 127.0.0.1:${UOM_TUNNEL_PORT} -> 127.0.0.1:${UOM_PHONE_SSH_PORT}"
            echo "  Log: ${ACTIVE_LOG}"
            return 0
        else
            echo "NOT RUNNING (stale PID ${_pid})"
        fi
    else
        echo "NOT RUNNING"
    fi
    return 1
}

# ── Foreground (start without exec, for debugging) ──────────────────────
_cmd_foreground() {
    _ensure_dirs
    _init_log
    _preflight

    _acquire_lock
    trap '_release_lock; _clear_pid; exit 0' HUP INT TERM

    _ssh_opts=$(_build_ssh_opts)
    _fwd=$(_build_forward_arg)
    _target="${UOM_LAPTOP_USER}@${LAPTOP_HOST}"

    _log "Starting reverse tunnel (foreground/debug): laptop:${UOM_TUNNEL_PORT} -> phone:${UOM_PHONE_SSH_PORT}"
    _log "Target: ${_target} (SSH port ${UOM_LAPTOP_SSH_PORT})"
    _log "Forward: ${_fwd}"

    _write_pid

    if command -v autossh >/dev/null 2>&1; then
        _log "Using autossh."
        export AUTOSSH_LOGFILE="${ACTIVE_LOG}"
        export AUTOSSH_LOGLEVEL=4
        export AUTOSSH_POLL=30
        export AUTOSSH_GATETIME=0
        export AUTOSSH_PORT="${UOM_AUTOSSH_MONITOR_PORT}"

        autossh -M "${UOM_AUTOSSH_MONITOR_PORT}" \
            -p "${UOM_LAPTOP_SSH_PORT}" \
            ${_ssh_opts} \
            ${_fwd} \
            "${_target}"
    else
        _log "Using ssh."
        ssh -p "${UOM_LAPTOP_SSH_PORT}" \
            ${_ssh_opts} \
            ${_fwd} \
            "${_target}"
    fi

    _rc=$?
    _log "Process exited (RC=${_rc})."
    _clear_pid
    _release_lock
}

# ── Main ────────────────────────────────────────────────────────────────
_active_log=""
ACTIVE_LOG="${TMPDIR:-${HOME}/tmp}/uom-tunnel.log"

_cmd="${1:-start}"
case "${_cmd}" in
    start)     _cmd_start ;;
    stop)      _cmd_stop ;;
    restart)
        _cmd_stop 2>/dev/null || true
        sleep 2
        _cmd_start
        ;;
    status)    _cmd_status ;;
    foreground|fg) _cmd_foreground ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|foreground}" >&2
        exit 1
        ;;
esac
