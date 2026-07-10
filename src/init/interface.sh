#!/bin/sh
# interface.sh — dispatcher. Loads common guards then the correct backend.
# Caller MUST set _OMNI_ROOT before sourcing this file.

[ -n "${_OMNI_ROOT:-}" ] || { echo "[omni] FATAL: _OMNI_ROOT not set" >&2; return 1; }

command -v detect_init >/dev/null 2>&1 || \
    . "$_OMNI_ROOT/src/core/detect.sh" || { echo "[omni] FATAL: detect.sh load failed" >&2; return 1; }

# Common guards MUST be loaded before any backend.
. "$_OMNI_ROOT/src/init/common.sh" || { echo "[omni] FATAL: common.sh load failed" >&2; return 1; }

_OMNI_INIT="${OMNI_INIT_OVERRIDE:-$(detect_init)}"
log_debug "service interface: backend=$_OMNI_INIT"

case "$_OMNI_INIT" in
    systemd) . "$_OMNI_ROOT/src/init/systemd.sh" ;;
    openrc)  . "$_OMNI_ROOT/src/init/openrc.sh"  ;;
    runit)   . "$_OMNI_ROOT/src/init/runit.sh"   ;;
    dinit)   . "$_OMNI_ROOT/src/init/dinit.sh"   ;;
    s6)      . "$_OMNI_ROOT/src/init/s6.sh"      ;;
    *)  log_error "no service backend for init system '$_OMNI_INIT'"; return 1 ;;
esac
