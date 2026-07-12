#!/bin/sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
_c() { [ "$2" = "$3" ] && { printf '  PASS %-50s = %s\n' "$1" "$3"; PASS=$((PASS+1)); } || { printf '  FAIL %-50s want=%s got=%s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); }; }

echo "=== M14 Security Module Tests ==="

for f in "$ROOT/src/security/tpm2.sh" "$ROOT/src/security/uki.sh" "$ROOT/src/security/sbat.sh" "$ROOT/bin/omni-security"; do
    sh -n "$f" && _c "syntax: $(basename "$f")" ok ok || _c "syntax: $(basename "$f")" ok fail
done

. "$ROOT/src/security/tpm2.sh"
. "$ROOT/src/security/uki.sh"
. "$ROOT/src/security/sbat.sh"

# --- Real-host degradation (THIS laptop: no TPM, no sbverify) -----------
_probe_real=$(security_tpm2_probe 2>&1)
case "$_probe_real" in
    *status=unavailable*) _c "real host: tpm2 unavailable (no crash)" yes yes ;;
    *) _c "real host: tpm2 unavailable (no crash)" yes no ;;
esac

rc=0; security_tpm2_audit >/dev/null 2>&1 || rc=$?
_c "real host: tpm2_audit degrades, rc=0" 0 "$rc"

# --- Mock tool harness ---------------------------------------------------
MOCKDIR="${TMPDIR:-/tmp}/omni-m14-mock-$$"
mkdir -p "$MOCKDIR"

cat > "$MOCKDIR/tpm2_pcrread" << 'MOCK1'
#!/bin/sh
printf 'sha256:\n  0 : 0xAAAA...\n  7 : 0xBBBB...\n'
MOCK1
chmod +x "$MOCKDIR/tpm2_pcrread"

cat > "$MOCKDIR/sbverify" << 'MOCK2'
#!/bin/sh
# args: --cert <cert> <bin>
exit 0
MOCK2
chmod +x "$MOCKDIR/sbverify"

_have_readelf=$(command -v readelf || true)

OLDPATH="$PATH"
export PATH="$MOCKDIR:$PATH"
FAKETPM="${TMPDIR:-/tmp}/omni-m14-tpm0"
mkdir -p "$FAKETPM"

# Simulate presence of TPM device via a symlink trick isn't possible for
# /sys, so we test the probe/audit logic paths independently by forcing
# the has-tool branch and checking output shape, not the device branch
# (device presence cannot be faked without root/hardware on this host).

_probe_mock=$(security_tpm2_probe 2>&1)
case "$_probe_mock" in
    *status=unavailable*) _c "mock PATH: still reports unavailable (no /sys/class/tpm)" yes yes ;;
    *) _c "mock PATH: still reports unavailable (no /sys/class/tpm)" yes no ;;
esac

# --- UKI verify with mocked sbverify + a real dummy PE-ish file ----------
DUMMY_PE="${TMPDIR:-/tmp}/omni-m14-dummy.efi"
# Build a minimal fake PE: "MZ" + padding to offset 0x3C + 4-byte LE offset(0x40) + "PE\0\0"
{
    printf 'MZ'
    dd if=/dev/zero bs=1 count=58 2>/dev/null
    printf '\x40\x00\x00\x00'
    dd if=/dev/zero bs=1 count=0 2>/dev/null
} > "$DUMMY_PE"
printf 'PE\0\0' >> "$DUMMY_PE"

rc=0; _out=$(security_uki_verify "$DUMMY_PE" "/dummy/cert.pem" 2>&1) || rc=$?
case "$_out" in
    *method=sbverify*) _c "uki_verify uses mocked sbverify when present" yes yes ;;
    *) _c "uki_verify uses mocked sbverify when present" yes no ;;
esac

rm -f "$MOCKDIR/sbverify"
rc=0; _out=$(security_uki_verify "$DUMMY_PE" "/dummy/cert.pem" 2>&1) || rc=$?
case "$_out" in
    *method=structural*status=structurally_valid*|*status=structurally_valid*method=structural*)
        _c "uki_verify falls back to structural check" yes yes ;;
    *) _c "uki_verify falls back to structural check" yes "no($_out)" ;;
esac

export PATH="$OLDPATH"
rm -rf "$MOCKDIR" "$DUMMY_PE" "$FAKETPM" 2>/dev/null

# --- Malformed file rejected ----------------------------------------------
BADFILE="${TMPDIR:-/tmp}/omni-m14-bad-$$"
printf 'not a pe file at all' > "$BADFILE"
rc=0; security_uki_verify "$BADFILE" >/dev/null 2>&1 || rc=$?
_c "uki_verify rejects non-PE file rc=1" 1 "$rc"
rm -f "$BADFILE"

# Missing file
rc=0; security_uki_verify "/nonexistent/path.efi" >/dev/null 2>&1 || rc=$?
_c "uki_verify missing file rc=2" 2 "$rc"

# --- SBAT: no section on a plain-text file --------------------------------
NOSBAT="${TMPDIR:-/tmp}/omni-m14-nosbat-$$"
printf 'plain text, no elf sections' > "$NOSBAT"
rc=0; security_sbat_audit "$NOSBAT" grub 5 >/dev/null 2>&1 || rc=$?
_c "sbat_audit no-section degrades rc=0" 0 "$rc"
rm -f "$NOSBAT"

# --- Mutation guard on enroll ---------------------------------------------
rc=0; OMNI_SYSROOT=/tmp/fx security_tpm2_enroll /dev/null >/dev/null 2>&1 || rc=$?
_c "tpm2_enroll OMNI_SYSROOT guard 126" 126 "$rc"

# --- CLI dispatch ----------------------------------------------------------
rc=0; "$ROOT/bin/omni-security" help >/dev/null 2>&1 || rc=$?
_c "cli help exits 0" 0 "$rc"

rc=0; "$ROOT/bin/omni-security" bogus >/dev/null 2>&1 || rc=$?
_c "cli unknown exits 2" 2 "$rc"

rc=0; "$ROOT/bin/omni-security" probe >/dev/null 2>&1 || rc=$?
_c "cli probe exits 0 (degraded host)" 0 "$rc"

rc=0; OMNI_SYSROOT=/tmp/fx "$ROOT/bin/omni-security" enroll tpm2 /dev/null >/dev/null 2>&1 || rc=$?
_c "cli enroll guard 126" 126 "$rc"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
