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

# Minimal JSON string escaping: backslash, double-quote, control chars stripped.
_json_escape() {
    printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Unified structured audit event (M6 integration point)
healer_emit() {
    _comp=$(_json_escape "$1")
    _evt=$(_json_escape "$2")
    _msg=$(_json_escape "$3")
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    printf '{"timestamp":"%s","component":"%s","event":"%s","message":"%s"}\n' \
        "$_ts" "$_comp" "$_evt" "$_msg" >> "$HEALER_AUDIT_LOG" 2>/dev/null || true
}

# Clamped exponential backoff — POSIX has no '**'; double iteratively.
# usage: healer_backoff <fail_count>  -> prints interval seconds
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

# Init-agnostic service status/restart (M2 abstraction pattern)
healer_svc_active() {
    _svc="$1"
    if [ -d /run/systemd/system ]; then systemctl is-active "$_svc" >/dev/null 2>&1
    elif [ -d /run/openrc ]; then rc-service "$_svc" status >/dev/null 2>&1
    elif [ -d /var/service ] || [ -d /run/runit ]; then sv status "$_svc" 2>/dev/null | grep -q '^run:'
    elif command -v dinitctl >/dev/null 2>&1; then dinitctl status "$_svc" 2>/dev/null | grep -qi started
    else return 0  # unknown init: assume healthy, never thrash
    fi
}

healer_svc_restart() {
    _svc="$1"
    if [ -d /run/systemd/system ]; then systemctl restart "$_svc" 2>/dev/null
    elif [ -d /run/openrc ]; then rc-service "$_svc" restart 2>/dev/null
    elif [ -d /var/service ] || [ -d /run/runit ]; then sv restart "$_svc" 2>/dev/null
    elif command -v dinitctl >/dev/null 2>&1; then dinitctl restart "$_svc" 2>/dev/null
    else return 1
    fi
}
