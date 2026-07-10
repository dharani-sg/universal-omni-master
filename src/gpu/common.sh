#!/bin/sh
# gpu/common.sh — GPU EAL: detection, binding state, mutation guard.

_gpu_guard_mutation() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        log_error "REFUSING GPU mutation: OMNI_SYSROOT is set (fixture/offline mode)."
        return 126
    fi
    return 0
}

# Enumerate all PCI GPUs. Emits lines: <bdf>|<vendor_id>|<device_id>|<driver_or_none>
_gpu_enumerate() {
    _pcidir="$(_sysfile /sys/bus/pci/devices)"
    [ -d "$_pcidir" ] || return 1
    for _dev in "$_pcidir"/*; do
        [ -d "$_dev" ] || continue
        _class_f="$_dev/class"
        [ -r "$_class_f" ] || continue
        _class=$(cat "$_class_f" 2>/dev/null)
        case "$_class" in
            0x030000|0x030200|0x038000) : ;;
            *) continue ;;
        esac
        _bdf=$(basename "$_dev")
        _vid=$(cat "$_dev/vendor" 2>/dev/null | sed 's/^0x//')
        _did=$(cat "$_dev/device" 2>/dev/null | sed 's/^0x//')
        _drv="none"
        [ -L "$_dev/driver" ] && _drv=$(basename "$(readlink -f "$_dev/driver" 2>/dev/null)" 2>/dev/null)
        printf '%s|%s|%s|%s\n' "$_bdf" "$_vid" "$_did" "$_drv"
    done
}

# Get list of GPU vendors present (canonical names, comma-separated)
gpu_vendors() {
    _gpu_enumerate 2>/dev/null | awk -F'|' '{print $2}' | sort -u | while read -r _v; do
        case "$_v" in
            8086) echo Intel ;;
            1002) echo AMD ;;
            10de) echo NVIDIA ;;
            *)    echo "Unknown($_v)" ;;
        esac
    done | sort -u | tr '\n' ',' | sed 's/,$//'
}

gpu_count() {
    _gpu_enumerate 2>/dev/null | grep -c .
}

# Is any dGPU (secondary GPU beyond iGPU) present?
gpu_hybrid() {
    _c=$(gpu_count)
    [ "${_c:-0}" -ge 2 ] && echo yes || echo no
}

# Find the dGPU BDF (the non-iGPU one, or the second GPU by convention).
# Priority: NVIDIA > AMD (if Intel iGPU is also present).
gpu_dgpu_bdf() {
    _all=$(_gpu_enumerate 2>/dev/null)
    _has_intel=$(printf '%s' "$_all" | awk -F'|' '$2=="8086"' | head -1)
    _amd=$(printf '%s' "$_all" | awk -F'|' '$2=="1002"' | head -1)
    _nvidia=$(printf '%s' "$_all" | awk -F'|' '$2=="10de"' | head -1)
    if [ -n "$_has_intel" ]; then
        [ -n "$_nvidia" ] && { printf '%s' "$_nvidia" | cut -d'|' -f1; return 0; }
        [ -n "$_amd" ]    && { printf '%s' "$_amd" | cut -d'|' -f1; return 0; }
    fi
    return 1
}

# Is the dGPU currently bound to a driver?
gpu_dgpu_bound() {
    _bdf=$(gpu_dgpu_bdf) || return 1
    _drv_link="$(_sysfile /sys/bus/pci/devices/$_bdf/driver)"
    [ -L "$_drv_link" ] && return 0
    return 1
}

# Which driver is bound? (returns "none" if unbound)
gpu_dgpu_driver() {
    _bdf=$(gpu_dgpu_bdf) || { echo none; return 1; }
    _drv_link="$(_sysfile /sys/bus/pci/devices/$_bdf/driver)"
    if [ -L "$_drv_link" ]; then
        basename "$(readlink -f "$_drv_link" 2>/dev/null)"
    else
        echo none
    fi
}

# Which render nodes exist and to which driver are they bound?
gpu_render_nodes() {
    _dridir="$(_sysfile /sys/class/drm)"
    [ -d "$_dridir" ] || return 1
    for _rn in "$_dridir"/renderD*; do
        [ -L "$_rn" ] || [ -d "$_rn" ] || continue
        _name=$(basename "$_rn")
        _drv_link="$_rn/device/driver"
        _drv=none
        [ -L "$_drv_link" ] && _drv=$(basename "$(readlink -f "$_drv_link" 2>/dev/null)")
        printf '%s|%s\n' "$_name" "$_drv"
    done
}

# Count active users of the dGPU render node (safety check before unload)
gpu_dgpu_users() {
    _bdf=$(gpu_dgpu_bdf) || { echo 0; return 1; }
    # Find the render node bound to this BDF
    _dridir="$(_sysfile /sys/class/drm)"
    [ -d "$_dridir" ] || { echo 0; return 1; }
    _node=""
    for _rn in "$_dridir"/renderD*; do
        _dev_link="$_rn/device"
        [ -L "$_dev_link" ] || continue
        _target=$(readlink -f "$_dev_link" 2>/dev/null)
        case "$_target" in
            */"$_bdf") _node=$(basename "$_rn"); break ;;
        esac
    done
    [ -z "$_node" ] && { echo 0; return 0; }
    # Live mode only: fuser check (fixture mode returns 0)
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        echo 0
    else
        _n=$(fuser "/dev/dri/$_node" 2>/dev/null | wc -w)
        echo "${_n:-0}"
    fi
}
