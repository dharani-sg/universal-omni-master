#!/bin/sh
# healer/common.sh — shared config, audit emitter, backoff for omni-healer.

HEALER_CONF="${HEALER_CONF:-/etc/omni-healer.conf}"
HEALER_AUDIT_LOG="${HEALER_AUDIT_LOG:-/var/log/omni-audit.json}"
HEALER_PIDFILE="${HEALER_PIDFILE:-/run/omni-healer.pid}"

# Defaults (overridable via /etc/omni-healer.conf)
HEALER_STORAGE_MONITOR="${HEALER_STORAGE_MONITOR:-1}"
HEALER_SERVICE_MONITOR="${HEALER_SERVICE_MONITOR:-1}"
HEALER_GPU_RESTORE="${HEALER_GPU_RESTORE:-1}"
HEALER_INTERVAL_BASE="${HEALER_INTERVAL_BASE:-5}"
HEALER_INTERVAL_MAX="${HEALER_INTERVAL_MAX:-60}"
HEALER_WATCH_SERVICES="${HEALER_WATCH_SERVICES:-dbus}"

healer_load_conf() {
    [ -f "$HEALER_CONF" ] && . "$HEALER_CONF"
    :
}

# _json_escape inherited from core/utils.sh

# Unified structured audit event (M6 integration point)
healer_emit() {
    _comp=$(_json_escape "$1")
    _evt=$(_json_escape "$2")
    _msg=$(_json_escape "$3")
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    printf '{"timestamp":"%s","component":"%s","event":"%s","message":"%s"}\n' \
        "$_ts" "$_comp" "$_evt" "$_msg" >> "$HEALER_AUDIT_LOG" 2>/dev/null || true
}

# Clamped exponential backoff — POSIX (no '**' operator).
# T_poll = min(T_max, T_base * 2^n), computed iteratively.
healer_backoff() {
    _n="${1:-0}"
    _iv="$HEALER_INTERVAL_BASE"
    _i=0
    while [ "$_i" -lt "$_n" ]; do
        _iv=$(( _iv * 2 ))
        [ "$_iv" -ge "$HEALER_INTERVAL_MAX" ] && { _iv="$HEALER_INTERVAL_MAX"; break; }
        _i=$(( _i + 1 ))
    done
    printf '%s' "$_iv"
}

# Delegates to init module's svc_status (from core/utils.sh → init/interface.sh)
healer_svc_active() {
    command -v svc_status >/dev/null 2>&1 || return 0
    _st=$(svc_status "$1" 2>/dev/null)
    [ "$_st" = "running" ]
}

# Delegates to init module's svc_restart (from core/utils.sh → init/interface.sh)
healer_svc_restart() {
    command -v svc_restart >/dev/null 2>&1 || return 1
    svc_restart "$1" 2>/dev/null
}

# Ensure runtime directories exist. Called from bin/omni-healer at startup.
# On fresh installs, /var/log and /run may exist but sub-dirs may not.
healer_ensure_paths() {
    _logdir=$(dirname "$HEALER_AUDIT_LOG")
    [ -n "$_logdir" ] && [ ! -d "$_logdir" ] && mkdir -p "$_logdir" 2>/dev/null
    _piddir=$(dirname "$HEALER_PIDFILE")
    [ -n "$_piddir" ] && [ ! -d "$_piddir" ] && mkdir -p "$_piddir" 2>/dev/null
    :
}
