#!/bin/sh
# diag/interface.sh — load all subsystems needed for audit (read-only).

[ -n "${_OMNI_ROOT:-}" ] || { echo "[omni] FATAL: _OMNI_ROOT not set" >&2; return 1; }

. "$_OMNI_ROOT/src/core/logging.sh"
. "$_OMNI_ROOT/src/core/utils.sh"
. "$_OMNI_ROOT/src/core/priv.sh"
. "$_OMNI_ROOT/src/core/detect.sh"
. "$_OMNI_ROOT/src/core/detect_hw.sh"

# Init (status only — no mutation)
. "$_OMNI_ROOT/src/init/interface.sh" 2>/dev/null || log_warn "init interface not available"

# Boot (detect/list only)
. "$_OMNI_ROOT/src/boot/interface.sh" 2>/dev/null || log_warn "boot interface not available"

# GPU (status only)
. "$_OMNI_ROOT/src/gpu/interface.sh" 2>/dev/null || log_warn "gpu interface not available"

# Storage (health/mode only)
. "$_OMNI_ROOT/src/storage/interface.sh" 2>/dev/null || log_warn "storage interface not available"

. "$_OMNI_ROOT/src/diag/common.sh"
. "$_OMNI_ROOT/src/diag/checks.sh"

log_debug "diag interface loaded"
