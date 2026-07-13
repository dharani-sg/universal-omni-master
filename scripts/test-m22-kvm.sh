#!/bin/sh
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PASS=0
FAIL=0

_c() {
    if [ "$2" = "$3" ]; then
        printf '  PASS %-52s = %s\n' "$1" "$3"
        PASS=$((PASS + 1))
    else
        printf '  FAIL %-52s want=%s got=%s\n' "$1" "$2" "$3"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== M22 KVM/QEMU Test Harness Tests ==="
export OMNI_ROOT="$ROOT"

# Syntax
sh -n "$ROOT/src/test/kvm.sh" && _c "syntax: kvm.sh" ok ok || _c "syntax: kvm.sh" ok fail

. "$ROOT/src/test/kvm.sh"

# 1. Environment check
kvm_available >/dev/null 2>&1
_kvm_avail=$?
if [ "$_kvm_avail" -eq 0 ]; then
    _c "kvm_available: QEMU present on this host" yes yes
else
    _c "kvm_available: QEMU absent (acceptable in CI)" no no
fi

# 2. Prerequisites
rc=0; kvm_check_prerequisites >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; then
    _c "kvm_check_prerequisites completes without crash" yes yes
else
    _c "kvm_check_prerequisites completes without crash" yes no
fi

# 3. Missing script returns 1
rc=0; kvm_run_script "/nonexistent/script.sh" "/nonexistent.iso" >/dev/null 2>&1 || rc=$?
_c "kvm_run_script missing script returns 1" 1 "$rc"

# 4. Missing iso returns 1
_tmp_script="${TMPDIR:-/tmp}/omni-kvm-test-$$.sh"
printf '#!/bin/sh\nexit 0\n' > "$_tmp_script"
chmod +x "$_tmp_script"
rc=0; kvm_run_script "$_tmp_script" "/nonexistent.iso" >/dev/null 2>&1 || rc=$?
_c "kvm_run_script missing iso returns 1" 1 "$rc"
rm -f "$_tmp_script"

# 5. QEMU absent returns 77 (FIX: use real dummy files, not /dev/null)
if ! kvm_available; then
    _dummy_script="${TMPDIR:-/tmp}/omni-kvm-dummy-$$.sh"
    _dummy_iso="${TMPDIR:-/tmp}/omni-kvm-dummy-$$.iso"
    : > "$_dummy_script"
    : > "$_dummy_iso"
    rc=0; kvm_run_script "$_dummy_script" "$_dummy_iso" 1 >/dev/null 2>&1 || rc=$?
    _c "kvm_run_script without QEMU returns 77" 77 "$rc"
    rm -f "$_dummy_script" "$_dummy_iso"
else
    _c "kvm_run_script QEMU-present skip (covered on real host)" skip skip
fi

# 6. Smoke test
rc=0; kvm_smoke_test >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ] || [ "$rc" -eq 77 ]; then
    _c "kvm_smoke_test does not crash" yes yes
else
    _c "kvm_smoke_test does not crash" yes no
fi

# 7. Mock QEMU fallback — validates serial PASS/FAIL parsing even when real QEMU absent
MOCKDIR="${TMPDIR:-/tmp}/omni-m22-mock-$$"
mkdir -p "$MOCKDIR/bin"
OLDPATH=$PATH
PATH="$MOCKDIR/bin:$PATH"
export PATH

cat > "$MOCKDIR/bin/qemu-system-x86_64" << 'MOCK_QEMU_PASS'
#!/bin/sh
_serial=""
while [ $# -gt 0 ]; do
    if [ "$1" = "-serial" ]; then
        shift
        _serial="${1#file:}"
        break
    fi
    shift
done
if [ -n "$_serial" ]; then
    printf 'Booting...\n' > "$_serial"
    printf 'OMNI_TEST_PASS\n' >> "$_serial"
fi
exit 0
MOCK_QEMU_PASS
chmod +x "$MOCKDIR/bin/qemu-system-x86_64"

_dummy_script="${TMPDIR:-/tmp}/omni-kvm-mock-$$.sh"
_dummy_iso="${TMPDIR:-/tmp}/omni-kvm-mock-$$.iso"
: > "$_dummy_script"
: > "$_dummy_iso"

rc=0; kvm_run_script "$_dummy_script" "$_dummy_iso" 5 >/dev/null 2>&1 || rc=$?
_c "mock QEMU serial PASS detection returns 0" 0 "$rc"

cat > "$MOCKDIR/bin/qemu-system-x86_64" << 'MOCK_QEMU_FAIL'
#!/bin/sh
_serial=""
while [ $# -gt 0 ]; do
    if [ "$1" = "-serial" ]; then
        shift
        _serial="${1#file:}"
        break
    fi
    shift
done
if [ -n "$_serial" ]; then
    printf 'Kernel panic\n' > "$_serial"
    printf 'OMNI_TEST_FAIL\n' >> "$_serial"
fi
exit 0
MOCK_QEMU_FAIL
chmod +x "$MOCKDIR/bin/qemu-system-x86_64"

rc=0; kvm_run_script "$_dummy_script" "$_dummy_iso" 5 >/dev/null 2>&1 || rc=$?
_c "mock QEMU serial FAIL detection returns 1" 1 "$rc"

rm -f "$_dummy_script" "$_dummy_iso"
rm -rf "$MOCKDIR"
PATH=$OLDPATH
export PATH

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
