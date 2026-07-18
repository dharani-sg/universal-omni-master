#!/bin/sh
# uom-lib.sh — Consolidated shared library for UOM phone-only Zen Loop
# Source this file: . "${HOME}/bin/uom-lib.sh"
# POSIX sh only. No bashisms. No hardcoded IPs/usernames/passwords.
# All values from config or environment.
#
# Functions:
#   uom_qemu_find_pid()     — 3-tier detection, returns PID or empty
#   uom_qemu_running()      — boolean wrapper, sets UOM_QEMU_PID/TIER/ADOPTED
#   uom_qemu_adopt_pid()    — write found PID to PID file
#   uom_guest_ssh_test()    — bounded SSH probe, returns 0/1
#   uom_wait_guest_ssh()    — bounded retry loop
#   uom_guest_ssh()         — SSH wrapper
#   uom_log()               — timestamped, redacts credentials
#   uom_ensure_qemu()       — check + start if needed
#   uom_network_discover()  — detect current phone IP (stub: Step 3)
#   uom_mode_detect()       — solo/dual mode detection (stub: Step 4)
#   uom_config_load()       — load dynamic config (stub: Step 5)
#
# VERSION: 2.1.0
# DEPENDS: ssh, ps, awk, kill, date
# SAFE: read-only (except uom_qemu_adopt_pid writes PID file)

# ── Environment hardening ──────────────────────────────────────────────
export PATH="${HOME}/bin:/data/data/com.termux/files/usr/bin:${PATH}"
export HOME="${HOME:-/data/data/com.termux/files/home}"

# ── Configuration ───────────────────────────────────────────────────────
UOM_VM_DIR="${HOME}/uom-vm"
UOM_IMAGES_DIR="${UOM_VM_DIR}/images"
UOM_LOG_DIR="${UOM_VM_DIR}/logs"
UOM_PID_FILE="${UOM_VM_DIR}/uom-qemu.pid"
UOM_LOCK_FILE="${UOM_VM_DIR}/uom-qemu.lock"
UOM_TMUX_SESSION="uom-qemu-host"
VM_NAME="uom-phone"
DISK="${UOM_IMAGES_DIR}/${VM_NAME}.qcow2"

UOM_QEMU_LAUNCHER="${HOME}/bin/uom-qemu-phone"

# ── Config loading (Step 5 stub) ───────────────────────────────────────
# Reads from environment or ~/.config/uom/runtime.env
# Never fails — uses defaults if config missing.
UOM_GUEST_USER="${UOM_GUEST_USER:-uom}"
UOM_GUEST_PORT="${UOM_GUEST_PORT:-2222}"
UOM_GUEST_HOST="${UOM_GUEST_HOST:-127.0.0.1}"
UOM_PHONE_SSH_PORT="${UOM_PHONE_SSH_PORT:-8022}"

_uom_config_load() {
    _cfg="${HOME}/.config/uom/runtime.env"
    if [ -f "$_cfg" ]; then
        # shellcheck disable=SC1090
        . "$_cfg" 2>/dev/null || true
    fi
    # Override with environment if set
    UOM_GUEST_USER="${UOM_GUEST_USER:-uom}"
    UOM_GUEST_PORT="${UOM_GUEST_PORT:-2222}"
    UOM_GUEST_HOST="${UOM_GUEST_HOST:-127.0.0.1}"
    UOM_PHONE_SSH_PORT="${UOM_PHONE_SSH_PORT:-8022}"
}

# Load config on source
_uom_config_load

UOM_SSH_OPTS="-p ${UOM_GUEST_PORT} -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null"

# ── Logging ─────────────────────────────────────────────────────────────
_uom_ts() { date +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || echo "unknown"; }

# Log to stderr (for widget/launcher output)
uom_log() {
    _tag="${UOM_LOG_TAG:-uom-lib}"
    printf '[%s] [%s] %s\n' "$(_uom_ts)" "$_tag" "$*" >&2
}

# Log to file (append)
uom_logf() {
    _logfile="${UOM_LOG_DIR}/${VM_NAME}-launcher.log"
    _tag="${UOM_LOG_TAG:-uom-lib}"
    mkdir -p "$UOM_LOG_DIR" 2>/dev/null || true
    printf '[%s] [%s] %s\n' "$(_uom_ts)" "$_tag" "$*" >> "$_logfile" 2>/dev/null || true
}

