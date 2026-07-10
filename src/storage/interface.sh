#!/bin/sh
# storage/interface.sh — loads all storage modules (no vendor branching needed;
# unlike GPU, storage backends are additive, not mutually exclusive).

[ -n "${_OMNI_ROOT:-}" ] || { echo "[omni] FATAL: _OMNI_ROOT not set" >&2; return 1; }

. "$_OMNI_ROOT/src/storage/common.sh"    || { echo "[omni] FATAL: storage/common.sh failed" >&2; return 1; }
. "$_OMNI_ROOT/src/storage/smart.sh"     || { echo "[omni] FATAL: storage/smart.sh failed" >&2; return 1; }
. "$_OMNI_ROOT/src/storage/cablewatch.sh" || { echo "[omni] FATAL: storage/cablewatch.sh failed" >&2; return 1; }
. "$_OMNI_ROOT/src/storage/btrfs.sh"     || { echo "[omni] FATAL: storage/btrfs.sh failed" >&2; return 1; }

log_debug "storage interface loaded"
