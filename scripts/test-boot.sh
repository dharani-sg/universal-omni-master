#!/bin/sh
# test-boot.sh — bootloader abstraction fixture matrix.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/bin/omni-boot"
FX="$ROOT/sandbox/fixtures"
PASS=0; FAIL=0

check_eq() {
    _label="$1"; _want="$2"; _got="$3"
    if [ "$_got" = "$_want" ]; then
        printf '  \033[0;32mPASS\033[0m %-40s = %s\n' "$_label" "$_got"; PASS=$((PASS+1))
    else
        printf '  \033[1;31mFAIL\033[0m %-40s want=%s got=%s\n' "$_label" "$_want" "$_got"; FAIL=$((FAIL+1))
    fi
}

echo "=== Universal Omni-Master Bootloader Matrix ==="

# --- GRUB / Alpine ---
r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" detect 2>/dev/null)
check_eq "alpine boot-detect" "grub" "$r"
r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" default 2>/dev/null)
check_eq "alpine grub-default" "alpine-top" "$r"
r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" count 2>/dev/null)
check_eq "alpine grub-entry-count" "2" "$r"
r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" verify alpine-top 2>/dev/null)
check_eq "alpine grub-verify alpine-top" "valid" "$r"
r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" verify ghost-entry 2>/dev/null)
check_eq "alpine grub-verify ghost" "not_found" "$r"

# --- GRUB / Void ---
r=$(OMNI_SYSROOT="$FX/void" OMNI_LOG_LEVEL=error "$CLI" detect 2>/dev/null)
check_eq "void boot-detect" "grub" "$r"

# --- systemd-boot / Arch ---
r=$(OMNI_SYSROOT="$FX/arch" OMNI_LOG_LEVEL=error "$CLI" detect 2>/dev/null)
check_eq "arch boot-detect" "systemd-boot" "$r"
r=$(OMNI_SYSROOT="$FX/arch" OMNI_LOG_LEVEL=error "$CLI" default 2>/dev/null)
check_eq "arch sd-boot-default" "arch.conf" "$r"
r=$(OMNI_SYSROOT="$FX/arch" OMNI_LOG_LEVEL=error "$CLI" count 2>/dev/null)
check_eq "arch sd-boot-entry-count" "2" "$r"
r=$(OMNI_SYSROOT="$FX/arch" OMNI_LOG_LEVEL=error "$CLI" list 2>/dev/null | wc -l | tr -d ' ')
check_eq "arch sd-boot-list-count" "2" "$r"

# --- systemd-boot / Debian ---
r=$(OMNI_SYSROOT="$FX/debian" OMNI_LOG_LEVEL=error "$CLI" detect 2>/dev/null)
check_eq "debian boot-detect" "systemd-boot" "$r"

# --- BusyBox-min: unknown ---
r=$(OMNI_SYSROOT="$FX/busybox-min" OMNI_LOG_LEVEL=error "$CLI" detect 2>/dev/null)
check_eq "busybox-min boot-detect" "unknown" "$r"

# --- Mutation guard ---
_rc=0
OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" regenerate >/dev/null 2>&1 || _rc=$?
check_eq "grub mutation-guard" "126" "$_rc"

_rc=0
OMNI_SYSROOT="$FX/arch" OMNI_LOG_LEVEL=error "$CLI" regenerate >/dev/null 2>&1 || _rc=$?
check_eq "systemd-boot mutation-guard" "126" "$_rc"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
