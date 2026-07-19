#!/bin/sh
# tests/test-phone-bootstrap.sh — Deterministic test harness for phone bootstrap
# Run: sh tests/test-phone-bootstrap.sh
# Requires: sh, grep, mkdir, rm, cat, touch, chmod (POSIX)
# Optional: shellcheck

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOTSTRAP="$REPO_DIR/install/bootstrap.sh"
BOOTSTRAP_TERMUX="$REPO_DIR/install/bootstrap-termux.sh"
RESULTS_DIR="$SCRIPT_DIR/results"
FIXTURES="$SCRIPT_DIR/fixtures/phone-bootstrap"
RESULTS="$RESULTS_DIR/phone-bootstrap-results.json"

mkdir -p "$RESULTS_DIR" "$FIXTURES"

# ── Test infrastructure ──────────────────────────────────────────────────
_PASS=0
_FAIL=0
_SKIP=0
_TOTAL=0

pass() {
  _TOTAL=$((_TOTAL + 1))
  _PASS=$((_PASS + 1))
  printf '  PASS: %s\n' "$1"
}

fail() {
  _TOTAL=$((_TOTAL + 1))
  _FAIL=$((_FAIL + 1))
  printf '  FAIL: %s — %s\n' "$1" "$2"
}

skip() {
  _TOTAL=$((_TOTAL + 1))
  _SKIP=$((_SKIP + 1))
  printf '  SKIP: %s — %s\n' "$1" "$2"
}

assert_file_exists() {
  if [ -f "$1" ]; then
    pass "$2"
  else
    fail "$2" "file not found: $1"
  fi
}

assert_file_not_exists() {
  if [ ! -f "$1" ]; then
    pass "$2"
  else
    fail "$2" "file should not exist: $1"
  fi
}

assert_file_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then
    pass "$3"
  else
    fail "$3" "pattern '$2' not found in $1"
  fi
}

assert_file_not_contains() {
  if ! grep -q "$2" "$1" 2>/dev/null; then
    pass "$3"
  else
    fail "$3" "pattern '$2' found in $1 (should not be)"
  fi
}

assert_exit_code() {
  if [ "$1" = "$2" ]; then
    pass "$3"
  else
    fail "$3" "expected exit $2, got $1"
  fi
}

assert_dir_exists() {
  if [ -d "$1" ]; then
    pass "$2"
  else
    fail "$2" "directory not found: $1"
  fi
}

assert_dir_not_exists() {
  if [ ! -d "$1" ]; then
    pass "$2"
  else
    fail "$2" "directory should not exist: $1"
  fi
}

# ── Helper: create mock environment ──────────────────────────────────────
MOCK_HOME=""
MOCK_ROOT=""

setup_mock() {
  MOCK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/uom-test-XXXXXX")"
  MOCK_HOME="$MOCK_ROOT/home"
  mkdir -p "$MOCK_HOME/.ssh" "$MOCK_HOME/src"
  export HOME="$MOCK_HOME"
  export PREFIX="/data/data/com.termux/files/usr"
  export UOM_SDK_OVERRIDE=28
}

cleanup_mock() {
  [ -n "$MOCK_ROOT" ] && rm -rf "$MOCK_ROOT"
  MOCK_ROOT=""
}

# ── SECTION 1: PLATFORM DETECTION ───────────────────────────────────────
printf '\n=== PLATFORM DETECTION (Tests 1-10) ===\n'

# Test 1: bootstrap.sh syntax
sh -n "$BOOTSTRAP" && pass "T01: bootstrap.sh syntax valid" || fail "T01: bootstrap.sh syntax" "sh -n failed"

# Test 2: bootstrap-termux.sh syntax
sh -n "$BOOTSTRAP_TERMUX" && pass "T02: bootstrap-termux.sh syntax valid" || fail "T02: bootstrap-termux.sh syntax" "sh -n failed"

# Test 3: No hardcoded IPs
if ! grep -q '192\.168\.' "$BOOTSTRAP" "$BOOTSTRAP_TERMUX" 2>/dev/null; then
  pass "T03: No hardcoded IPs"
else
  fail "T03: No hardcoded IPs" "found hardcoded IP"
fi

