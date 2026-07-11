#!/bin/sh
# diag/services.sh — service audit via omni-service.

audit_services() {
    audit_section "SERVICES"

    _init="$(./bin/omni-detect 2>/dev/null | awk -F'"' '/"init":/{print $4; exit}')"

    case "$_init" in
        openrc)
            _required="networkmanager sddm elogind polkit chronyd smartd alpine-guardian-boot wifi-watchdog dgpu-manager nopm-enforcer"
            _oneshot=""
            ;;
        runit)
            _required="dbus seatd sshd NetworkManager polkitd socklog-unix dgpu-manager nopm-enforcer"
            _oneshot="brightness-restore"
            ;;
        systemd)
            _required="dbus NetworkManager"
            _oneshot=""
            ;;
        *)
            audit_emit unknown services "unknown init=$_init"
            return 0
            ;;
    esac

    for svc in $_required; do
        st="$(./bin/omni-service status "$svc" 2>/dev/null || echo not_found)"
        case "$st" in
            running)
                audit_emit ok services "$svc running"
                ;;
            stopped|not_supervised|disabled_unknown_state)
                audit_emit warn services "$svc not running ($st)"
                ;;
            failed)
                audit_emit fail services "$svc failed"
                ;;
            not_found)
                audit_emit warn services "$svc not found"
                ;;
            *)
                audit_emit unknown services "$svc state=$st"
                ;;
        esac
    done

    for svc in $_oneshot; do
        st="$(./bin/omni-service status "$svc" 2>/dev/null || echo not_found)"
        case "$st" in
            running|stopped|not_supervised|supervised_unknown_state)
                audit_emit info services "$svc one-shot state=$st"
                ;;
            failed)
                audit_emit fail services "$svc failed"
                ;;
        esac
    done
}
