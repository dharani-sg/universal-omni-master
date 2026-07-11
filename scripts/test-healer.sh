#!/bin/sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
check() {
    if [ "$2" = "$3" ]; then printf '  PASS %-45s = %s\n' "$1" "$3"; PASS=$((PASS+1))
    else printf '  FAIL %-45s want=%s got=%s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); fi
}

echo "=== M8 Healer Module Tests ==="
for f in "$ROOT"/src/healer/*.sh "$ROOT/bin/omni-healer"; do
    sh -n "$f" && check "syntax: $(basename "$f")" ok ok || check "syntax: $(basename "$f")" ok fail
done

. "$ROOT/src/core/logging.sh" 2>/dev/null
. "$ROOT/src/healer/common.sh"

# Backoff: clamped doubling, no bash-isms
check "backoff(0) = base(5)"   "5"  "$(healer_backoff 0)"
check "backoff(2) = 20"        "20" "$(healer_backoff 2)"
check "backoff(99) clamps 60"  "60" "$(healer_backoff 99)"

# JSON escaping: quotes/backslashes must not break the record
_log="/tmp/omni-audit-test-$$.json"
HEALER_AUDIT_LOG="$_log" healer_emit "t" "e" 'msg with "quotes" and \slash'
grep -q '\\"quotes\\"' "$_log" && check "json escaping quotes" yes yes || check "json escaping quotes" yes no
rm -f "$_log"

# Status when not running exits 1
rc=0; "$ROOT/bin/omni-healer" status >/dev/null 2>&1 || rc=$?
check "status not-running rc=1" "1" "$rc"

# Unknown command exits 2
rc=0; "$ROOT/bin/omni-healer" bogus >/dev/null 2>&1 || rc=$?
check "unknown cmd rc=2" "2" "$rc"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

echo; echo "=== L12 regression: dmesg follow-capability detection ==="
. "$ROOT/src/healer/storage.sh" 2>/dev/null
grep -q "_dmesg_has_follow" "$ROOT/src/healer/storage.sh" && \
    check "storage.sh has capability detection" yes yes || check "storage.sh has capability detection" yes no
grep -q "poll-diff" "$ROOT/src/healer/storage.sh" && \
    check "storage.sh has poll fallback" yes yes || check "storage.sh has poll fallback" yes no