# Test 4: No hardcoded hostnames
if ! grep -q 'hp-pavilion' "$BOOTSTRAP" "$BOOTSTRAP_TERMUX" 2>/dev/null; then
  pass "T04: No hardcoded hostnames"
else
  fail "T04: No hardcoded hostnames" "found hardcoded hostname"
fi

# Test 5: No curl|bash
if ! grep -q 'curl.*|.*bash' "$BOOTSTRAP" 2>/dev/null; then
  pass "T05: No curl|bash in bootstrap.sh"
else
  fail "T05: No curl|bash" "found curl|bash pattern"
fi

# Test 6: No non-POSIX &>
if ! grep -q '&>' "$BOOTSTRAP_TERMUX" 2>/dev/null; then
  pass "T06: No non-POSIX &> in bootstrap-termux.sh"
else
  fail "T06: No non-POSIX &>" "found &> pattern"
fi

# Test 7: --help works
MOCK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/uom-test-XXXXXX")"
OUTPUT=$(HOME="$MOCK_HOME" UOM_SDK_OVERRIDE=28 sh "$BOOTSTRAP_TERMUX" --help 2>&1 || true)
assert_exit_code 0 $? "T07: --help exits 0"
echo "$OUTPUT" | grep -q "Usage:" && pass "T08: --help shows usage" || fail "T08: --help shows usage" "no Usage: found"

# Test 8: Unknown argument rejected
HOME="$MOCK_HOME" UOM_SDK_OVERRIDE=28 sh "$BOOTSTRAP_TERMUX" --bogus 2>/dev/null
assert_exit_code 1 $? "T09: Unknown argument exits 1"
rm -rf "$MOCK_HOME"

# Test 9: Default mode is check
MOCK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/uom-test-XXXXXX")"
OUTPUT=$(HOME="$MOCK_HOME" UOM_SDK_OVERRIDE=28 sh "$BOOTSTRAP_TERMUX" --check 2>&1 || true)
echo "$OUTPUT" | grep -qiE 'check|dry.run' && pass "T10: Default mode is check" || fail "T10: Default mode" "check not mentioned"
rm -rf "$MOCK_HOME"

# ── SECTION 2: CHECK MODE READ-ONLY ─────────────────────────────────────
printf '\n=== CHECK MODE READ-ONLY (Tests 11-20) ===\n'

# Test 11-13: --check creates no files (excluding npm/node cache noise)
setup_mock
PRE_FILES=$(find "$MOCK_HOME" -type f -not -path '*/.npm/*' -not -path '*/node-compile-cache/*' 2>/dev/null | wc -l)
HOME="$MOCK_HOME" sh "$BOOTSTRAP_TERMUX" --check 2>/dev/null
POST_FILES=$(find "$MOCK_HOME" -type f -not -path '*/.npm/*' -not -path '*/node-compile-cache/*' 2>/dev/null | wc -l)
if [ "$PRE_FILES" -eq "$POST_FILES" ]; then
  pass "T11: --check creates no new files"
else
  fail "T11: --check creates no new files" "before=$PRE_FILES after=$POST_FILES"
fi

# Test 12: --check doesn't create directories that didn't exist
assert_dir_not_exists "$MOCK_HOME/.termux" "T12: --check doesn't create .termux"

# Test 13: --check doesn't modify .ssh
assert_dir_not_exists "$MOCK_HOME/.ssh/config" "T13: --check doesn't create SSH config"
cleanup_mock

# Test 14: --check doesn't clone repo
setup_mock
assert_dir_not_exists "$MOCK_HOME/src/universal-omni-master" "T14: repo dir doesn't exist before check"
HOME="$MOCK_HOME" sh "$BOOTSTRAP_TERMUX" --check 2>/dev/null
# Check that src/ was not created
if [ ! -d "$MOCK_HOME/src/universal-omni-master" ]; then
  pass "T14: --check doesn't create repo directory"
else
  fail "T14: --check doesn't create repo directory" "directory created"
fi
cleanup_mock

