#!/bin/sh
# s6.sh — s6-rc backend. Void-s6 / Obarun / 66.

svc_exists() { _svc_exists_any "/etc/s6-rc/source/$1" "/etc/s6/sv/$1"; }

svc_status() {
    svc_exists "$1" || { echo "not_found"; return 1; }
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        _have "/run/s6/servicedirs/$1" && { echo "running"; return 0; }
        echo "stopped"; return 0
    fi
    _spath="/run/service/$1"
    if s6-svstat -o up "$_spath" 2>/dev/null | grep -q "^true"; then
        echo "running"
    elif [ -d "$_spath" ]; then
        echo "stopped"
    else
        echo "unknown"
    fi
}

svc_enable()  { _svc_guard_mutation "$1" || return $?; run_as_root s6-rc-bundle -f add default "$1"; }
svc_disable() { _svc_guard_mutation "$1" || return $?; run_as_root s6-rc-bundle -f del default "$1"; }
svc_start()   { _svc_guard_mutation "$1" || return $?; svc_exists "$1" || { log_error "not found: $1"; return 1; }; run_as_root s6-rc -u change "$1"; }
svc_stop()    { _svc_guard_mutation "$1" || return $?; run_as_root s6-rc -d change "$1"; }
svc_restart() { _svc_guard_mutation "$1" || return $?; svc_stop "$1" && svc_start "$1"; }
svc_logs()    { [ -n "${OMNI_SYSROOT:-}" ] && { echo "[fixture] logs unavailable"; return 0; }; cat "/run/service/$1/log/current" 2>/dev/null || log_warn "no s6 log for $1"; }
