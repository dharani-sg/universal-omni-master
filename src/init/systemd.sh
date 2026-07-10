#!/bin/sh
# systemd.sh — systemd backend. Arch/Debian/Fedora targets.
# Fixture convention: /run/systemd/system/<svc>.service = running (active),
# /usr/lib/systemd/system/<svc>.service = installed-but-stopped.

svc_exists()  { _svc_exists_any "/etc/systemd/system/$1.service" "/usr/lib/systemd/system/$1.service" "/lib/systemd/system/$1.service"; }
svc_enabled() { _svc_exists_any "/etc/systemd/system/multi-user.target.wants/$1.service"; }
svc_active()  { _svc_exists_any "/run/systemd/system/$1.service"; }   # fixture convention

svc_status() {
    svc_exists "$1" || { echo "not_found"; return 1; }
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        svc_active "$1"  && { echo "running"; return 0; }
        svc_enabled "$1" && { echo "stopped"; return 0; }
        echo "stopped"; return 0
    fi
    case "$(systemctl is-active "$1" 2>/dev/null)" in
        active)   echo "running" ;;
        inactive) echo "stopped" ;;
        failed)   echo "failed"  ;;
        *)        echo "unknown" ;;
    esac
}

svc_enable()  { _svc_guard_mutation "$1" || return $?; svc_exists "$1" || { log_error "not found: $1"; return 1; }; run_as_root systemctl enable "$1"; }
svc_disable() { _svc_guard_mutation "$1" || return $?; run_as_root systemctl disable "$1"; }
svc_start()   { _svc_guard_mutation "$1" || return $?; svc_exists "$1" || { log_error "not found: $1"; return 1; }; run_as_root systemctl start "$1"; }
svc_stop()    { _svc_guard_mutation "$1" || return $?; run_as_root systemctl stop "$1"; }
svc_restart() { _svc_guard_mutation "$1" || return $?; svc_exists "$1" || { log_error "not found: $1"; return 1; }; run_as_root systemctl restart "$1"; }
svc_logs()    { [ -n "${OMNI_SYSROOT:-}" ] && { echo "[fixture] logs unavailable"; return 0; }; run_as_root journalctl -u "$1" -n "${2:-50}" --no-pager 2>/dev/null || log_warn "journalctl unavailable for $1"; }