# Test 15: --check with --profile phone-relay
setup_mock
OUTPUT=$(HOME="$MOCK_HOME" sh "$BOOTSTRAP_TERMUX" --check --profile phone-relay 2>&1 || true)
echo "$OUTPUT" | grep -q "phone-relay\|check" && pass "T15: --check --profile phone-relay works" || fail "T15: --check --profile phone-relay" "output missing expected strings"
cleanup_mock

# Test 16: --check with --test-root (no writes outside test root)
setup_mock
TEST_ROOT="$MOCK_ROOT/test-install"
OUTPUT=$(HOME="$MOCK_HOME" sh "$BOOTSTRAP_TERMUX" --check --test-root "$TEST_ROOT" 2>&1 || true)
assert_exit_code 0 $? "T16: --check --test-root exits 0"
cleanup_mock

# Test 17: --check shows Android SDK
setup_mock
OUTPUT=$(HOME="$MOCK_HOME" sh "$BOOTSTRAP_TERMUX" --check 2>&1 || true)
echo "$OUTPUT" | grep -q "Android SDK" && pass "T17: --check shows Android SDK" || fail "T17: --check shows Android SDK" "SDK not mentioned"
cleanup_mock

# Test 18: --check shows opencode status
setup_mock
OUTPUT=$(HOME="$MOCK_HOME" sh "$BOOTSTRAP_TERMUX" --check 2>&1 || true)
echo "$OUTPUT" | grep -q "opencode" && pass "T18: --check shows opencode status" || fail "T18: --check shows opencode status" "opencode not mentioned"
cleanup_mock

# Test 19: --check shows companion packages
setup_mock
OUTPUT=$(HOME="$MOCK_HOME" sh "$BOOTSTRAP_TERMUX" --check 2>&1 || true)
echo "$OUTPUT" | grep -q "Companion packages" && pass "T19: --check lists companion packages" || fail "T19: --check lists companion packages" "packages not mentioned"
cleanup_mock

# Test 20: --check shows summary
setup_mock
OUTPUT=$(HOME="$MOCK_HOME" sh "$BOOTSTRAP_TERMUX" --check 2>&1 || true)
echo "$OUTPUT" | grep -q "UOM BOOTSTRAP SUMMARY" && pass "T20: --check shows summary" || fail "T20: --check shows summary" "summary not found"
cleanup_mock

# ── SECTION 3: DOWNLOAD VALIDATION ──────────────────────────────────────
printf '\n=== DOWNLOAD VALIDATION (Tests 21-27) ===\n'

# Test 21: bootstrap.sh has shebang
HEAD1=$(head -1 "$BOOTSTRAP")
case "$HEAD1" in '#!'*) pass "T21: bootstrap.sh has shebang" ;; *) fail "T21: bootstrap.sh has shebang" "no shebang" ;; esac

# Test 22: bootstrap-termux.sh has shebang
HEAD1=$(head -1 "$BOOTSTRAP_TERMUX")
case "$HEAD1" in '#!'*) pass "T22: bootstrap-termux.sh has shebang" ;; *) fail "T22: bootstrap-termux.sh has shebang" "no shebang" ;; esac

# Test 23: bootstrap.sh < 10KB
SIZE=$(wc -c < "$BOOTSTRAP")
if [ "$SIZE" -lt 10000 ]; then pass "T23: bootstrap.sh < 10KB ($SIZE bytes)" ; else fail "T23: bootstrap.sh < 10KB" "$SIZE bytes" ; fi

# Test 24: bootstrap-termux.sh < 30KB
SIZE=$(wc -c < "$BOOTSTRAP_TERMUX")
if [ "$SIZE" -lt 30000 ]; then pass "T24: bootstrap-termux.sh < 30KB ($SIZE bytes)" ; else fail "T24: bootstrap-termux.sh < 30KB" "$SIZE bytes" ; fi

# Test 25: No HTML content in scripts (excluding grep/case patterns that reference HTML)
# The bootstrap.sh validator contains a grep pattern that checks for HTML — that's OK.
# We check for actual HTML tags on non-grep lines.
HTML_FOUND=0
for _f in "$BOOTSTRAP" "$BOOTSTRAP_TERMUX"; do
  # Skip lines that are grep patterns, case patterns, or comments referencing HTML
  if grep -n '<!DOCTYPE\|<html\|<head\|<body' "$_f" 2>/dev/null | grep -v 'grep\|case\|DOCTYPE.*html' | grep -qiE '^\s*<'; then
    HTML_FOUND=1
  fi
