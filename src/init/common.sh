#!/bin/sh
# common.sh — shared guards for all init backends.
# ALL mutation functions MUST call _svc_guard_mutation before touching the system.

# Abort any mutating action when OMNI_SYSROOT is set.
# This is a non-negotiable safety boundary between fixture testing and real mutation.
_svc_guard_mutation() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        log_error "REFUSING mutation of '$1': OMNI_SYSROOT is set (fixture/read-only mode)."
        return 126
    fi
    return 0
}

# Check whether any of the given sysroot-prefixed paths exist.
_svc_exists_any() {
    for _p in "$@"; do
        _have "$_p" && return 0
    done
    return 1
}
