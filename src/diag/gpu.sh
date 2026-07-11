#!/bin/sh
# diag/gpu.sh — GPU audit via omni-gpu.

audit_gpu() {
    audit_section "GPU"

    vendors="$(./bin/omni-gpu vendors 2>/dev/null || echo unknown)"
    count="$(./bin/omni-gpu count 2>/dev/null || echo 0)"
    hybrid="$(./bin/omni-gpu hybrid 2>/dev/null || echo no)"
    dgpu_vendor="$(./bin/omni-gpu dgpu-vendor 2>/dev/null || echo none)"
    dgpu_driver="$(./bin/omni-gpu dgpu-driver 2>/dev/null || echo none)"
    dgpu_bound="$(./bin/omni-gpu dgpu-bound 2>/dev/null || echo no)"
    dgpu_users="$(./bin/omni-gpu dgpu-users 2>/dev/null || echo 0)"

    audit_emit info gpu "vendors=$vendors count=$count hybrid=$hybrid"

    # Guard: no GPUs at all (embedded/BusyBox) — skip GPU policy checks entirely
    if [ "${count:-0}" -eq 0 ]; then
        audit_emit info gpu "no GPUs detected (embedded/minimal system)"
        return 0
    fi

    # Intel iGPU check — only meaningful if at least one GPU exists
    intel="$(./bin/omni-gpu intel-status 2>/dev/null || echo unknown)"
    if [ "$intel" = "active" ]; then
        audit_emit ok gpu "Intel/iGPU render path active"
    elif [ "$intel" = "unknown" ] || [ "$intel" = "no_drm" ]; then
        # Not having Intel is INFO if other GPUs exist, not a failure
        audit_emit info gpu "Intel iGPU not detected or not primary"
    else
        audit_emit warn gpu "Intel/iGPU render path not active (status=$intel)"
    fi

    # dGPU hybrid policy
    if [ "$hybrid" = "yes" ]; then
        if [ "$dgpu_bound" = "no" ]; then
            if [ "$dgpu_driver" = "none" ]; then
                audit_emit ok gpu "dGPU deferred at boot (unbound, no driver)"
            else
                audit_emit info gpu "dGPU module loaded but unbound (safe hybrid idle)"
            fi
        else
            if [ "${dgpu_users:-0}" -gt 0 ]; then
                audit_emit info gpu "dGPU active for workload users=$dgpu_users driver=$dgpu_driver"
            else
                audit_emit warn gpu "dGPU bound but idle users=0 driver=$dgpu_driver"
            fi
        fi
    else
        audit_emit info gpu "non-hybrid or single-GPU topology"
    fi
}
