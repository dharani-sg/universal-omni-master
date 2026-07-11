#!/bin/sh
# diag/power.sh — no-PM runtime policy checks.

audit_power_policy() {
    audit_section "POWER POLICY"

    if [ -n "${OMNI_SYSROOT:-}" ]; then
        audit_emit info power "fixture mode: runtime power policy skipped"
        return 0
    fi

    gov="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)"
    [ "$gov" = "performance" ] \
        && audit_emit ok power "CPU governor=performance" \
        || audit_emit warn power "CPU governor=$gov"

    ps="$(cat /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null || echo unknown)"
    [ "$ps" = "0" ] \
        && audit_emit ok power "snd_hda_intel power_save=0" \
        || audit_emit warn power "snd_hda_intel power_save=$ps"

    ctl="$(cat /sys/module/snd_hda_intel/parameters/power_save_controller 2>/dev/null || echo unknown)"
    [ "$ctl" = "N" ] \
        && audit_emit ok power "snd_hda_intel power_save_controller=N" \
        || audit_emit warn power "snd_hda_intel power_save_controller=$ctl"

    if command -v iw >/dev/null 2>&1; then
        iw dev wlan0 get power_save 2>/dev/null | grep -q off \
            && audit_emit ok power "WiFi power_save=off" \
            || audit_emit warn power "WiFi power_save not off"
    fi
}
