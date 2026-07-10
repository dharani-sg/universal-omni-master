#!/bin/sh
# openrc.sh — OpenRC service backend. Alpine reference implementation.
# Status uses filesystem markers (NOT rc-service exit codes — they are version-unstable).

svc_exists() { _svc_exists_any "/etc/init.d/$1"; }

svc_status() {
    svc_exists "$1" || { echo "not_found"; return 1; }
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        _have "/run/openrc/started/$1"  && { echo "running";  return 0; }
        _have "/run/openrc/stopping/$1" && { echo "stopping"; return 0; }
        echo "stopped"; return 0
    fi
    _out=$(rc-service "$1" status 2>/dev/null)
    case "$_out" in
        *started*|*running*) echo "running"  ;;
        *crashed*)           echo "failed"   ;;
        *stopped*)           echo "stopped"  ;;
        *)                   echo "unknown"  ;;
    esac
}

svc_enable()  { _svc_guard_mutation "$1" || return $?; svc_exists "$1" || { log_error "not found: $1"; return 1; }; run_as_root rc-update add "$1" default; }
svc_disable() { _svc_guard_mutation "$1" || return $?; run_as_root rc-update del "$1" default; }
svc_start()   { _svc_guard_mutation "$1" || return $?; svc_exists "$1" || { log_error "not found: $1"; return 1; }; run_as_root rc-service "$1" start; }
svc_stop()    { _svc_guard_mutation "$1" || return $?; run_as_root rc-service "$1" stop; }
svc_restart() { _svc_guard_mutation "$1" || return $?; svc_exists "$1" || { log_error "not found: $1"; return 1; }; run_as_root rc-service "$1" restart; }

svc_logs() {
    [ -n "${OMNI_SYSROOT:-}" ] && { echo "[fixture] logs unavailable in test mode"; return 0; }
    grep "$1" /var/log/messages 2>/dev/null | tail -50 || log_warn "no log found for $1"
}
