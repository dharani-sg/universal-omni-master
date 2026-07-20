#!/bin/sh
# DRY-RUN T1-T10 TEST HARNESS
# Run this on the phone under realistic Termux env

export HOME=/data/data/com.termux/files/home

PASS=0
FAIL=0

pass() {
    PASS=$((PASS + 1))
    echo "PASS"
}
fail() {
    FAIL=$((FAIL + 1))
    echo "FAIL: $1"
}

echo "==========================================="
echo " DRY-RUN T1-T10 TEST HARNESS"
echo " $(date)"
echo "==========================================="
echo ""

# T1: QEMU is running and visible from widget context
echo -n "T1: QEMU visible... "
. ~/bin/uom-lib.sh
if uom_qemu_running; then
    pass
else
    fail "not running"
fi

# T2: Launcher status reports RUNNING
echo -n "T2: Launcher status... "
STATUS=$(~/bin/uom-qemu-phone status 2>&1)
if echo "$STATUS" | grep -q "RUNNING"; then
    pass
else
    fail "status=$(echo "$STATUS" | head -1)"
fi

# T3: Guest SSH works
echo -n "T3: Guest SSH... "
if uom_guest_ssh_test 3 10; then
    pass
else
    fail "SSH unreachable"
fi

# T4: Zen models API reachable from guest
echo -n "T4: Zen models API... "
MODELS=$(uom_guest_ssh "curl -s https://opencode.ai/zen/v1/models 2>/dev/null | head -c 200" 2>/dev/null)
if echo "$MODELS" | grep -q "id"; then
    pass
else
    fail "no model data"
fi

# T5: Guest filesystem write
echo -n "T5: Guest filesystem write... "
RESULT=$(uom_guest_ssh "echo dryrun-t5 > /tmp/dryrun-t5.txt && cat /tmp/dryrun-t5.txt" 2>/dev/null)
if echo "$RESULT" | grep -q "dryrun-t5"; then
    pass
else
    fail "write failed"
fi

# T6: Guest disk < 90%
echo -n "T6: Guest disk... "
DISK=$(uom_guest_ssh "df / | awk 'NR==2{print \$5}' | tr -d '%'" 2>/dev/null)
if [ -n "$DISK" ] && [ "$DISK" -lt 90 ] 2>/dev/null; then
    echo "PASS (${DISK}%)"
    PASS=$((PASS + 1))
else
    fail "disk=${DISK}%"
fi

# T7: Watchdog script present and executable
echo -n "T7: Watchdog present... "
if [ -x ~/bin/uom-qemu-watchdog.sh ]; then
    pass
else
    fail "not found"
fi

# T8: Consolidated lib present
echo -n "T8: Consolidated lib... "
if [ -x ~/bin/uom-lib.sh ]; then
    pass
else
    fail "not found"
fi

# T9: All widget scripts syntax-check
echo -n "T9: Widget syntax... "
ERRORS=""
for w in ~/.shortcuts/00-UOM-Status \
         ~/.shortcuts/20-UOM-Guest-Shell \
         ~/.shortcuts/30-UOM-Zen-Console \
         ~/.shortcuts/50-UOM-Logs \
         ~/.shortcuts/90-UOM-Stop \
         ~/.shortcuts/tasks/10-UOM-Start; do
    if ! sh -n "$w" 2>/dev/null; then
        ERRORS="$ERRORS $(basename "$w")"
    fi
done
if [ -z "$ERRORS" ]; then
    echo "PASS (6/6)"
    PASS=$((PASS + 1))
else
    fail "bad:$ERRORS"
fi

# T10: All scripts in ~/bin/ syntax-check
echo -n "T10: Bin scripts syntax... "
BIN_ERRS=""
for s in ~/bin/uom-lib.sh ~/bin/uom-qemu-phone ~/bin/uom-qemu-watchdog.sh ~/bin/uom-widget-lib.sh; do
    if ! sh -n "$s" 2>/dev/null; then
        BIN_ERRS="$BIN_ERRS $(basename "$s")"
    fi
done
if [ -z "$BIN_ERRS" ]; then
    echo "PASS (4/4)"
    PASS=$((PASS + 1))
else
    fail "bad:$BIN_ERRS"
fi

echo ""
echo "==========================================="
TOTAL=$((PASS + FAIL))
echo " RESULTS: $PASS/$TOTAL PASS, $FAIL FAIL"
echo "==========================================="
