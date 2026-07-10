#!/bin/sh
# OpenRC service backend — POSIX, SYSROOT-aware for fixture testing.

svc_enable()  { run_as_root rc-update add "$1" default; }
svc_disable() { run_as_root rc-update del "$1" default; }
svc_start()   { run_as_root rc-service "$1" start; }
svc_stop()    { run_as_root rc-service "$1" stop; }
svc_restart() { run_as_root rc-service "$1" restart; }

svc_status() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        # Fixture mode: inspect filesystem markers only.
        # OpenRC writes to /run/openrc/started/<svc> when a service is running.
        _started="$(_sysfile /run/openrc/started/$1)"
        _initd="$(_sysfile /etc/init.d/$1)"
        [ -e "$_started" ] && { echo "running"; return 0; }
        [ -e "$_initd" ]   && { echo "stopped"; return 0; }
        echo "unknown"; return 0
    fi
    # Live mode: rc-service exit codes: 0=started, 1=stopped, 3=stopped, 8=crashed
    rc-service "$1" status >/dev/null 2>&1
    _r=$?
    case "$_r" in
        0) echo "running" ;;
        1|3) echo "stopped" ;;
        8) echo "failed"  ;;
        *) echo "unknown" ;;
    esac
}

svc_logs() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then echo "[fixture] no logs in test mode"; return 0; fi
    # OpenRC itself has no unified log; fall back to syslog if socklog/syslogd present
    if command -v svlogd >/dev/null 2>&1; then
        cat "/var/log/$1/current" 2>/dev/null || echo "no socklog for $1"
    else
        grep "$1" /var/log/messages 2>/dev/null | tail -50
    fi
}
