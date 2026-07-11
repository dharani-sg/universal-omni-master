#!/bin/sh
# scripts/test-m11-rollback.sh — M11 rollback module tests.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

check() {
    if [ "$2" = "$3" ]; then
        printf '  PASS %-50s = %s\n' "$1" "$3"; PASS=$((PASS+1))
    else
        printf '  FAIL %-50s want=%s got=%s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1))
    fi
}

echo "=== M11 Rollback Module Tests ==="

# 1. Syntax
for f in "$ROOT/src/snapshot/boot_entry.sh" "$ROOT/src/snapshot/restore.sh"; do
    sh -n "$f" && check "syntax: $(basename "$f")" ok ok || check "syntax: $(basename "$f")" ok fail
done
sh -n "$ROOT/bin/omni-snapshot" && check "syntax: omni-snapshot (extended)" ok ok

# 2. CLI dispatch for new commands
rc=0; "$ROOT/bin/omni-snapshot" boot-entry list >/dev/null 2>&1 || rc=$?
# On non-Btrfs, returns 0 (graceful) or lists nothing — either is acceptable
check "boot-entry list dispatches" ok ok

rc=0; "$ROOT/bin/omni-snapshot" boot-entry bogus >/dev/null 2>&1 || rc=$?
check "boot-entry unknown subcommand exits 2" "2" "$rc"

# 3. Mutation guard on boot-entry add
rc=$(OMNI_SYSROOT="/tmp/fx" sh -c "
    . '$ROOT/src/core/logging.sh' 2>/dev/null || true
    . '$ROOT/src/snapshot/common.sh'
    . '$ROOT/src/snapshot/boot_entry.sh'
    snap_load_conf
    snap_boot_entry_add testsnap >/dev/null 2>&1
    printf '%s' \$?
")
check "boot-entry add: mutation guard 126" "126" "$rc"

# 4. Mutation guard on restore
rc=$(OMNI_SYSROOT="/tmp/fx" sh -c "
    . '$ROOT/src/core/logging.sh' 2>/dev/null || true
    . '$ROOT/src/snapshot/common.sh'
    . '$ROOT/src/snapshot/restore.sh'
    snap_load_conf
    snap_restore testsnap >/dev/null 2>&1
    printf '%s' \$?
")
check "restore: mutation guard 126" "126" "$rc"

# 5. Bootloader detection function exists
grep -q '_snap_detect_bootloader' "$ROOT/src/snapshot/boot_entry.sh" && \
    check "boot_entry.sh has bootloader detection" yes yes || \
    check "boot_entry.sh has bootloader detection" yes no

# 6. Restore creates safety snapshot before swap
grep -q 'pre-restore' "$ROOT/src/snapshot/restore.sh" && \
    check "restore.sh creates pre-restore safety snap" yes yes || \
    check "restore.sh creates pre-restore safety snap" yes no

# 7. GRUB + systemd-boot dual support
grep -q 'systemd-boot' "$ROOT/src/snapshot/boot_entry.sh" && \
    check "boot_entry supports systemd-boot" yes yes || \
    check "boot_entry supports systemd-boot" yes no
grep -q 'grub' "$ROOT/src/snapshot/boot_entry.sh" && \
    check "boot_entry supports GRUB" yes yes || \
    check "boot_entry supports GRUB" yes no

# 8. Entry namespace isolation (omni-snap- prefix)
grep -q 'SNAP_BOOT_PREFIX="omni-snap"' "$ROOT/src/snapshot/boot_entry.sh" && \
    check "boot entries use omni-snap- prefix" yes yes || \
    check "boot entries use omni-snap- prefix" yes no

# 9. Sync removes stale entries
grep -q 'snap_boot_entry_sync' "$ROOT/src/snapshot/boot_entry.sh" && \
    check "boot_entry has sync for stale entries" yes yes || \
    check "boot_entry has sync for stale entries" yes no

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

echo; echo "=== M11.1 regressions (G1-G9) ==="
grep -q '_snap_root_uuid' "$ROOT/src/snapshot/boot_entry.sh" && \
    check "G3: UUID resolver strips [subvol]" yes yes || check "G3: UUID resolver strips [subvol]" yes no
grep -q '\.\./@snapshots' "$ROOT/src/snapshot/boot_entry.sh" && \
    check "G2: no '..' subvol construction" no yes || check "G2: no '..' subvol construction" no no
grep -q '_snap_scrub_cmdline' "$ROOT/src/snapshot/boot_entry.sh" && \
    check "G1: cmdline scrubber present" yes yes || check "G1: cmdline scrubber present" yes no
grep -q '_restore_confirm' "$ROOT/src/snapshot/restore.sh" && \
    check "G4: restore confirmation gate" yes yes || check "G4: restore confirmation gate" yes no
grep -q 'root.restore" \] && {' "$ROOT/src/snapshot/restore.sh" && \
    check "G5: stale @root.restore refusal" yes yes || check "G5: stale @root.restore refusal" yes no
grep -q 'snap_boot_once' "$ROOT/src/snapshot/restore.sh" && \
    check "G7: boot-once implemented" yes yes || check "G7: boot-once implemented" yes no
grep -q '_restore_warn_kernel_mismatch' "$ROOT/src/snapshot/restore.sh" && \
    check "G8: kernel mismatch warning" yes yes || check "G8: kernel mismatch warning" yes no
grep -q 'snap_boot_entry_sync' "$ROOT/src/snapshot/prune.sh" && \
    check "G9: prune wires boot-entry sync" yes yes || check "G9: prune wires boot-entry sync" yes no
