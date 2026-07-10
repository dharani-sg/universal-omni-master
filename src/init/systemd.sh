#!/bin/sh
# systemd service backend — POSIX, SYSROOT-aware for fixture testing.

svc_enable()  { run_as_root systemctl enable  -- "$1"; }
svc_disable() { run_as_root systemctl disable -- "$1"; }
svc_start()   { run_as_root systemctl start   -- "$1"; }
svc_stop()    { run_as_root systemctl stop    -- "$1"; }
svc_restart() { run_as_root systemctl restart -- "$1"; }

svc_status() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        # Fixture mode: inspect /run/systemd filesystem markers only
        _active="$(_sysfile /run/systemd/system/$1.service)"
        _failed="$(_sysfile /run/systemd/failed/$1.service)"
        _unit="$(_sysfile /usr/lib/systemd/system/$1.service)"
        _unit2="$(_sysfile /etc/systemd/system/$1.service)"
        [ -e "$_failed" ]  && { echo "failed";  return 0; }
        [ -e "$_active" ]  && { echo "running"; return 0; }
        { [ -e "$_unit" ] || [ -e "$_unit2" ]; } && { echo "stopped"; return 0; }
        echo "unknown"; return 0
    fi
    # Live mode: invoke real systemctl
    _s=$(systemctl is-active -- "$1" 2>/dev/null)
    case "$_s" in
        active)   echo "running" ;;
        failed)   echo "failed"  ;;
        inactive) echo "stopped" ;;
        *)        echo "unknown" ;;
    esac
}

svc_logs() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then echo "[fixture] no logs in test mode"; return 0; fi
    journalctl -u "$1" -n 50 --no-pager
}
