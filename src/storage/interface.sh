#!/bin/sh
# storage/interface.sh — loads all storage modules (additive, not exclusive).

[ -n "${_OMNI_ROOT:-}" ] || { echo "[omni] FATAL: _OMNI_ROOT not set" >&2; return 1; }

. "$_OMNI_ROOT/src/storage/common.sh"     || { echo "[omni] FATAL: common.sh"     >&2; return 1; }
. "$_OMNI_ROOT/src/storage/smart.sh"      || { echo "[omni] FATAL: smart.sh"      >&2; return 1; }
. "$_OMNI_ROOT/src/storage/cablewatch.sh" || { echo "[omni] FATAL: cablewatch.sh" >&2; return 1; }
. "$_OMNI_ROOT/src/storage/btrfs.sh"      || { echo "[omni] FATAL: btrfs.sh"      >&2; return 1; }

log_debug "storage interface loaded"
