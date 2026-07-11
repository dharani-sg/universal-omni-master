#!/bin/sh
# diag/platform.sh — platform + hardware summary.

audit_platform() {
    audit_section "PLATFORM"

    data="$(./bin/omni-detect 2>/dev/null || true)"

    get() { printf '%s\n' "$data" | awk -F'"' -v k="$1" '$2==k {print $4; exit}'; }

    distro="$(get distro)"
    init="$(get init)"
    libc="$(get libc)"
    pkg="$(get pkgmgr)"
    priv="$(get priv_helper)"
    boot="$(get bootloader)"
    cpu="$(get cpu_model)"
    gpus="$(get gpu_vendors)"
    storage="$(get storage)"

    audit_emit info platform "distro=${distro:-unknown} init=${init:-unknown} libc=${libc:-unknown}"
    audit_emit info platform "pkgmgr=${pkg:-unknown} priv=${priv:-unknown} boot=${boot:-unknown}"
    audit_emit info platform "cpu=${cpu:-unknown}"
    audit_emit info platform "gpu=${gpus:-unknown}"
    audit_emit info platform "storage=${storage:-unknown}"

    [ -z "$distro" ] && audit_emit unknown platform "distro not detected"
    [ "$init" = "unknown" ] && audit_emit unknown platform "init unknown"
}