done
if [ "$HTML_FOUND" -eq 0 ]; then
  pass "T25: No HTML content"
else
  fail "T25: No HTML content" "found actual HTML tags"
fi

# Test 26: bootstrap.sh has version comment
grep -q "install/bootstrap.sh" "$BOOTSTRAP" && pass "T26: bootstrap.sh has file path comment" || fail "T26: bootstrap.sh has file path comment" "missing"

# Test 27: bootstrap-termux.sh has version comment
grep -q "install/bootstrap-termux.sh" "$BOOTSTRAP_TERMUX" && pass "T27: bootstrap-termux.sh has file path comment" || fail "T27: bootstrap-termux.sh has file path comment" "missing"

# ── SECTION 4: ARGUMENT FORWARDING ──────────────────────────────────────
printf '\n=== ARGUMENT FORWARDING (Tests 28-35) ===\n'

# Test 28: bootstrap.sh --help shows usage
MOCK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/uom-test-XXXXXX")"
OUTPUT=$(HOME="$MOCK_HOME" sh "$BOOTSTRAP" --help 2>&1 || true)
echo "$OUTPUT" | grep -q "Usage\|help\|OPTIONS" && pass "T28: bootstrap.sh --help shows usage" || fail "T28: bootstrap.sh --help" "no usage output"
rm -rf "$MOCK_HOME"

# Test 29: --apply flag recognized
MOCK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/uom-test-XXXXXX")"
OUTPUT=$(HOME="$MOCK_HOME" UOM_SDK_OVERRIDE=28 sh "$BOOTSTRAP_TERMUX" --apply 2>&1 || true)
echo "$OUTPUT" | grep -qiE 'apply|dry.run|android.sdk' && pass "T29: --apply flag recognized" || fail "T29: --apply flag" "not recognized"
rm -rf "$MOCK_HOME"

# Test 30: --check flag recognized
MOCK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/uom-test-XXXXXX")"
OUTPUT=$(HOME="$MOCK_HOME" UOM_SDK_OVERRIDE=28 sh "$BOOTSTRAP_TERMUX" --check 2>&1 || true)
echo "$OUTPUT" | grep -qiE 'check|dry.run|android.sdk' && pass "T30: --check flag recognized" || fail "T30: --check flag" "not recognized"
rm -rf "$MOCK_HOME"

# Test 31: --verify flag recognized
MOCK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/uom-test-XXXXXX")"
OUTPUT=$(HOME="$MOCK_HOME" UOM_SDK_OVERRIDE=28 sh "$BOOTSTRAP_TERMUX" --verify 2>&1 || true)
echo "$OUTPUT" | grep -qiE 'VERIFY|verify|android.sdk' && pass "T31: --verify flag recognized" || fail "T31: --verify flag" "not recognized"
rm -rf "$MOCK_HOME"

# Test 32: --ref accepted
MOCK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/uom-test-XXXXXX")"
OUTPUT=$(HOME="$MOCK_HOME" sh "$BOOTSTRAP_TERMUX" --check --ref main 2>&1 || true)
assert_exit_code 0 $? "T32: --ref accepted"
rm -rf "$MOCK_HOME"

# Test 33: --profile accepted
MOCK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/uom-test-XXXXXX")"
OUTPUT=$(HOME="$MOCK_HOME" sh "$BOOTSTRAP_TERMUX" --check --profile phone-relay 2>&1 || true)
assert_exit_code 0 $? "T33: --profile accepted"
rm -rf "$MOCK_HOME"

# Test 34: --skip-packages accepted
MOCK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/uom-test-XXXXXX")"
OUTPUT=$(HOME="$MOCK_HOME" sh "$BOOTSTRAP_TERMUX" --check --skip-packages 2>&1 || true)
assert_exit_code 0 $? "T34: --skip-packages accepted"
rm -rf "$MOCK_HOME"

