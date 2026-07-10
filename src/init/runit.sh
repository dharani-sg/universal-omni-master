#!/bin/sh
# Runit service backend — POSIX, SYSROOT-aware for fixture testing.

svc_enable()  { run_as_root ln -sf "/etc/sv/$1" "/var/service/$1"; }
svc_disable() { run_as_root rm -f "/var/service/$1"; }
svc_start()   { run_as_root sv start "$1"; }
svc_stop()    { run_as_root sv stop  "$1"; }
svc_restart() { run_as_root sv restart "$1"; }

svc_status() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        # Fixture mode: check filesystem markers only.
        # Runit: /var/service/<svc> is a symlink to /etc/sv/<svc> when enabled.
        # A "run" file must exist in the sv dir for it to be "configured".
        _link="$(_sysfile /var/service/$1)"
        _svdir="$(_sysfile /etc/sv/$1)"
        _run_marker="$(_sysfile /run/runit/supervise/$1/pid)"
        [ -e "$_run_marker" ] && { echo "running"; return 0; }
        [ -L "$_link" ]       && { echo "stopped"; return 0; }
        [ -d "$_svdir" ]      && { echo "stopped"; return 0; }
        echo "unknown"; return 0
    fi
    # Live mode: sv outputs "run: <svc>: <N>s" or "down: <svc>: <N>s"
    _out=$(sv status "$1" 2>&1)
    case "$_out" in
        run:*)  echo "running" ;;
        down:*) echo "stopped" ;;
        fail:*) echo "failed"  ;;
        *"unable to open"*|*"warning"*) echo "unknown" ;;
        *) echo "unknown" ;;
    esac
}

svc_logs() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then echo "[fixture] no logs in test mode"; return 0; fi
    cat "/var/log/$1/current" 2>/dev/null || svlogd -t "/var/log/$1" 2>/dev/null || echo "no log for $1"
}
