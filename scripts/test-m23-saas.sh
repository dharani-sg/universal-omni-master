#!/bin/sh
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PASS=0
FAIL=0

_c() {
    if [ "$2" = "$3" ]; then
        printf '  PASS %-55s = %s\n' "$1" "$3"
        PASS=$((PASS + 1))
    else
        printf '  FAIL %-55s want=%s got=%s\n' "$1" "$2" "$3"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== M23.1 SaaS Tier Switching Tests ==="

sh -n "$ROOT/src/saas/meter.sh" && _c "syntax: meter.sh" ok ok || _c "syntax: meter.sh" ok fail
sh -n "$ROOT/bin/omni-saas" && _c "syntax: omni-saas" ok ok || _c "syntax: omni-saas" ok fail

. "$ROOT/src/saas/meter.sh"

WORK="${TMPDIR:-/tmp}/omni-m231-$$"
MOCK="$WORK/bin"
mkdir -p "$MOCK"
export OMNI_SAAS_CACHE="$WORK/cache"
export OMNI_SAAS_ENDPOINT="http://mock.local/v1"
export PATH="$MOCK:$PATH"

# Trial active from backend
cat > "$MOCK/curl" << 'CURL_TRIAL'
#!/bin/sh
case "$*" in
    */validate*) printf '{"valid":true,"tier":"trial","expiry":9999999999,"credits":0,"usage_count":3,"usage_window":"trial"}\n' ;;
    */meter*) exit 0 ;;
esac
CURL_TRIAL
chmod +x "$MOCK/curl"

rc=0
saas_check_license "TRIAL-KEY" >/dev/null 2>&1 || rc=$?
_c "trial active returns 0" 0 "$rc"
_c "trial cached as tier=trial" trial "$(_saas_cache_get tier)"

# Trial expired offline
rm -f "$MOCK/curl"
mkdir -p "$OMNI_SAAS_CACHE"
cat > "$OMNI_SAAS_CACHE/license.cache" << CACHE
ts=$(date +%s)
tier=trial
expiry=1000000000
credits=0
usage_count=0
usage_window=trial
CACHE

rc=0
saas_check_license "TRIAL-KEY" >/dev/null 2>&1 || rc=$?
_c "trial expired offline returns 1" 1 "$rc"

# Pay per use active from backend
cat > "$MOCK/curl" << 'CURL_PPU'
#!/bin/sh
case "$*" in
    */validate*) printf '{"valid":true,"tier":"pay_per_use","expiry":0,"credits":50,"usage_count":8,"usage_window":"metered"}\n' ;;
    */meter*) exit 0 ;;
esac
CURL_PPU
chmod +x "$MOCK/curl"

rc=0
saas_check_license "PPU-KEY" >/dev/null 2>&1 || rc=$?
_c "pay_per_use active returns 0" 0 "$rc"
_c "pay_per_use cached tier" pay_per_use "$(_saas_cache_get tier)"
_c "pay_per_use cached credits" 50 "$(_saas_cache_get credits)"

# Pay per use exhausted offline
rm -f "$MOCK/curl"
cat > "$OMNI_SAAS_CACHE/license.cache" << CACHE
ts=$(date +%s)
tier=pay_per_use
expiry=0
credits=0
usage_count=9
usage_window=metered
CACHE

rc=0
saas_check_license "PPU-KEY" >/dev/null 2>&1 || rc=$?
_c "pay_per_use exhausted offline returns 1" 1 "$rc"

# subscription weekly valid offline
cat > "$OMNI_SAAS_CACHE/license.cache" << CACHE
ts=$(date +%s)
tier=subscription_weekly
expiry=9999999999
credits=0
usage_count=10
usage_window=weekly
CACHE

rc=0
saas_check_license "SUB-WEEK" >/dev/null 2>&1 || rc=$?
_c "subscription_weekly offline returns 0" 0 "$rc"

