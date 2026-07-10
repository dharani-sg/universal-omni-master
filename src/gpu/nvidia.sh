#!/bin/sh
# gpu/nvidia.sh — NVIDIA-specific dGPU management.

gpu_nvidia_load() {
    _gpu_guard_mutation || return $?
    _bdf=$(gpu_dgpu_bdf) || { log_error "no NVIDIA dGPU found"; return 1; }
    run_as_root sh -c "echo > /sys/bus/pci/devices/$_bdf/driver_override"
    if ! [ -d /sys/module/nvidia ]; then
        run_as_root modprobe --ignore-install nvidia || \
        run_as_root modprobe nvidia
    fi
    run_as_root sh -c "echo $_bdf > /sys/bus/pci/drivers/nvidia/bind" 2>/dev/null || true
    run_as_root udevadm settle 2>/dev/null || true
}

gpu_nvidia_unload() {
    _gpu_guard_mutation || return $?
    _bdf=$(gpu_dgpu_bdf) || return 1
    _u=$(gpu_dgpu_users)
    [ "${_u:-0}" -gt 0 ] && { log_error "REFUSING unload: $_u process(es) using dGPU"; return 1; }
    run_as_root sh -c "echo $_bdf > /sys/bus/pci/drivers/nvidia/unbind" 2>/dev/null || true
    run_as_root sh -c "echo none > /sys/bus/pci/devices/$_bdf/driver_override" 2>/dev/null || true
    for _mod in nvidia_drm nvidia_modeset nvidia_uvm nvidia; do
        [ -d "/sys/module/$_mod" ] && run_as_root modprobe -r "$_mod" 2>/dev/null || true
    done
}
