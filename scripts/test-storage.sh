#!/bin/sh
# test-storage.sh — storage telemetry fixture matrix.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/bin/omni-storage"
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

echo "=== Universal Omni-Master Storage Matrix ==="

# --- Alpine: SATA at baseline (HP Pavilion reference: CRC=5360=baseline) ---
r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" crc sda 2>/dev/null)
check_eq "alpine sda CRC reading" "5360" "$r"
r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" baseline sda 2>/dev/null)
check_eq "alpine sda baseline" "5360" "$r"
r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" health sda 2>/dev/null)
check_eq "alpine sda health (at baseline = ok)" "ok" "$r"

# --- Void: SATA with NEW delta (5410 > baseline 5360) -> degraded ---
r=$(OMNI_SYSROOT="$FX/void" OMNI_LOG_LEVEL=error "$CLI" health sda 2>/dev/null)
check_eq "void sda health (delta+50 = degraded)" "degraded" "$r"
r=$(OMNI_SYSROOT="$FX/void" OMNI_LOG_LEVEL=error "$CLI" mode sda 2>/dev/null)
check_eq "void cable-watch mode triggered" "cable_watch" "$r"

# --- Arch: NVMe healthy ---
r=$(OMNI_SYSROOT="$FX/arch" OMNI_LOG_LEVEL=error "$CLI" health nvme0n1 2>/dev/null)
check_eq "arch nvme health (0 errors = ok)" "ok" "$r"

# --- Debian: NVMe degraded ---
r=$(OMNI_SYSROOT="$FX/debian" OMNI_LOG_LEVEL=error "$CLI" health nvme0n1 2>/dev/null)
check_eq "debian nvme health (3 errors = degraded)" "degraded" "$r"
r=$(OMNI_SYSROOT="$FX/debian" OMNI_LOG_LEVEL=error "$CLI" luks sda2 2>/dev/null)
check_eq "debian sda2 LUKS detection" "yes" "$r"
r=$(OMNI_SYSROOT="$FX/debian" OMNI_LOG_LEVEL=error "$CLI" luks sda1 2>/dev/null)
check_eq "debian sda1 not LUKS" "no" "$r"

# --- BusyBox-min: unreadable SMART data ---
r=$(OMNI_SYSROOT="$FX/busybox-min" OMNI_LOG_LEVEL=error "$CLI" crc sda 2>/dev/null)
check_eq "busybox-min unreadable CRC" "" "$r"
r=$(OMNI_SYSROOT="$FX/busybox-min" OMNI_LOG_LEVEL=error "$CLI" health sda 2>/dev/null)
check_eq "busybox-min health unknown" "unknown" "$r"

# --- Btrfs (Void, matches real HP Pavilion subvolume layout) ---
r=$(OMNI_SYSROOT="$FX/void" OMNI_LOG_LEVEL=error "$CLI" btrfs-count / 2>/dev/null)
check_eq "void btrfs subvolume count" "5" "$r"
r=$(OMNI_SYSROOT="$FX/void" OMNI_LOG_LEVEL=error "$CLI" btrfs-subvols / 2>/dev/null | grep -c '^@')
check_eq "void btrfs @-prefixed subvols" "5" "$r"
r=$(OMNI_SYSROOT="$FX/void" OMNI_LOG_LEVEL=error "$CLI" btrfs-free / 2>/dev/null)
check_eq "void btrfs unallocated bytes" "37580000000" "$r"

# --- Cable-watch safety invariant: fsck NEVER disabled ---
r=$("$CLI" fsck-policy 2>/dev/null)
check_eq "fsck policy invariant" "never_disabled" "$r"

# --- Mutation guard ---
_rc=0
OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" set-baseline sda >/dev/null 2>&1 || _rc=$?
check_eq "set-baseline mutation guard" "126" "$_rc"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
