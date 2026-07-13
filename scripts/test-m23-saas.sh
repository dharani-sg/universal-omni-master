#!/bin/sh
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PASS=0
FAIL=0

_c() {
    if [ "$2" = "$3" ]; then
        printf '  PASS %-52s = %s\n' "$1" "$3"
        PASS=$((PASS+1))
    else
        printf '  FAIL %-52s want=%s got=%s\n' "$1" "$2" "$3"
        FAIL=$((FAIL+1))
    fi
}

echo "=== M23 SaaS Metering Tests ==="

sh -n "$ROOT/src/saas/meter.sh" && _c "syntax: meter.sh" ok ok || _c "syntax: meter.sh" ok fail
sh -n "$ROOT/bin/omni-saas" && _c "syntax: omni-saas" ok ok || _c "syntax: omni-saas" ok fail

. "$ROOT/src/saas/meter.sh"

WORK="${TMPDIR:-/tmp}/omni-m23-$$"
MOCK="$WORK/bin"
mkdir -p "$MOCK"
export OMNI_SAAS_CACHE="$WORK/cache"
export OMNI_SAAS_ENDPOINT="http://mock.local/v1"
export PATH="$MOCK:$PATH"

cat > "$MOCK/curl" << 'CURL_VALID'
#!/bin/sh
case "$*" in
    */validate*) printf '{"valid": true}\n' ;;
    */meter*) exit 0 ;;
esac
CURL_VALID
chmod +x "$MOCK/curl"

rc=0
saas_check_license "GOOD-KEY" >/dev/null 2>&1 || rc=$?
_c "valid license returns 0" 0 "$rc"
_c "valid license writes cache" yes "$([ -f "$OMNI_SAAS_CACHE/license.cache" ] && echo yes || echo no)"

cat > "$MOCK/curl" << 'CURL_INVALID'
#!/bin/sh
case "$*" in
    */validate*) printf '{"valid": false}\n' ;;
esac
CURL_INVALID
chmod +x "$MOCK/curl"
rm -f "$OMNI_SAAS_CACHE/license.cache"

rc=0
saas_check_license "BAD-KEY" >/dev/null 2>&1 || rc=$?
_c "invalid license returns 1" 1 "$rc"

mkdir -p "$OMNI_SAAS_CACHE"
echo $(( $(date +%s) - 3600 )) > "$OMNI_SAAS_CACHE/license.cache"

rc=0
saas_check_license "OFFLINE" >/dev/null 2>&1 || rc=$?
_c "offline grace returns 0" 0 "$rc"

rm -f "$OMNI_SAAS_CACHE/license.cache"
cat > "$MOCK/curl" << 'CURL_VALID2'
#!/bin/sh
printf '{"valid": true}\n'
CURL_VALID2
chmod +x "$MOCK/curl"

OMNI_SYSROOT=/tmp/fx saas_check_license "NO-CACHE" >/dev/null 2>&1
_c "OMNI_SYSROOT prevents cache write" no "$([ -f "$OMNI_SAAS_CACHE/license.cache" ] && echo yes || echo no)"

saas_meter_event "deploy_success" >/dev/null 2>&1
_c "meter event logs locally" yes "$(grep -q 'deploy_success' "$OMNI_SAAS_CACHE/meter.ndjson" 2>/dev/null && echo yes || echo no)"

rc=0
OMNI_SYSROOT=/tmp/fx saas_meter_event "fixture_event" >/dev/null 2>&1 || rc=$?
_c "meter event under OMNI_SYSROOT returns 0" 0 "$rc"

rc=0
"$ROOT/bin/omni-saas" help >/dev/null 2>&1 || rc=$?
_c "cli help exits 0" 0 "$rc"

rc=0
"$ROOT/bin/omni-saas" bogus >/dev/null 2>&1 || rc=$?
_c "cli unknown exits 2" 2 "$rc"

rm -rf "$WORK"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
