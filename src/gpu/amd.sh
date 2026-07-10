#!/bin/sh
# gpu/amd.sh — AMD-specific dGPU management (radeon/amdgpu drivers).

gpu_amd_load() {
    _gpu_guard_mutation || return $?
    _bdf=$(gpu_dgpu_bdf) || { log_error "no AMD dGPU found"; return 1; }
    # Clear driver_override to allow binding
    run_as_root sh -c "echo > /sys/bus/pci/devices/$_bdf/driver_override"
    # Load module (bypass install=/bin/true directive)
    if ! [ -d /sys/module/amdgpu ]; then
        run_as_root modprobe --ignore-install amdgpu || \
            run_as_root insmod "/lib/modules/$(uname -r)/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko"
    fi
    # Trigger bind
    run_as_root sh -c "echo $_bdf > /sys/bus/pci/drivers/amdgpu/bind" 2>/dev/null || true
    run_as_root udevadm settle 2>/dev/null || true
}

gpu_amd_unload() {
    _gpu_guard_mutation || return $?
    _bdf=$(gpu_dgpu_bdf) || return 1
    _u=$(gpu_dgpu_users)
    [ "${_u:-0}" -gt 0 ] && { log_error "REFUSING unload: $_u process(es) using dGPU"; return 1; }
    run_as_root sh -c "echo $_bdf > /sys/bus/pci/drivers/amdgpu/unbind" 2>/dev/null || true
    run_as_root sh -c "echo none > /sys/bus/pci/devices/$_bdf/driver_override" 2>/dev/null || true
    [ -d /sys/module/amdgpu ] && run_as_root modprobe -r amdgpu 2>/dev/null || true
}