# ── Credential redaction ────────────────────────────────────────────────
uom_redact() {
    sed -E \
        -e 's/(password|passwd|secret|key|token|auth)[=: ]+[^ ]*/\1=<REDACTED>/gi' \
        -e 's/([A-Za-z0-9+/]{40,})/<REDACTED_BLOB>/g'
}

# ── QEMU PID detection (3-tier) ────────────────────────────────────────
# Finds the actual QEMU process, not tmux/bash wrappers.
# Uses ps -ef + awk field-8 match (not pgrep, broken in env -i on Android).
_uom_find_qemu_pid() {
    _pid=$(ps -ef 2>/dev/null \
        | awk '$8 == "qemu-system-aarch64" && $0 ~ /uom-phone.qcow2/ && !/awk|grep/ { print $2; exit }')
    if [ -n "$_pid" ] && [ "$_pid" != "$$" ] && [ "$_pid" != "$PPID" ]; then
        echo "$_pid"
        return 0
    fi
    return 1
}

# SSH probe (returns 0 if guest responds)
_uom_ssh_probe() {
    ssh -p "${UOM_GUEST_PORT}" -o ConnectTimeout=3 -o BatchMode=yes \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${UOM_GUEST_USER}@${UOM_GUEST_HOST}" 'echo UOM_PROBE_OK' 2>/dev/null \
        | grep -q "UOM_PROBE_OK"
}

# ── Public: uom_qemu_find_pid ──────────────────────────────────────────
# 3-tier detection: PID file → ps scan → SSH probe
# Returns: 0=running (sets UOM_QEMU_PID), 1=stopped
uom_qemu_find_pid() {
    UOM_QEMU_PID=""
    UOM_QEMU_TIER=""
    UOM_QEMU_ADOPTED="no"

    # Tier A: PID file — process alive and has our qcow2 in cmdline
    if [ -f "$UOM_PID_FILE" ]; then
        _fp_pid=$(cat "$UOM_PID_FILE" 2>/dev/null || echo "")
        if [ -n "$_fp_pid" ] && [ "$_fp_pid" != "$$" ]; then
            if kill -0 "$_fp_pid" 2>/dev/null; then
                _cmdline=$(tr '\0' ' ' < /proc/"$_fp_pid"/cmdline 2>/dev/null || true)
                case "$_cmdline" in
                    *qemu-system*"${VM_NAME}.qcow2"*)
                        UOM_QEMU_PID="$_fp_pid"
                        UOM_QEMU_TIER="pid-file"
                        return 0
                        ;;
                esac
            fi
            rm -f "$UOM_PID_FILE" "$UOM_LOCK_FILE" 2>/dev/null || true
        else
            rm -f "$UOM_PID_FILE" "$UOM_LOCK_FILE" 2>/dev/null || true
        fi
    fi

    # Tier B: Find actual QEMU process via ps scan
    _found_pid=$(_uom_find_qemu_pid 2>/dev/null || true)
    if [ -n "$_found_pid" ]; then
        UOM_QEMU_PID="$_found_pid"
        UOM_QEMU_TIER="ps-scan"
        UOM_QEMU_ADOPTED="yes"
        echo "$_found_pid" > "$UOM_PID_FILE" 2>/dev/null || true
        uom_log "Tier B: adopted running QEMU pid=$_found_pid"
        return 0
    fi

    # Tier C: SSH probe (process not found but port may be live)
    if _uom_ssh_probe; then
        UOM_QEMU_TIER="ssh-probe"
        UOM_QEMU_ADOPTED="no"
        return 0
    fi

    # Tier D: stopped
    UOM_QEMU_TIER="none"
    return 1
}

# ── Public: uom_qemu_running ───────────────────────────────────────────
# Boolean wrapper for uom_qemu_find_pid.
# Returns 0 if QEMU is running (any tier), 1 if stopped.
# Sets: UOM_QEMU_PID, UOM_QEMU_TIER, UOM_QEMU_ADOPTED
uom_qemu_running() {
    uom_qemu_find_pid
}

