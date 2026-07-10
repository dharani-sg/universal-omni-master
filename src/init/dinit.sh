#!/bin/sh
# Dinit service backend (Chimera, Artix-dinit) — POSIX, SYSROOT-aware.

svc_enable()  { run_as_root dinitctl enable  "$1"; }
svc_disable() { run_as_root dinitctl disable "$1"; }
svc_start()   { run_as_root dinitctl start   "$1"; }
svc_stop()    { run_as_root dinitctl stop    "$1"; }
svc_restart() { run_as_root dinitctl restart "$1"; }

svc_status() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        _def="$(_sysfile /etc/dinit.d/$1)"
        _run="$(_sysfile /run/dinitd/active/$1)"
        [ -e "$_run" ] && { echo "running"; return 0; }
        [ -e "$_def" ] && { echo "stopped"; return 0; }
        echo "unknown"; return 0
    fi
    _out=$(dinitctl status "$1" 2>&1)
    case "$_out" in
        *"Service status: started"*) echo "running" ;;
        *"Service status: stopped"*) echo "stopped" ;;
        *"Service status: failed"*)  echo "failed"  ;;
        *) echo "unknown" ;;
    esac
}

svc_logs() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then echo "[fixture] no logs in test mode"; return 0; fi
    echo "dinit: check /var/log/$1 or journalctl if available"
}
