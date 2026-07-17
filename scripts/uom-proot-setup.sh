#!/bin/sh
# scripts/uom-proot-setup.sh — Cloud-only environment verification
# Checks: curl, jq, internet access to Pollinations.ai API.
# 100% user-space. No sudo. No root. No local LLM.
#
# Usage: sh scripts/uom-proot-setup.sh [--force]

set -u

UOM_DIR="$(cd "$(dirname "$0")/.." && pwd)"
API_BASE="https://text.pollinations.ai"
SETUP_META="${UOM_DIR}/.uom-agent/setup-env.json"
FORCE="${1:-}"
RETRY_DELAY=10
MAX_RETRIES=3

GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; NC="\033[0m"
_pass() { printf '  %s✓%s %s\n' "$GREEN" "$NC" "$1"; }
_warn() { printf '  %s!%s %s\n' "$YELLOW" "$NC" "$1"; }
_fail() { printf '  %s✗%s %s\n' "$RED" "$NC" "$1"; }

# ── Platform detection ──────────────────────────────────────────────────
IS_TERMUX=0
if [ -d "/data/data/com.termux" ] || [ -n "${ANDROID_ROOT:-}" ]; then
    IS_TERMUX=1
fi

printf '\n═══ UOM CLOUD ENVIRONMENT SETUP ═══\n'
if [ "$IS_TERMUX" -eq 1 ]; then
    printf 'Platform: Termux/Android\n'
else
    printf 'Platform: Linux (%s)\n' "$(uname -m 2>/dev/null || echo unknown)"
fi
printf '\n'

# ── Step 1: Ensure curl ────────────────────────────────────────────────
if command -v curl >/dev/null 2>&1; then
    _pass "curl: $(curl --version 2>/dev/null | head -1)"
else
    _warn "curl not found — attempting install..."
    if [ "$IS_TERMUX" -eq 1 ] && command -v pkg >/dev/null 2>&1; then
        pkg install -y curl >/dev/null 2>&1 && _pass "curl installed via pkg" \
            || { _fail "curl install failed — install manually: pkg install curl"; exit 1; }
    else
        _fail "curl not found — install manually for your platform"
        exit 1
    fi
fi

# ── Step 2: Ensure jq ──────────────────────────────────────────────────
if command -v jq >/dev/null 2>&1; then
    _pass "jq: $(jq --version 2>/dev/null)"
else
    _warn "jq not found — attempting install..."
    if [ "$IS_TERMUX" -eq 1 ] && command -v pkg >/dev/null 2>&1; then
        pkg install -y jq >/dev/null 2>&1 && _pass "jq installed via pkg" \
            || { _fail "jq install failed — install manually: pkg install jq"; exit 1; }
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache jq >/dev/null 2>&1 && _pass "jq installed via apk" \
            || { _fail "jq install failed"; exit 1; }
    else
        _fail "jq not found — install manually for your platform"
        exit 1
    fi
fi

# ── Step 3: Test API connectivity with graceful retry ──────────────────
printf '\n'
printf 'Testing API endpoint: %s\n' "$API_BASE"

_api_ok=0
_retry=0
while [ "$_retry" -lt "$MAX_RETRIES" ]; do
    # Lightweight GET — the API echoes back a small response for any prompt
    _status=$(curl -sS -o /dev/null -w '%{http_code}' \
        --max-time 15 \
        "${API_BASE}/hello" 2>/dev/null || echo "000")

    if [ "$_status" = "200" ] || [ "$_status" = "201" ] || [ "$_status" = "204" ]; then
        _pass "API reachable (HTTP ${_status})"
        _api_ok=1
        break
    fi

    _retry=$((_retry + 1))
    if [ "$_retry" -lt "$MAX_RETRIES" ]; then
        _warn "API returned HTTP ${_status} — retry ${_retry}/${MAX_RETRIES} in ${RETRY_DELAY}s"
        sleep "$RETRY_DELAY"
    fi
done

if [ "$_api_ok" -eq 0 ]; then
    _fail "API unreachable after ${MAX_RETRIES} attempts"
    printf '\n'
    printf 'Possible causes:\n'
    printf '  - No internet connection\n'
    printf '  - DNS resolution failure\n'
    printf '  - Firewall blocking outbound HTTPS\n'
    printf '  - API endpoint temporarily down\n'
    printf '\n'
    printf 'The Zen loop agents will use stub mode as fallback.\n'
    printf 'Re-run this script when connectivity is restored.\n'
fi

# ── Step 4: Test POST pipeline (dry-run) ───────────────────────────────
printf '\n'
printf 'Testing POST pipeline (dry-run)...'

_dry_payload=$(jq -n '{messages:[{role:"user",content:"Reply with exactly: OK"}]}')
_dry_response=$(curl -sS --max-time 30 \
    -X POST "${API_BASE}/" \
    -H "Content-Type: application/json" \
    -d "$_dry_payload" 2>/dev/null || echo "")

if printf '%s' "$_dry_response" | grep -qi 'ok'; then
    _pass "POST pipeline functional"
else
    _warn "POST response unexpected (may still work with longer prompts)"
    _warn "Response preview: $(printf '%s' "$_dry_response" | head -1 | cut -c1-80)"
fi

# ── Step 5: Android resource check (informational) ─────────────────────
if [ "$IS_TERMUX" -eq 1 ] && [ -f /proc/meminfo ]; then
    printf '\n'
    _mem_avail=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null || echo "0")
    _mem_mb=$((_mem_avail / 1024))
    if [ "${_mem_avail:-0}" -lt 307200 ] 2>/dev/null; then
        _warn "Low memory: ${_mem_mb}MB — close heavy apps before launching agents"
    else
        _pass "Memory OK: ${_mem_mb}MB available"
    fi
fi

# ── Record setup metadata ──────────────────────────────────────────────
mkdir -p "${UOM_DIR}/.uom-agent"
cat > "$SETUP_META" << EOF
{
  "mode": "cloud-only",
  "api_base": "${API_BASE}",
  "api_status": "$([ "$_api_ok" -eq 1 ] && echo "reachable" || echo "unreachable")",
  "platform": "$([ "$IS_TERMUX" -eq 1 ] && echo "termux" || echo "linux")",
  "curl_version": "$(curl --version 2>/dev/null | head -1 || echo "unknown")",
  "jq_version": "$(jq --version 2>/dev/null || echo "unknown")",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)"
}
EOF
_pass "Metadata recorded at ${SETUP_META}"

printf '\n═══ SETUP COMPLETE ═══\n'
if [ "$_api_ok" -eq 0 ]; then
    printf '\n%sWARNING:%s API unreachable — agents will use stub fallback.\n' "$YELLOW" "$NC"
fi
printf '\n'