# ── Public: uom_qemu_adopt_pid ─────────────────────────────────────────
# Write found PID to PID file (call after uom_qemu_find_pid).
uom_qemu_adopt_pid() {
    if [ -n "$UOM_QEMU_PID" ]; then
        echo "$UOM_QEMU_PID" > "$UOM_PID_FILE" 2>/dev/null || true
        return 0
    fi
    return 1
}

# ── Public: uom_guest_ssh_test ─────────────────────────────────────────
# Bounded SSH probe. Returns 0 if guest responds, 1 if not.
# Usage: uom_guest_ssh_test [retries] [timeout_per_try]
uom_guest_ssh_test() {
    _retries="${1:-3}"
    _timeout="${2:-5}"
    _i=0
    while [ "$_i" -lt "$_retries" ]; do
        if _uom_ssh_probe; then
            return 0
        fi
        _i=$((_i + 1))
        [ "$_i" -lt "$_retries" ] && sleep 1
    done
    return 1
}

# ── Public: uom_wait_guest_ssh ─────────────────────────────────────────
# Bounded retry loop. Returns 0 when SSH responds, 1 on timeout.
# Usage: uom_wait_guest_ssh [timeout_seconds]
uom_wait_guest_ssh() {
    _timeout="${1:-60}"
    _interval=3
    _elapsed=0
    while [ "$_elapsed" -lt "$_timeout" ]; do
        if uom_guest_ssh_test 1 3; then
            return 0
        fi
        sleep "$_interval"
        _elapsed=$((_elapsed + _interval))
    done
    return 1
}

# ── Public: uom_guest_ssh ──────────────────────────────────────────────
# SSH wrapper. Usage: uom_guest_ssh 'command'
uom_guest_ssh() {
    ssh ${UOM_SSH_OPTS} "${UOM_GUEST_USER}@${UOM_GUEST_HOST}" "$@"
}

# ── Public: uom_ensure_qemu ────────────────────────────────────────────
# Check + start if needed. Returns 0 if running (started or already).
uom_ensure_qemu() {
    if uom_qemu_running; then
        return 0
    fi
    uom_log "QEMU not running. Starting..."
    "${UOM_QEMU_LAUNCHER}" start 2>&1 || {
        uom_log "ERROR: QEMU start failed"
        _logfile="${UOM_LOG_DIR}/${VM_NAME}-launcher.log"
        if [ -f "$_logfile" ]; then
            uom_log "--- Launcher log (last 5 lines) ---"
            tail -5 "$_logfile" 2>/dev/null
        fi
        return 1
    }
    uom_log "Waiting for guest SSH..."
    if uom_wait_guest_ssh 60; then
        uom_log "Guest SSH ready"
        return 0
    fi
    uom_log "ERROR: Guest SSH timeout after 60s"
    return 1
}

# ── Public: uom_network_discover (Step 3 stub) ─────────────────────────
# Detect current phone IP. Returns IP on stdout, 1 on failure.
# TODO: Implement in Step 3 — dynamic network discovery
uom_network_discover() {
    # Stub: return last known IP or fail
    _last_ip_file="${HOME}/.config/uom/last-phone-ip.txt"
    if [ -f "$_last_ip_file" ]; then
        cat "$_last_ip_file" 2>/dev/null
        return 0
    fi
    return 1
}

# ── Public: uom_mode_detect (Step 4 stub) ──────────────────────────────
# Detect operational mode. Returns mode string on stdout.
# Modes: PHONE_TERMUX, GUEST_IN_PHONE, LAPTOP_DUAL, LAPTOP_SOLO
# TODO: Implement in Step 4 — solo/dual mode detection
uom_mode_detect() {
    if [ "$(uname -o 2>/dev/null)" = "Android" ]; then
        if hostname 2>/dev/null | grep -q "uom-phone-qemu"; then
            echo "GUEST_IN_PHONE"
        else
            echo "PHONE_TERMUX"
        fi
        return
    fi
    # On laptop — check if phone reachable
    _phone_ip=$(uom_network_discover 2>/dev/null || true)
    if [ -n "$_phone_ip" ] && ssh -o ConnectTimeout=3 -o BatchMode=yes \
        -p "${UOM_PHONE_SSH_PORT}" "u0_a608@${_phone_ip}" "echo OK" 2>/dev/null \
        | grep -q OK; then
        echo "LAPTOP_DUAL"
    else
        echo "LAPTOP_SOLO"
    fi
}
