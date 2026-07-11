#!/bin/sh
# healer/services.sh — init-agnostic service watchdog with clamped backoff (M2 integration).

healer_services_loop() {
    healer_emit "services" "init" "service monitor started (watching: $HEALER_WATCH_SERVICES)"
    _fails=0
    while :; do
        _recovered=0
        for _svc in $HEALER_WATCH_SERVICES; do
            if ! healer_svc_active "$_svc"; then
                if healer_svc_restart "$_svc"; then
                    healer_emit "services" "recovery_triggered" "restarted failed service: $_svc"
                    _recovered=1
                else
                    healer_emit "services" "recovery_failed" "could not restart: $_svc"
                    _recovered=1
                fi
            fi
        done
        if [ "$_recovered" -eq 1 ]; then _fails=$(( _fails + 1 )); else _fails=0; fi
        sleep "$(healer_backoff "$_fails")"
    done
}
