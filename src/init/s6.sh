#!/bin/sh
# s6-rc service backend — POSIX, SYSROOT-aware.

svc_enable()  { run_as_root s6-rc-bundle -f add default "$1"; }
svc_disable() { run_as_root s6-rc-bundle -f del default "$1"; }
svc_start()   { run_as_root s6-rc -u change "$1"; }
svc_stop()    { run_as_root s6-rc -d change "$1"; }
svc_restart() { svc_stop "$1" && svc_start "$1"; }

svc_status() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        # s6-rc "live" services appear in /run/s6/servicedirs/ when started
        _live="$(_sysfile /run/s6/servicedirs/$1)"
        _src="$(_sysfile /etc/s6-rc/source/$1)"
        [ -d "$_live" ] && { echo "running"; return 0; }
        [ -e "$_src" ]  && { echo "stopped"; return 0; }
        echo "unknown"; return 0
    fi
    # Live: s6-svstat returns 0 if running
    _spath="/run/service/$1"
    if s6-svstat -o up "$_spath" 2>/dev/null | grep -q "^true"; then
        echo "running"
    elif [ -d "$_spath" ]; then
        echo "stopped"
    else
        echo "unknown"
    fi
}

svc_logs() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then echo "[fixture] no logs in test mode"; return 0; fi
    cat "/run/service/$1/log/current" 2>/dev/null || echo "no log for $1"
}
