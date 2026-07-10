#!/bin/sh
# dinit.sh — Dinit backend. Chimera, Artix-dinit.

svc_exists() { _svc_exists_any "/etc/dinit.d/$1"; }

svc_status() {
    svc_exists "$1" || { echo "not_found"; return 1; }
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        _have "/run/dinitd/active/$1" && { echo "running"; return 0; }
        echo "stopped"; return 0
    fi
    _out=$(dinitctl status "$1" 2>&1)
    case "$_out" in
        *"Service status: started"*) echo "running" ;;
        *"Service status: stopped"*) echo "stopped" ;;
        *"Service status: failed"*)  echo "failed"  ;;
        *)                           echo "unknown" ;;
    esac
}

svc_enable()  { _svc_guard_mutation "$1" || return $?; svc_exists "$1" || { log_error "not found: $1"; return 1; }; run_as_root dinitctl enable  "$1"; }
svc_disable() { _svc_guard_mutation "$1" || return $?; run_as_root dinitctl disable "$1"; }
svc_start()   { _svc_guard_mutation "$1" || return $?; svc_exists "$1" || { log_error "not found: $1"; return 1; }; run_as_root dinitctl start   "$1"; }
svc_stop()    { _svc_guard_mutation "$1" || return $?; run_as_root dinitctl stop    "$1"; }
svc_restart() { _svc_guard_mutation "$1" || return $?; svc_exists "$1" || { log_error "not found: $1"; return 1; }; run_as_root dinitctl restart "$1"; }
svc_logs()    { [ -n "${OMNI_SYSROOT:-}" ] && { echo "[fixture] logs unavailable"; return 0; }; log_warn "dinit: check /var/log/$1 or journalctl if available"; }
