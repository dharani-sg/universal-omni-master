#!/bin/sh
# diag/interface.sh — load all diag dependencies.

[ -n "${_OMNI_ROOT:-}" ] || { echo "[omni] FATAL: _OMNI_ROOT not set" >&2; return 1; }

. "$_OMNI_ROOT/src/core/logging.sh"
. "$_OMNI_ROOT/src/core/utils.sh"
. "$_OMNI_ROOT/src/core/priv.sh"
. "$_OMNI_ROOT/src/core/detect.sh"
. "$_OMNI_ROOT/src/core/detect_hw.sh"

. "$_OMNI_ROOT/src/init/interface.sh"    2>/dev/null || log_warn "init interface unavailable"
. "$_OMNI_ROOT/src/boot/interface.sh"    2>/dev/null || log_warn "boot interface unavailable"
. "$_OMNI_ROOT/src/gpu/interface.sh"     2>/dev/null || log_warn "gpu interface unavailable"
. "$_OMNI_ROOT/src/storage/interface.sh" 2>/dev/null || log_warn "storage interface unavailable"

. "$_OMNI_ROOT/src/diag/common.sh"
. "$_OMNI_ROOT/src/diag/platform.sh"
. "$_OMNI_ROOT/src/diag/services.sh"
. "$_OMNI_ROOT/src/diag/gpu.sh"
. "$_OMNI_ROOT/src/diag/storage.sh"
. "$_OMNI_ROOT/src/diag/boot.sh"
. "$_OMNI_ROOT/src/diag/network.sh"
. "$_OMNI_ROOT/src/diag/session.sh"
. "$_OMNI_ROOT/src/diag/power.sh"
. "$_OMNI_ROOT/src/diag/overall.sh"
