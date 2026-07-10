#!/bin/sh
# boot/interface.sh — loads common.sh then the correct backend.
# Caller MUST set _OMNI_ROOT before sourcing this file.

[ -n "${_OMNI_ROOT:-}" ] || { echo "[omni] FATAL: _OMNI_ROOT not set" >&2; return 1; }

. "$_OMNI_ROOT/src/boot/common.sh" || { echo "[omni] FATAL: boot/common.sh failed" >&2; return 1; }

_OMNI_BOOT="${OMNI_BOOT_OVERRIDE:-$(boot_detect)}"
log_debug "boot interface: backend=$_OMNI_BOOT"

case "$_OMNI_BOOT" in
    grub)         . "$_OMNI_ROOT/src/boot/grub.sh" ;;
    systemd-boot) . "$_OMNI_ROOT/src/boot/systemd_boot.sh" ;;
    *)            log_warn "no boot backend for '$_OMNI_BOOT'; read-only detection only" ;;
esac
