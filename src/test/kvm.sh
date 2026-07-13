#!/bin/sh
# src/test/kvm.sh — M22: Headless QEMU/KVM test primitives.

OMNI_KVM_TIMEOUT="${OMNI_KVM_TIMEOUT:-120}"
OMNI_KVM_MEMORY="${OMNI_KVM_MEMORY:-512m}"

kvm_available() {
    command -v qemu-system-x86_64 >/dev/null 2>&1
}

kvm_check_prerequisites() {
    _missing=0
    if ! kvm_available; then
        printf 'kvm: qemu-system-x86_64 missing\n' >&2
        _missing=1
    fi
    if ! command -v kvm >/dev/null 2>&1 && [ ! -w /dev/kvm ] 2>/dev/null; then
        printf 'kvm: /dev/kvm not accessible (hardware virtualization disabled)\n' >&2
        # Not fatal for emulation, but slow
    fi
    return "$_missing"
}

kvm_run_script() {
    _kvm_script="${1:?kvm_run_script: script required}"
    _kvm_iso="${2:?kvm_run_script: iso required}"
    _kvm_timeout="${3:-$OMNI_KVM_TIMEOUT}"

    # CRITICAL FIX: Validate inputs BEFORE checking environment
    [ -f "$_kvm_script" ] || { printf 'kvm: script not found: %s\n' "$_kvm_script" >&2; return 1; }
    [ -f "$_kvm_iso" ] || { printf 'kvm: iso not found: %s\n' "$_kvm_iso" >&2; return 1; }

    if ! kvm_available; then
        printf 'kvm: QEMU not available — skipping hardware test\n' >&2
        return 77
    fi

    _kvm_serial="${TMPDIR:-/tmp}/omni-kvm-serial-$$.log"
    _kvm_pidfile="${TMPDIR:-/tmp}/omni-kvm-pid-$$"

    qemu-system-x86_64 \
        -nographic \
        -serial "file:$_kvm_serial" \
        -monitor none \
        -m "$OMNI_KVM_MEMORY" \
        -cdrom "$_kvm_iso" \
        -no-reboot \
        -pidfile "$_kvm_pidfile" \
        2>/dev/null &

    _kvm_pid=$!
    _kvm_elapsed=0
    _kvm_rc=2

    while [ "$_kvm_elapsed" -lt "$_kvm_timeout" ]; do
        sleep 1
        _kvm_elapsed=$((_kvm_elapsed + 1))

        if grep -q 'OMNI_TEST_PASS' "$_kvm_serial" 2>/dev/null; then
            _kvm_rc=0; break
        fi
        if grep -q 'OMNI_TEST_FAIL' "$_kvm_serial" 2>/dev/null; then
            _kvm_rc=1; break
        fi
        if ! kill -0 "$_kvm_pid" 2>/dev/null; then
            _kvm_rc=1; break
        fi
    done

    kill "$_kvm_pid" 2>/dev/null || true
    rm -f "$_kvm_pidfile" "$_kvm_serial"
    return "$_kvm_rc"
}

kvm_smoke_test() {
    if ! kvm_available; then
        printf 'kvm_smoke_test: QEMU unavailable — skip\n' >&2
        return 77
    fi
    printf 'kvm_smoke_test: QEMU binary present and executable\n'
    return 0
}
