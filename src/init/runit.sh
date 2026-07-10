#!/bin/sh
# runit.sh — Runit backend. Void reference implementation.
# True running state (run/down/fail) requires live supervise pipe — we
# are HONEST about this in fixture mode: "supervised" vs "not_supervised".

svc_exists()     { _svc_exists_any "/etc/sv/$1"; }
svc_supervised() { _svc_exists_any "/var/service/$1"; }

svc_status() {
    svc_exists "$1" || { echo "not_found"; return 1; }
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        # /run/runit/supervise/<svc>/pid is written by supervise when running.
        _have "/run/runit/supervise/$1/pid" && { echo "running"; return 0; }
        svc_supervised "$1"                 && { echo "stopped"; return 0; }
        echo "not_supervised"; return 0
    fi
    _out=$(sv status "$1" 2>&1)
    case "$_out" in
        run:*)                                echo "running" ;;
        down:*)                               echo "stopped" ;;
        fail:*)                               echo "failed"  ;;
        *"unable to open"*|*"warning"*)       echo "unknown" ;;
        *)                                    echo "unknown" ;;
    esac
}

svc_enable()  { _svc_guard_mutation "$1" || return $?; svc_exists "$1" || { log_error "not found: $1"; return 1; }; run_as_root ln -sf "/etc/sv/$1" "/var/service/$1"; }
svc_disable() { _svc_guard_mutation "$1" || return $?; run_as_root rm -f "/var/service/$1"; }
svc_start()   { _svc_guard_mutation "$1" || return $?; svc_supervised "$1" || { log_error "not supervised: $1"; return 1; }; run_as_root sv start "$1"; }
svc_stop()    { _svc_guard_mutation "$1" || return $?; run_as_root sv stop "$1"; }
svc_restart() { _svc_guard_mutation "$1" || return $?; svc_supervised "$1" || { log_error "not supervised: $1"; return 1; }; run_as_root sv restart "$1"; }

svc_logs() {
    [ -n "${OMNI_SYSROOT:-}" ] && { echo "[fixture] logs unavailable in test mode"; return 0; }
    # svlogd writes to /var/log/<svc>/current — NOT readable via svlogd itself
    cat "/var/log/$1/current" 2>/dev/null || log_warn "no svlogd log directory for $1"
}
