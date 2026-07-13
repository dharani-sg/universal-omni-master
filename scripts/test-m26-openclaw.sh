#!/bin/sh
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PASS=0; FAIL=0
_c() { [ "$2" = "$3" ] && { printf '  PASS %-52s = %s\n' "$1" "$3"; PASS=$((PASS+1)); } || { printf '  FAIL %-52s want=%s got=%s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); }; }

echo "=== M26 OpenClaw Telemetry Tests ==="
sh -n "$ROOT/src/saas/openclaw.sh" && _c "syntax: openclaw.sh" ok ok || _c "syntax: openclaw.sh" ok fail
sh -n "$ROOT/bin/omni-openclaw" && _c "syntax: omni-openclaw" ok ok || _c "syntax: omni-openclaw" ok fail

. "$ROOT/src/saas/openclaw.sh"

WORK="${TMPDIR:-/tmp}/omni-m26-$$"
mkdir -p "$WORK"
export OMNI_TELEMETRY_DIR="$WORK"

cat > "$WORK/meter.ndjson" << 'NDJSON'
{"ts":"2026-01-01T00:00:00Z","event":"deploy_success"}
{"ts":"2026-01-01T00:01:00Z","event":"ai_patch_query"}
{"ts":"2026-01-01T00:02:00Z","event":"ai_patch_query"}
NDJSON

cat > "$WORK/compliance.ndjson" << 'NDJSON'
{"ts":"2026-01-01T00:00:00Z","action":"enforce_sshd","rule":"PermitRootLogin","value":"no"}
NDJSON

# 1. Payload generation
_payload=$(openclaw_generate_payload)
echo "$_payload" | grep -q '"ai_patches_applied": 2' && _c "payload counts AI patches" yes yes || _c "payload counts AI patches" yes no
echo "$_payload" | grep -q '"successful_deployments": 1' && _c "payload counts deployments" yes yes || _c "payload counts deployments" yes no
echo "$_payload" | grep -q '"compliance_enforcements": 1' && _c "payload counts compliance" yes yes || _c "payload counts compliance" yes no

# 2. Sync with mock curl
mkdir -p "$WORK/bin"
_curl_log="${TMPDIR:-/tmp}/omni-m26-curl-args-$$.txt"
cat > "$WORK/bin/curl" << MOCK_CURL
#!/bin/sh
printf '%s\n' "\$*" > "$_curl_log"
exit 0
MOCK_CURL
chmod +x "$WORK/bin/curl"
OLDPATH="$PATH"
PATH="$WORK/bin:$PATH"
export PATH

rc=0; openclaw_sync >/dev/null 2>&1 || rc=$?
_c "sync executes successfully" 0 "$rc"
_c "sync invokes curl with endpoint" yes "$(grep -q 'api.openclaw.local' "$_curl_log" 2>/dev/null && echo yes || echo no)"

PATH="$OLDPATH"
export PATH

# 3. OMNI_SYSROOT guard
rc=0; OMNI_SYSROOT=/tmp/fx openclaw_sync >/dev/null 2>&1 || rc=$?
_c "sync guarded by OMNI_SYSROOT" 126 "$rc"

# 4. CLI help
rc=0; "$ROOT/bin/omni-openclaw" help >/dev/null 2>&1 || rc=$?
_c "cli help exits 0" 0 "$rc"

# 5. CLI unknown command
rc=0; "$ROOT/bin/omni-openclaw" bogus >/dev/null 2>&1 || rc=$?
_c "cli unknown exits 2" 2 "$rc"

# 6. Empty telemetry dir
rm -f "$WORK/meter.ndjson" "$WORK/compliance.ndjson"
_empty_payload=$(openclaw_generate_payload)
echo "$_empty_payload" | grep -q '"ai_patches_applied": 0' && _c "empty dir yields zero counts" yes yes || _c "empty dir yields zero counts" yes no

rm -rf "$WORK" "$_curl_log"

printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