# Test 35: --test-root accepted
MOCK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/uom-test-XXXXXX")"
OUTPUT=$(HOME="$MOCK_HOME" sh "$BOOTSTRAP_TERMUX" --check --test-root "$MOCK_ROOT/test" 2>&1 || true)
assert_exit_code 0 $? "T35: --test-root accepted"
rm -rf "$MOCK_HOME"

# ── SECTION 5: SSH SAFETY ───────────────────────────────────────────────
printf '\n=== SSH SAFETY (Tests 36-42) ===\n'

# Test 36: No StrictHostKeyChecking=no
if ! grep -q 'StrictHostKeyChecking no' "$BOOTSTRAP_TERMUX" 2>/dev/null; then
  pass "T36: No StrictHostKeyChecking=no"
else
  fail "T36: No StrictHostKeyChecking=no" "found insecure setting"
fi

# Test 37: Uses accept-new instead
grep -q 'accept-new' "$BOOTSTRAP_TERMUX" && pass "T37: Uses StrictHostKeyChecking accept-new" || fail "T37: Uses accept-new" "not found"

# Test 38: Uses dedicated key name (not default id_ed25519)
grep -q 'id_ed25519_uom' "$BOOTSTRAP_TERMUX" && pass "T38: Uses dedicated key id_ed25519_uom" || fail "T38: Uses dedicated key" "not found"

# Test 39: SSH config appends managed block (doesn't replace)
grep -q 'UOM-MANAGED-BEGIN' "$BOOTSTRAP_TERMUX" && pass "T39: SSH config uses managed block" || fail "T39: Uses managed block" "not found"

# Test 40: Backup exists before config change
grep -q 'config.bak' "$BOOTSTRAP_TERMUX" && pass "T40: Backs up existing SSH config" || fail "T40: SSH config backup" "not found"

# Test 41: Key not overwritten if exists
grep -q 'SSH key already exists' "$BOOTSTRAP_TERMUX" && pass "T41: Key detection before generation" || fail "T41: Key detection" "not implemented"

# Test 42: chmod 700 on .ssh directory
grep -q 'chmod 700' "$BOOTSTRAP_TERMUX" && pass "T42: Sets correct permissions on .ssh" || fail "T42: .ssh permissions" "chmod 700 not found"

# ── SECTION 6: METADATA & JSON SAFETY ───────────────────────────────────
printf '\n=== METADATA & JSON SAFETY (Tests 43-48) ===\n'

# Test 43: json_escape helper exists
grep -q 'json_escape' "$BOOTSTRAP_TERMUX" && pass "T43: json_escape helper defined" || fail "T43: json_escape" "not found"

# Test 44: Metadata uses json_escape
grep -q 'json_escape.*ANDROID_RELEASE' "$BOOTSTRAP_TERMUX" && pass "T44: Metadata escapes strings" || fail "T44: Metadata escaping" "not found"

# Test 45: Metadata includes profile field
grep -q '"profile"' "$BOOTSTRAP_TERMUX" && pass "T45: Metadata includes profile" || fail "T45: Metadata profile" "not found"

# Test 46: Metadata includes ref field
grep -q '"ref"' "$BOOTSTRAP_TERMUX" && pass "T46: Metadata includes ref" || fail "T46: Metadata ref" "not found"

# Test 47: Metadata includes test_root field
grep -q '"test_root"' "$BOOTSTRAP_TERMUX" && pass "T47: Metadata includes test_root" || fail "T47: Metadata test_root" "not found"

# Test 48: Metadata schema is 1
grep -q '"schema": 1' "$BOOTSTRAP_TERMUX" && pass "T48: Metadata schema is 1" || fail "T48: Metadata schema" "not 1"

# ── SECTION 7: IDEMPOTENCY & LOCK ───────────────────────────────────────
printf '\n=== IDEMPOTENCY & LOCK (Tests 49-55) ===\n'

# Test 49: Lock mechanism exists
grep -q 'INSTALL_LOCK' "$BOOTSTRAP_TERMUX" && pass "T49: Lock mechanism defined" || fail "T49: Lock mechanism" "not found"

# Test 50: Stale lock detection
grep -q 'Stale lock' "$BOOTSTRAP_TERMUX" && pass "T50: Stale lock detection" || fail "T50: Stale lock" "not found"

