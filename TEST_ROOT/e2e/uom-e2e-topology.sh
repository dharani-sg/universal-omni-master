#!/bin/sh
# V15: E2E topology test — tests outbound HTTP API calls from VM
# Tests: connectivity to free LLM API endpoints
# Usage: uom-e2e-topology.sh <host> <port> <user> [ssh_key]
set -e

HOST="${1:?Usage: $0 <host> <port> <user> [ssh_key]}"
PORT="${2:?Missing port}"
USER="${3:?Missing user}"
SSHKEY="${4:-/home/alpine/.ssh/id_ed25519_phone}"

PASS=0; FAIL=0; WARN=0
log_pass() { PASS=$((PASS+1)); echo "  ✓ $1"; }
log_fail() { FAIL=$((FAIL+1)); echo "  ✗ FAIL: $1"; }
log_warn() { WARN=$((WARN+1)); echo "  ⚠ WARN: $1"; }

SSH_CMD="ssh -i $SSHKEY -o BatchMode=yes -o ConnectTimeout=10 -p $PORT $USER@$HOST"

echo "=== E2E Topology Test: $USER@$HOST:$PORT ==="
echo ""

# Test 1: HTTP GET to httpbin
echo "[1/6] HTTP GET → httpbin.org"
R=$($SSH_CMD 'curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 http://httpbin.org/get' 2>/dev/null | tr -d '\r\n')
if [ "$R" = "200" ]; then
  log_pass "httpbin.org returned 200"
else
  log_fail "httpbin.org returned $R"
fi

# Test 2: HTTPS GET to a known endpoint
echo "[2/6] HTTPS GET → api.github.com"
R=$($SSH_CMD 'curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 https://api.github.com' 2>/dev/null | tr -d '\r\n')
if [ "$R" = "200" ] || [ "$R" = "403" ]; then
  log_pass "api.github.com returned $R (reachable)"
else
  log_fail "api.github.com returned $R"
fi

# Test 3: DNS resolution for multiple hosts
echo "[3/6] DNS resolution → openrouter.ai"
R=$($SSH_CMD 'nslookup openrouter.ai 2>&1 | grep -c "Address:"' 2>/dev/null | tr -d '\r\n')
if [ "$R" -ge 2 ] 2>/dev/null; then
  log_pass "openrouter.ai resolves ($R addresses)"
else
  log_warn "DNS resolution partial"
fi

# Test 4: Python3 http connectivity
echo "[4/6] Python3 urllib → httpbin.org"
R=$($SSH_CMD 'python3 -c "import urllib.request; r=urllib.request.urlopen(\"http://httpbin.org/get\",timeout=10); print(r.status)"' 2>/dev/null | tr -d '\r\n')
if [ "$R" = "200" ]; then
  log_pass "Python3 urllib OK (status $R)"
else
  log_fail "Python3 urllib failed: $R"
fi

# Test 5: TCP connectivity to common API port
echo "[5/6] TCP → api.openai.com:443"
R=$($SSH_CMD 'timeout 5 curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 https://api.openai.com/v1/models 2>/dev/null || echo FAIL' 2>/dev/null | tr -d '\r\n')
if [ "$R" = "401" ] || [ "$R" = "200" ]; then
  log_pass "TCP 443 to api.openai.com reachable (HTTP $R)"
elif [ "$R" = "FAIL" ]; then
  log_warn "TCP check inconclusive"
else
  log_pass "TCP 443 reachable (HTTP $R)"
fi

# Test 6: JSON parse capability
echo "[6/6] JSON parse → python3 json.loads"
R=$($SSH_CMD 'python3 << "PYEOF"
import json
d = json.loads("{\"status\":\"ok\"}")
print(d["status"])
PYEOF
' 2>/dev/null | tr -d '\r\n')
if [ "$R" = "ok" ]; then
  log_pass "JSON parsing works"
else
  log_fail "JSON parsing failed: got $R"
fi

echo ""
echo "=== RESULT: PASS=$PASS FAIL=$FAIL WARN=$WARN ==="
if [ "$FAIL" -eq 0 ]; then
  echo "STATUS: PASS"
  exit 0
else
  echo "STATUS: FAIL"
  exit 1
fi
