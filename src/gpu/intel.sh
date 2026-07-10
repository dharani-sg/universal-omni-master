#!/bin/sh
# gpu/intel.sh — Intel iGPU management (always primary; typically not unloaded).

gpu_intel_status() {
    _dridir="$(_sysfile /sys/class/drm)"
    [ -d "$_dridir" ] || { echo "no_drm"; return 1; }
    for _rn in "$_dridir"/renderD*; do
        _drv_link="$_rn/device/driver"
        [ -L "$_drv_link" ] || continue
        _drv=$(basename "$(readlink -f "$_drv_link" 2>/dev/null)")
        [ "$_drv" = "i915" ] && { echo "active"; return 0; }
    done
    echo "inactive"
}