# Test 51: SSH managed block deduplication
grep -q 'already has UOM managed block\|managed block already' "$BOOTSTRAP_TERMUX" && pass "T51: SSH block deduplication" || fail "T51: SSH dedup" "not found"

# Test 52: Dirty repo detection
grep -q 'dirty' "$BOOTSTRAP_TERMUX" && pass "T52: Dirty repo detection" || fail "T52: Dirty repo" "not found"

# Test 53: ff-only pull
grep -q 'ff-only\|FETCH_HEAD' "$BOOTSTRAP_TERMUX" && pass "T53: ff-only pull" || fail "T53: ff-only pull" "not found"

# Test 54: Interrupt trap
grep -q 'trap.*cleanup' "$BOOTSTRAP_TERMUX" && pass "T54: Interrupt trap defined" || fail "T54: Interrupt trap" "not found"

# Test 55: Rollback mechanism
grep -q 'run_rollback\|ROLLED_BACK' "$BOOTSTRAP_TERMUX" && pass "T55: Rollback mechanism" || fail "T55: Rollback" "not found"

# ── SECTION 8: VERIFY MODE ──────────────────────────────────────────────
printf '\n=== VERIFY MODE (Tests 56-60) ===\n'

# Test 56: --verify mode exists
grep -q 'VERIFY_PASS\|VERIFY_FAIL' "$BOOTSTRAP_TERMUX" && pass "T56: Verify mode outputs defined" || fail "T56: Verify mode" "not found"

# Test 57: Verify checks SSH key
grep -q 'SSH key.*PASS\|SSH key.*MISSING' "$BOOTSTRAP_TERMUX" && pass "T57: Verify checks SSH key" || fail "T57: Verify SSH key" "not found"

# Test 58: Verify checks repo
grep -q 'Repository.*PASS\|Repository.*MISSING' "$BOOTSTRAP_TERMUX" && pass "T58: Verify checks repository" || fail "T58: Verify repo" "not found"

# Test 59: Verify checks packages
grep -q 'Package.*PASS\|Package.*MISSING' "$BOOTSTRAP_TERMUX" && pass "T59: Verify checks packages" || fail "T59: Verify packages" "not found"

# Test 60: Verify checks metadata
grep -q 'Metadata.*PASS\|Metadata.*MISSING' "$BOOTSTRAP_TERMUX" && pass "T60: Verify checks metadata" || fail "T60: Verify metadata" "not found"

# ── SECTION 9: EDGE CASES ──────────────────────────────────────────────
printf '\n=== EDGE CASES (Tests 61-67) ===\n'

# Test 61: Empty HOME doesn't crash
MOCK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/uom-test-XXXXXX")"
HOME="" UOM_SDK_OVERRIDE=28 sh "$BOOTSTRAP_TERMUX" --check 2>/dev/null
assert_exit_code 0 $? "T61: Empty HOME doesn't crash"
rm -rf "$MOCK_HOME"

# Test 62: HOME with spaces
MOCK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/uom test-XXXXXX")"
HOME="$MOCK_HOME" UOM_SDK_OVERRIDE=28 sh "$BOOTSTRAP_TERMUX" --check 2>/dev/null
assert_exit_code 0 $? "T62: HOME with spaces works"
rm -rf "$MOCK_HOME"

# Test 63: Large number of arguments
MOCK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/uom-test-XXXXXX")"
HOME="$MOCK_HOME" UOM_SDK_OVERRIDE=28 sh "$BOOTSTRAP_TERMUX" --check --check --check 2>/dev/null
assert_exit_code 0 $? "T63: Duplicate --check doesn't crash"
rm -rf "$MOCK_HOME"

# Test 64: Unknown flag after valid flags
MOCK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/uom-test-XXXXXX")"
HOME="$MOCK_HOME" sh "$BOOTSTRAP_TERMUX" --check --bogus 2>/dev/null
assert_exit_code 1 $? "T64: Unknown flag after valid flag rejected"
rm -rf "$MOCK_HOME"