# subscription monthly valid offline
cat > "$OMNI_SAAS_CACHE/license.cache" << CACHE
ts=$(date +%s)
tier=subscription_monthly
expiry=9999999999
credits=0
usage_count=11
usage_window=monthly
CACHE

rc=0
saas_check_license "SUB-MONTH" >/dev/null 2>&1 || rc=$?
_c "subscription_monthly offline returns 0" 0 "$rc"

# Momentary switch: cached trial, backend returns pay_per_use
cat > "$OMNI_SAAS_CACHE/license.cache" << CACHE
ts=$(date +%s)
tier=trial
expiry=9999999999
credits=0
usage_count=0
usage_window=trial
CACHE

cat > "$MOCK/curl" << 'CURL_SWITCH'
#!/bin/sh
case "$*" in
    */validate*) printf '{"valid":true,"tier":"pay_per_use","expiry":0,"credits":100,"usage_count":12,"usage_window":"metered"}\n' ;;
    */meter*) exit 0 ;;
esac
CURL_SWITCH
chmod +x "$MOCK/curl"

rc=0
saas_check_license "SWITCH" >/dev/null 2>&1 || rc=$?
_c "momentary switch returns 0" 0 "$rc"
_c "momentary switch updates tier" pay_per_use "$(_saas_cache_get tier)"
_c "momentary switch updates credits" 100 "$(_saas_cache_get credits)"

# status command
_status=$("$ROOT/bin/omni-saas" status)
printf '%s\n' "$_status" | grep -q '^tier=pay_per_use$'
_c "status prints tier" 0 "$?"
printf '%s\n' "$_status" | grep -q '^credits=100$'
_c "status prints credits" 0 "$?"

# usage_count increments and pay_per_use credit decrements on deploy_success
saas_meter_event "deploy_success" >/dev/null 2>&1
_c "meter increments usage_count" 13 "$(_saas_cache_get usage_count)"
_c "meter decrements pay_per_use credits" 99 "$(_saas_cache_get credits)"

# manual consume-credit
saas_consume_credit >/dev/null 2>&1
_c "manual consume-credit decrements" 98 "$(_saas_cache_get credits)"

# OMNI_SYSROOT prevents cache writes
rm -f "$OMNI_SAAS_CACHE/license.cache"
cat > "$MOCK/curl" << 'CURL_VALID'
#!/bin/sh
printf '{"valid":true,"tier":"trial","expiry":9999999999,"credits":0,"usage_count":0,"usage_window":"trial"}\n'
CURL_VALID
chmod +x "$MOCK/curl"

OMNI_SYSROOT=/tmp/fx saas_check_license "NO-CACHE" >/dev/null 2>&1
_c "OMNI_SYSROOT prevents license cache write" no "$([ -f "$OMNI_SAAS_CACHE/license.cache" ] && echo yes || echo no)"

rm -f "$OMNI_SAAS_CACHE/meter.ndjson"
OMNI_SYSROOT=/tmp/fx saas_meter_event "fixture_event" >/dev/null 2>&1
_c "OMNI_SYSROOT prevents meter log write" no "$([ -f "$OMNI_SAAS_CACHE/meter.ndjson" ] && echo yes || echo no)"

# CLI tests
cat > "$OMNI_SAAS_CACHE/license.cache" << CACHE
ts=$(date +%s)
tier=subscription_monthly
expiry=9999999999
credits=0
usage_count=20
usage_window=monthly
CACHE

rc=0
"$ROOT/bin/omni-saas" help >/dev/null 2>&1 || rc=$?
_c "cli help exits 0" 0 "$rc"

rc=0
"$ROOT/bin/omni-saas" bogus >/dev/null 2>&1 || rc=$?
_c "cli unknown exits 2" 2 "$rc"

_status=$("$ROOT/bin/omni-saas" status)
printf '%s\n' "$_status" | grep -q '^tier=subscription_monthly$'
_c "cli status shows subscription tier" 0 "$?"

rm -rf "$WORK"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
