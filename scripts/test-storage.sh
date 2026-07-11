#!/bin/sh
# test-storage.sh — M5 storage telemetry fixture matrix.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/bin/omni-storage"
FX="$ROOT/sandbox/fixtures"
PASS=0; FAIL=0

check_eq() {
    _label="$1"; _want="$2"; _got="$3"
    if [ "$_got" = "$_want" ]; then
        printf '  \033[0;32mPASS\033[0m %-45s = %s\n' "$_label" "$_got"; PASS=$((PASS+1))
    else
        printf '  \033[1;31mFAIL\033[0m %-45s want=%s got=%s\n' "$_label" "$_want" "$_got"; FAIL=$((FAIL+1))
    fi
}

echo "=== Universal Omni-Master Storage Matrix ==="
echo "──── SATA baseline-relative model (Alpine reference) ────"

r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" crc sda)
check_eq "alpine sda CRC value"                    "5360" "$r"

r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" baseline sda)
check_eq "alpine sda baseline stored"              "5360" "$r"

r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" health sda)
check_eq "alpine sda health (CRC at baseline)"     "ok"   "$r"

r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" attr sda 187)
check_eq "alpine sda attr187 (uncorrectable=0)"    "0"    "$r"

r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" attr sda 197)
check_eq "alpine sda attr197 (pending=0)"          "0"    "$r"

r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" attr sda 198)
check_eq "alpine sda attr198 (offline=0)"          "0"    "$r"

r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" mode sda)
check_eq "alpine mode at baseline"                 "normal" "$r"

echo; echo "──── SATA CRC delta degradation (Void) ────"

r=$(OMNI_SYSROOT="$FX/void" OMNI_LOG_LEVEL=error "$CLI" health sda)
check_eq "void sda health (CRC delta+50)"          "degraded" "$r"

r=$(OMNI_SYSROOT="$FX/void" OMNI_LOG_LEVEL=error "$CLI" mode sda)
check_eq "void cable-watch triggered"              "cable_watch" "$r"

echo; echo "──── SATA zero-tolerance: pending sectors (busybox-min) ────"

r=$(OMNI_SYSROOT="$FX/busybox-min" OMNI_LOG_LEVEL=error "$CLI" type sda)
check_eq "busybox-min sda type"                    "ssd" "$r"

r=$(OMNI_SYSROOT="$FX/busybox-min" OMNI_LOG_LEVEL=error "$CLI" attr sda 197)
check_eq "busybox-min attr197 (pending=5)"         "5" "$r"

r=$(OMNI_SYSROOT="$FX/busybox-min" OMNI_LOG_LEVEL=error "$CLI" health sda)
check_eq "busybox-min health (pending sectors→degraded)" "degraded" "$r"

echo; echo "──── NVMe healthy (Arch) ────"

r=$(OMNI_SYSROOT="$FX/arch" OMNI_LOG_LEVEL=error "$CLI" nvme-cw nvme0n1)
check_eq "arch nvme0n1 critical_warning raw"       "0x00" "$r"

r=$(OMNI_SYSROOT="$FX/arch" OMNI_LOG_LEVEL=error "$CLI" nvme-cw-sev nvme0n1)
check_eq "arch nvme0n1 cw severity"                "ok" "$r"

r=$(OMNI_SYSROOT="$FX/arch" OMNI_LOG_LEVEL=error "$CLI" health nvme0n1)
check_eq "arch nvme0n1 health (0 errors)"          "ok" "$r"

echo; echo "──── NVMe critical_warning bit2 (Arch nvme1n1) ────"

r=$(OMNI_SYSROOT="$FX/arch" OMNI_LOG_LEVEL=error "$CLI" nvme-cw nvme1n1)
check_eq "arch nvme1n1 critical_warning 0x04"      "0x04" "$r"

r=$(OMNI_SYSROOT="$FX/arch" OMNI_LOG_LEVEL=error "$CLI" nvme-cw-sev nvme1n1)
check_eq "arch nvme1n1 cw severity (bit2=critical)" "critical" "$r"

r=$(OMNI_SYSROOT="$FX/arch" OMNI_LOG_LEVEL=error "$CLI" health nvme1n1)
check_eq "arch nvme1n1 health (reliability degraded)" "critical" "$r"

echo; echo "──── NVMe media errors (Debian) ────"

r=$(OMNI_SYSROOT="$FX/debian" OMNI_LOG_LEVEL=error "$CLI" health nvme0n1)
check_eq "debian nvme0n1 health (media_errors=3)"  "degraded" "$r"

echo; echo "──── LUKS detection (Debian) ────"

r=$(OMNI_SYSROOT="$FX/debian" OMNI_LOG_LEVEL=error "$CLI" luks sda2)
check_eq "debian sda2 LUKS yes"                    "yes" "$r"

r=$(OMNI_SYSROOT="$FX/debian" OMNI_LOG_LEVEL=error "$CLI" luks sda1)
check_eq "debian sda1 not LUKS"                    "no"  "$r"

echo; echo "──── Btrfs subvolumes + headroom (Void) ────"

r=$(OMNI_SYSROOT="$FX/void" OMNI_LOG_LEVEL=error "$CLI" btrfs-count /)
check_eq "void btrfs subvolume count"              "5" "$r"

r=$(OMNI_SYSROOT="$FX/void" OMNI_LOG_LEVEL=error "$CLI" btrfs-subvols / | grep -c '^@')
check_eq "void btrfs @-prefixed subvols"           "5" "$r"

r=$(OMNI_SYSROOT="$FX/void" OMNI_LOG_LEVEL=error "$CLI" btrfs-free /)
check_eq "void btrfs unallocated bytes"            "37580000000" "$r"

echo; echo "──── Btrfs device stats (Void clean) ────"

r=$(OMNI_SYSROOT="$FX/void" OMNI_LOG_LEVEL=error "$CLI" btrfs-device-health /)
check_eq "void btrfs device health (all zero)"     "ok" "$r"

echo; echo "──── Safety invariants ────"

r=$("$CLI" fsck-policy)
check_eq "fsck policy invariant"                   "never_disabled" "$r"

_rc=0
OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" set-baseline sda >/dev/null 2>&1 || _rc=$?
check_eq "set-baseline mutation guard (exit 126)"  "126" "$_rc"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
