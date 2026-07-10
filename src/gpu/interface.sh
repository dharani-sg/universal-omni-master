#!/bin/sh
# gpu/interface.sh — loads common.sh + vendor backends. Consistent dGPU definition.

[ -n "${_OMNI_ROOT:-}" ] || { echo "[omni] FATAL: _OMNI_ROOT not set" >&2; return 1; }

. "$_OMNI_ROOT/src/gpu/common.sh" || { echo "[omni] FATAL: gpu/common.sh failed" >&2; return 1; }
. "$_OMNI_ROOT/src/gpu/intel.sh"  2>/dev/null || true

# dGPU vendor is derived from gpu_dgpu_bdf() — the SINGLE source of truth.
# gpu_dgpu_bdf() returns non-empty ONLY for a true discrete-secondary GPU
# (i.e. an Intel iGPU coexisting with an AMD/NVIDIA card). A single-GPU
# system (e.g. NVIDIA-only workstation) has no discrete secondary => none.
_dgpu_bdf=$(gpu_dgpu_bdf 2>/dev/null || true)
_OMNI_DGPU=none
if [ -n "$_dgpu_bdf" ]; then
    _dgpu_vid=$(_gpu_enumerate 2>/dev/null | awk -F'|' -v b="$_dgpu_bdf" '$1==b {print $2; exit}')
    case "$_dgpu_vid" in
        10de) . "$_OMNI_ROOT/src/gpu/nvidia.sh"; _OMNI_DGPU=nvidia ;;
        1002) . "$_OMNI_ROOT/src/gpu/amd.sh";    _OMNI_DGPU=amd ;;
    esac
fi

# Wrapper functions (robust; POSIX aliases are unreliable when sourced).
gpu_dgpu_load() {
    case "$_OMNI_DGPU" in
        nvidia) gpu_nvidia_load "$@" ;;
        amd)    gpu_amd_load "$@" ;;
        *)      log_error "no discrete dGPU present to load"; return 1 ;;
    esac
}
gpu_dgpu_unload() {
    case "$_OMNI_DGPU" in
        nvidia) gpu_nvidia_unload "$@" ;;
        amd)    gpu_amd_unload "$@" ;;
        *)      log_error "no discrete dGPU present to unload"; return 1 ;;
    esac
}

log_debug "gpu interface: dgpu-vendor=$_OMNI_DGPU (bdf=${_dgpu_bdf:-none})"
