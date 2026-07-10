#!/bin/sh
# test-gpu.sh — GPU abstraction fixture matrix.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/bin/omni-gpu"
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

echo "=== Universal Omni-Master GPU Matrix ==="

# Alpine (Intel + AMD unbound)
r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" count 2>/dev/null)
check_eq "alpine gpu-count" "2" "$r"
r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" vendors 2>/dev/null)
check_eq "alpine gpu-vendors" "AMD,Intel" "$r"
r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" hybrid 2>/dev/null)
check_eq "alpine gpu-hybrid" "yes" "$r"
r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" dgpu-vendor 2>/dev/null)
check_eq "alpine dgpu-vendor" "amd" "$r"
r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" dgpu-bdf 2>/dev/null)
check_eq "alpine dgpu-bdf" "0000:01:00.0" "$r"
r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" dgpu-bound 2>/dev/null)
check_eq "alpine dgpu-bound (unbound)" "no" "$r"
r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" intel-status 2>/dev/null)
check_eq "alpine intel-status" "active" "$r"

# Void (same as Alpine)
r=$(OMNI_SYSROOT="$FX/void" OMNI_LOG_LEVEL=error "$CLI" hybrid 2>/dev/null)
check_eq "void gpu-hybrid" "yes" "$r"
r=$(OMNI_SYSROOT="$FX/void" OMNI_LOG_LEVEL=error "$CLI" dgpu-vendor 2>/dev/null)
check_eq "void dgpu-vendor" "amd" "$r"

# Arch (NVIDIA-only, bound)
r=$(OMNI_SYSROOT="$FX/arch" OMNI_LOG_LEVEL=error "$CLI" count 2>/dev/null)
check_eq "arch gpu-count" "1" "$r"
r=$(OMNI_SYSROOT="$FX/arch" OMNI_LOG_LEVEL=error "$CLI" vendors 2>/dev/null)
check_eq "arch gpu-vendors" "NVIDIA" "$r"
r=$(OMNI_SYSROOT="$FX/arch" OMNI_LOG_LEVEL=error "$CLI" hybrid 2>/dev/null)
check_eq "arch gpu-hybrid (single)" "no" "$r"
r=$(OMNI_SYSROOT="$FX/arch" OMNI_LOG_LEVEL=error "$CLI" dgpu-vendor 2>/dev/null)
check_eq "arch dgpu-vendor (no iGPU)" "none" "$r"

# Debian (Intel + NVIDIA hybrid, bound)
r=$(OMNI_SYSROOT="$FX/debian" OMNI_LOG_LEVEL=error "$CLI" vendors 2>/dev/null)
check_eq "debian gpu-vendors" "Intel,NVIDIA" "$r"
r=$(OMNI_SYSROOT="$FX/debian" OMNI_LOG_LEVEL=error "$CLI" dgpu-vendor 2>/dev/null)
check_eq "debian dgpu-vendor" "nvidia" "$r"
r=$(OMNI_SYSROOT="$FX/debian" OMNI_LOG_LEVEL=error "$CLI" dgpu-bdf 2>/dev/null)
check_eq "debian dgpu-bdf" "0000:01:00.0" "$r"
r=$(OMNI_SYSROOT="$FX/debian" OMNI_LOG_LEVEL=error "$CLI" dgpu-bound 2>/dev/null)
check_eq "debian dgpu-bound" "yes" "$r"
r=$(OMNI_SYSROOT="$FX/debian" OMNI_LOG_LEVEL=error "$CLI" dgpu-driver 2>/dev/null)
check_eq "debian dgpu-driver" "nvidia" "$r"

# BusyBox-min (no GPUs)
r=$(OMNI_SYSROOT="$FX/busybox-min" OMNI_LOG_LEVEL=error "$CLI" count 2>/dev/null)
check_eq "busybox-min gpu-count" "0" "$r"
r=$(OMNI_SYSROOT="$FX/busybox-min" OMNI_LOG_LEVEL=error "$CLI" hybrid 2>/dev/null)
check_eq "busybox-min gpu-hybrid" "no" "$r"

# Mutation guard
_rc=0
OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" load >/dev/null 2>&1 || _rc=$?
check_eq "alpine gpu load guard" "126" "$_rc"
_rc=0
OMNI_SYSROOT="$FX/debian" OMNI_LOG_LEVEL=error "$CLI" unload >/dev/null 2>&1 || _rc=$?
check_eq "debian gpu unload guard" "126" "$_rc"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
