#!/bin/sh
# test-audit.sh — omni-audit fixture matrix for M6.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/bin/omni-audit"
FX="$ROOT/sandbox/fixtures"
STOR="$ROOT/bin/omni-storage"
PASS=0; FAIL=0

check() {
    label="$1"; want="$2"; got="$3"
    if [ "$want" = "$got" ]; then
        printf '  \033[0;32mPASS\033[0m %-42s = %s\n' "$label" "$got"
        PASS=$((PASS+1))
    else
        printf '  \033[1;31mFAIL\033[0m %-42s want=%s got=%s\n' "$label" "$want" "$got"
        FAIL=$((FAIL+1))
    fi
}

echo "=== M6 Audit Matrix ==="

# ── Alpine: ext4 root, healthy SATA ──
rc=0
OMNI_SYSROOT="$FX/alpine" OMNI_AUDIT_PRIME=0 OMNI_LOG_LEVEL=error "$CLI" > /tmp/audit-alpine.txt 2>/dev/null || rc=$?
[ "$rc" -le 1 ] && check "alpine audit noncritical (rc<=1)" "yes" "yes" || check "alpine audit noncritical (rc<=1)" "yes" "no(rc=$rc)"
grep -q "fsck policy: never_disabled" /tmp/audit-alpine.txt \
    && check "alpine fsck invariant in output" "yes" "yes" \
    || check "alpine fsck invariant in output" "yes" "no"
grep -q "root filesystem: ext4" /tmp/audit-alpine.txt \
    && check "alpine root filesystem=ext4" "yes" "yes" \
    || check "alpine root filesystem=ext4" "yes" "no"
grep -q "Btrfs checks skipped" /tmp/audit-alpine.txt \
    && check "alpine Btrfs correctly skipped (not Btrfs root)" "yes" "yes" \
    || check "alpine Btrfs correctly skipped (not Btrfs root)" "yes" "no"

# ── Void: Btrfs root, degraded SATA ──
rc=0
OMNI_SYSROOT="$FX/void" OMNI_AUDIT_PRIME=0 OMNI_LOG_LEVEL=error "$CLI" > /tmp/audit-void.txt 2>/dev/null || rc=$?
grep -q "cable_watch\|degraded" /tmp/audit-void.txt \
    && check "void degraded SATA detected" "yes" "yes" \
    || check "void degraded SATA detected" "yes" "no"
[ "$rc" -ge 1 ] && check "void audit nonzero exit (warn or worse)" "yes" "yes" || check "void audit nonzero exit" "yes" "no"
grep -q "root filesystem: btrfs" /tmp/audit-void.txt \
    && check "void root filesystem=btrfs" "yes" "yes" \
    || check "void root filesystem=btrfs" "yes" "no"

# ── BusyBox-min: no-Btrfs, no-smartctl — must not crash ──
rc=0
OMNI_SYSROOT="$FX/busybox-min" OMNI_AUDIT_PRIME=0 OMNI_LOG_LEVEL=error "$CLI" > /tmp/audit-busybox.txt 2>/dev/null || rc=$?
[ "$rc" -le 1 ] && check "busybox audit completes noncritical" "yes" "yes" || check "busybox audit completes noncritical" "yes" "no(rc=$rc)"

# ── JSON mode ──
OMNI_SYSROOT="$FX/alpine" OMNI_AUDIT_FORMAT=json OMNI_AUDIT_PRIME=0 OMNI_LOG_LEVEL=error "$CLI" > /tmp/audit-alpine.json 2>/dev/null || true
grep -q '"findings"' /tmp/audit-alpine.json \
    && check "json mode produces findings array" "yes" "yes" \
    || check "json mode produces findings array" "yes" "no"

# ── Filesystem detection ──
r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$STOR" fs-type / 2>/dev/null)
check "alpine fs-type / = ext4" "ext4" "$r"
r=$(OMNI_SYSROOT="$FX/void" OMNI_LOG_LEVEL=error "$STOR" fs-type / 2>/dev/null)
check "void fs-type / = btrfs" "btrfs" "$r"
r=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$STOR" fs-preference 2>/dev/null)
check "alpine fs-preference default = auto" "auto" "$r"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
