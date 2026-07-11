#!/bin/sh
# M11.1 release-blocker audit (corrected: @root is the project convention).
fail=0
_r() { echo "  $1"; }

grep -q 'btrfs subvolume set-default' src/snapshot/restore.sh \
    && { _r "FAIL restore still uses set-default"; fail=1; } \
    || _r "PASS restore does not use set-default"

grep -q '_restore_confirm' src/snapshot/restore.sh \
    && _r "PASS restore has confirmation gate" \
    || { _r "FAIL restore confirmation missing"; fail=1; }

grep -q '@restore_' src/snapshot/restore.sh \
    && _r "PASS restore uses unique RW clone name" \
    || { _r "FAIL restore clone name not unique"; fail=1; }

grep -Eq '^[[:space:]]*restore\|rollback\)' bin/omni-snapshot \
    && _r "PASS restore/rollback dispatch present" \
    || { _r "FAIL restore/rollback dispatch absent"; fail=1; }

grep -Eq '^[[:space:]]*boot-once\)' bin/omni-snapshot \
    && _r "PASS boot-once dispatch present" \
    || { _r "FAIL boot-once dispatch absent"; fail=1; }

for m in boot_entry.sh restore.sh; do
    grep -q "$m" src/deploy/snapshot_install.sh \
        && _r "PASS deploy payload includes $m" \
        || { _r "FAIL deploy payload omits $m"; fail=1; }
done

echo "RESULT: fail=$fail"
[ "$fail" -eq 0 ]
