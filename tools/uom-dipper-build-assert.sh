#!/bin/sh
# UOM Dipper Build Assertions
# Run after every boot.img build, before any boot.
# Exit 0 = all assertions PASS; exit 1 = any assertion FAIL.

set -e

BOOTIMG="${1:?Usage: $0 <boot.img>}"
VAULT_DTB_SHA256="f8f6b32583d625d493f97269f347b7841f0cbb6482207bccc589c27b5a74f205"

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }

[ -f "$BOOTIMG" ] || fail "boot.img not found: $BOOTIMG"

echo "=== UOM Dipper Build Assertions ==="
echo "Image: $BOOTIMG"
echo ""

# 1. Check file size
SIZE=$(stat -c%s "$BOOTIMG")
MAX_SIZE=$((80 * 1024 * 1024))
[ "$SIZE" -le "$MAX_SIZE" ] || fail "boot.img too large: $SIZE > $MAX_SIZE"
pass "Size: $SIZE bytes (limit $MAX_SIZE)"

# 2. Check magic (ANDROID!)
MAGIC=$(dd if="$BOOTIMG" bs=8 count=1 2>/dev/null)
[ "$MAGIC" = "ANDROID!" ] || fail "bad magic: $MAGIC"
pass "Magic: ANDROID!"

# 3. Check cmdline contains panic= and rdinit=
CMDLINE=$(dd if="$BOOTIMG" bs=1 skip=64 count=512 2>/dev/null | tr '\0' ' ')
echo "$CMDLINE" | grep -q "panic=" || fail "cmdline missing panic="
echo "$CMDLINE" | grep -q "rdinit=" || fail "cmdline missing rdinit="
echo "$CMDLINE" | grep -q "console=" || fail "cmdline missing console="
pass "Cmdline contains panic=, rdinit=, console="

# 4. DTB check via gates tool
GATES_TOOL="$(dirname "$0")/uom-bootimg-gates.py"
if [ -f "$GATES_TOOL" ]; then
    python3 "$GATES_TOOL" \
        --image "$BOOTIMG" \
        --stage L0 \
        --check-dtb-compatible \
        --check-dtb-board-id 0x37 \
        --check-dtb-headless \
        --check-dtb-sha256 "$VAULT_DTB_SHA256" \
        --check-no-beryllium \
        --check-cpio-contains init_uom \
        --check-cpio-contains uom-dipper-diag-init \
        --check-cpio-contains 00-watchdog-reboot.sh \
        --check-cmdline-contains panic= \
        --check-cmdline-contains rdinit= \
        --check-cmdline-contains console= \
        --check-size-max "$MAX_SIZE" \
        > /dev/null 2>&1 && pass "Gates tool PASS" || fail "Gates tool FAIL"
else
    echo "WARN: gates tool not found, skipping DTB/CPIO checks"
fi

echo ""
echo "=== ALL ASSERTIONS PASS ==="
