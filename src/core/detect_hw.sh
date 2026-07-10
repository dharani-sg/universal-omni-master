#!/bin/sh
# detect_hw.sh — CPU / GPU / storage / power. SYSROOT for /proc,/sys; env overrides for tools.

detect_cpu_vendor() {
    _ci="$(_sysfile /proc/cpuinfo)"
    [ -r "$_ci" ] || { echo unknown; return; }
    grep -m1 -E '^vendor_id' "$_ci" | cut -d: -f2 | sed 's/^ *//' || echo unknown
}
detect_cpu_model() {
    _ci="$(_sysfile /proc/cpuinfo)"
    [ -r "$_ci" ] || { echo unknown; return; }
    _m=$(grep -m1 -E '^model name' "$_ci" | cut -d: -f2 | sed 's/^ *//')
    [ -z "$_m" ] && _m=$(grep -m1 -E '^Model' "$_ci" | cut -d: -f2 | sed 's/^ *//')
    printf '%s' "${_m:-unknown}"
}
detect_cpu_count() {
    _ci="$(_sysfile /proc/cpuinfo)"
    [ -r "$_ci" ] && grep -c -E '^processor' "$_ci" || echo 0
}
detect_cpu_hybrid() {
    _base="$(_sysfile /sys/devices/system/cpu)"
    _freqs=""
    for _f in "$_base"/cpu*/cpufreq/cpuinfo_max_freq; do
        [ -r "$_f" ] || continue
        _freqs="$_freqs $(cat "$_f" 2>/dev/null)"
    done
    [ -z "$_freqs" ] && { echo no; return; }
    _u=$(printf '%s\n' $_freqs | sort -u | grep -c .)
    [ "$_u" -gt 1 ] && echo yes || echo no
}

# GPU: prefer OMNI_LSPCI fixture file; else live `lspci -knn`.
_gpu_raw() {
    if [ -n "${OMNI_LSPCI:-}" ] && [ -r "$OMNI_LSPCI" ]; then
        cat "$OMNI_LSPCI"
    elif [ -z "$OMNI_SYSROOT" ] && command -v lspci >/dev/null 2>&1; then
        lspci -nn 2>/dev/null
    fi
}
detect_gpu_count() {
    _gpu_raw | grep -E 'VGA compatible controller|3D controller|Display controller' | grep -c . 
}
detect_gpu_vendors() {
    # Extract PCI vendor IDs [XXXX:YYYY] and map to canonical names.
    # More reliable than parsing the free-text vendor string.
    _gpu_raw | grep -E 'VGA compatible controller|3D controller|Display controller' \
        | grep -oE '\[[0-9a-fA-F]{4}:' | sed 's/\[//; s/://' | sort -u | while read _vid; do
            case "$_vid" in
                8086) printf 'Intel\n' ;;
                1002) printf 'AMD\n' ;;
                10de) printf 'NVIDIA\n' ;;
                *)    printf 'Unknown(%s)\n' "$_vid" ;;
            esac
        done | sort -u | tr '\n' ',' | sed 's/,$//'
}
detect_gpu_hybrid() {
    _n=$(detect_gpu_count)
    [ "${_n:-0}" -ge 2 ] && echo yes || echo no
}

# Storage: rotational flag per block device (sysroot-aware).
detect_storage_types() {
    _base="$(_sysfile /sys/block)"
    _out=""
    [ -d "$_base" ] || { echo unknown; return; }
    for _d in "$_base"/*; do
        [ -d "$_d" ] || continue
        _n=$(basename "$_d")
        case "$_n" in loop*|ram*|zram*|sr*) continue ;; esac
        _rot="?"
        [ -r "$_d/queue/rotational" ] && _rot=$(cat "$_d/queue/rotational")
        case "$_n" in
            nvme*) _t=nvme ;;
            *)     [ "$_rot" = "0" ] && _t=ssd || _t=hdd ;;
        esac
        _out="$_out$_n:$_t "
    done
    printf '%s' "$(echo "$_out" | sed 's/ *$//')"
    [ -z "$_out" ] && printf 'unknown'
}

detect_power_source() {
    _base="$(_sysfile /sys/class/power_supply)"
    [ -d "$_base" ] || { echo unknown; return; }
    for _p in "$_base"/*/online; do
        [ -r "$_p" ] || continue
        [ "$(cat "$_p")" = "1" ] && { echo ac; return; }
    done
    # If a battery exists but no AC online -> battery; else ac (desktop)
    for _b in "$_base"/*/capacity; do
        [ -r "$_b" ] && { echo battery; return; }
    done
    echo ac
}
