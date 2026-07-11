#!/bin/sh
# healer/gpu.sh — GPU state watchdog; re-applies M4 driver_override policy on resume.

_gpu_card_present() { [ -e /sys/class/drm/card0/device/driver_override ]; }

_gpu_healthy() {
    # Prefer glxinfo when present; otherwise consider a bound driver as healthy.
    if command -v glxinfo >/dev/null 2>&1; then
        glxinfo >/dev/null 2>&1
    else
        [ -e /sys/class/drm/card0/device/driver ]
    fi
}

healer_gpu_loop() {
    healer_emit "gpu" "init" "GPU restoration watchdog started"
    while :; do
        sleep 10
        _gpu_card_present || continue
        if ! _gpu_healthy; then
            healer_emit "gpu" "driver_override" "GPU unhealthy; re-asserting driver_override policy"
            # Delegate to M4 policy if available, else direct override
            if command -v gpu_apply_policy >/dev/null 2>&1; then
                gpu_apply_policy 2>/dev/null || true
            else
                printf 'amdgpu' > /sys/class/drm/card0/device/driver_override 2>/dev/null || true
            fi
        fi
    done
}
