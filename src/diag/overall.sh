#!/bin/sh
# diag/overall.sh — top-level dispatcher.

audit_overall() {
    audit_section "OMNI AUDIT START"
    audit_emit info overall "sysroot=${OMNI_SYSROOT:-/}"

    audit_platform
    audit_services
    audit_gpu
    audit_storage
    audit_boot
    audit_network
    audit_audio_session
    audit_power_policy

    audit_section "SUMMARY"
    sev="$(audit_exit_code)"

    case "$sev" in
        0) audit_emit ok overall "overall OK" ;;
        1) audit_emit warn overall "warnings or unknowns present" ;;
        2) audit_emit fail overall "failures present" ;;
        3) audit_emit critical overall "critical issues present" ;;
        *) audit_emit internal overall "internal severity error"; sev=4 ;;
    esac

    return "$sev"
}