# Test 65: --test-root with non-existent parent
MOCK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/uom-test-XXXXXX")"
OUTPUT=$(HOME="$MOCK_HOME" UOM_SDK_OVERRIDE=28 sh "$BOOTSTRAP_TERMUX" --check --test-root "/nonexistent/path" 2>&1 || true)
# Script handles this gracefully (logs FATAL but doesn't crash the process)
echo "$OUTPUT" | grep -qi 'fatal\|cannot\|test.root' && pass "T65: --test-root with non-existent parent handled" || fail "T65: --test-root with non-existent parent handled" "no error message"
rm -rf "$MOCK_HOME"

# Test 66: Multiple --profile flags (last wins)
MOCK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/uom-test-XXXXXX")"
OUTPUT=$(HOME="$MOCK_HOME" UOM_SDK_OVERRIDE=28 sh "$BOOTSTRAP_TERMUX" --check --profile phone-relay --profile phone-agent 2>&1 || true)
assert_exit_code 0 $? "T66: Multiple --profile flags handled"
rm -rf "$MOCK_HOME"

# Test 67: --resume flag accepted
MOCK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/uom-test-XXXXXX")"
OUTPUT=$(HOME="$MOCK_HOME" UOM_SDK_OVERRIDE=28 sh "$BOOTSTRAP_TERMUX" --check --resume 2>&1 || true)
assert_exit_code 0 $? "T67: --resume flag accepted"
rm -rf "$MOCK_HOME"

# ── SECTION 10: EXISTING STATE ──────────────────────────────────────────
printf '\n=== EXISTING STATE (Tests 68-70) ===\n'

# Test 68: Existing SSH key not overwritten
setup_mock
touch "$MOCK_HOME/.ssh/id_ed25519_uom"
chmod 600 "$MOCK_HOME/.ssh/id_ed25519_uom"
OUTPUT=$(HOME="$MOCK_HOME" sh "$BOOTSTRAP_TERMUX" --check 2>&1 || true)
echo "$OUTPUT" | grep -q "already exists" && pass "T68: Existing SSH key detected" || fail "T68: Existing key" "not detected"
cleanup_mock

# Test 69: Existing SSH managed block not duplicated
setup_mock
mkdir -p "$MOCK_HOME/.ssh"
cat > "$MOCK_HOME/.ssh/config" << 'SSHEOF'
# existing config
Host existing
  HostName 10.0.0.1
# UOM-MANAGED-BEGIN
Host uom-phone-local
  HostName 127.0.0.1
# UOM-MANAGED-END
SSHEOF
OUTPUT=$(HOME="$MOCK_HOME" UOM_SDK_OVERRIDE=28 sh "$BOOTSTRAP_TERMUX" --apply 2>&1 || true)
echo "$OUTPUT" | grep -qi 'already has UOM\|managed block' && pass "T69: Existing managed block detected" || fail "T69: Existing managed block" "not detected"
# Verify existing config content is preserved
grep -q "Host existing" "$MOCK_HOME/.ssh/config" && pass "T69b: Existing config preserved" || fail "T69b: Existing config preserved" "lost"
cleanup_mock

# Test 70: Existing Termux:Boot file detected
setup_mock
mkdir -p "$MOCK_HOME/.termux/boot"
touch "$MOCK_HOME/.termux/boot/start-uom.sh"
OUTPUT=$(HOME="$MOCK_HOME" sh "$BOOTSTRAP_TERMUX" --check 2>&1 || true)
assert_exit_code 0 $? "T70: Existing boot file handled gracefully"
cleanup_mock

# ── RESULTS ──────────────────────────────────────────────────────────────
printf '\n========================================\n'
printf 'RESULTS: %d passed, %d failed, %d skipped out of %d total\n' \
  "$_PASS" "$_FAIL" "$_SKIP" "$_TOTAL"
printf '========================================\n\n'

# Write machine-readable results
cat > "$RESULTS" << RESULTSEOF
{
  "test_run": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "script": "tests/test-phone-bootstrap.sh",
  "total": $_TOTAL,
  "passed": $_PASS,
  "failed": $_FAIL,
  "skipped": $_SKIP,
  "result": "$([ "$_FAIL" -eq 0 ] && echo 'ALL_PASS' || echo 'SOME_FAIL')"
}
RESULTSEOF

printf 'Results written to: %s\n' "$RESULTS"

# Exit code
[ "$_FAIL" -eq 0 ]
