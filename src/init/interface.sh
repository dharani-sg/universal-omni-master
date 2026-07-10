#!/bin/sh
# interface.sh — dispatcher that loads the correct backend.
# MUST be sourced AFTER logging.sh, utils.sh, priv.sh, detect.sh are sourced.
# Caller MUST have set _OMNI_ROOT to the project root directory.

# Validate prerequisites
if [ -z "${_OMNI_ROOT:-}" ]; then
    echo "[omni] FATAL: _OMNI_ROOT not set before sourcing interface.sh" >&2
    return 1
fi

if ! command -v detect_init >/dev/null 2>&1; then
    . "$_OMNI_ROOT/src/core/detect.sh" || { echo "[omni] FATAL: cannot load detect.sh" >&2; return 1; }
fi

_OMNI_INIT="${OMNI_INIT_OVERRIDE:-$(detect_init)}"
log_debug "service interface: backend=$_OMNI_INIT"

case "$_OMNI_INIT" in
    systemd) . "$_OMNI_ROOT/src/init/systemd.sh" ;;
    openrc)  . "$_OMNI_ROOT/src/init/openrc.sh"  ;;
    runit)   . "$_OMNI_ROOT/src/init/runit.sh"   ;;
    dinit)   . "$_OMNI_ROOT/src/init/dinit.sh"   ;;
    s6)      . "$_OMNI_ROOT/src/init/s6.sh"      ;;
    *)
        log_error "service interface: no backend for init system '$_OMNI_INIT'"
        return 1
        ;;
esac
