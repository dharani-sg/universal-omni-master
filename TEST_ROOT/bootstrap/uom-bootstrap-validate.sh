#!/bin/sh
# V14: Bootstrap validation — checks core infrastructure on any endpoint
# Usage: uom-bootstrap-validate.sh <host> <port> <user> [ssh_key]
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
echo "=== Bootstrap Validation: $USER@$HOST:$PORT ==="
echo ""

# 1. SSH connectivity
echo "[1/10] SSH connectivity"
if $SSH_CMD 'echo ok' >/dev/null 2>&1; then
  log_pass "SSH reachable"
else
  log_fail "SSH unreachable — aborting"
  echo "RESULT: FAIL ($FAIL failures)"
  exit 1
fi

# 2. Kernel version
echo "[2/10] Kernel"
KERN=$($SSH_CMD 'uname -r' 2>/dev/null | tr -d '\r\n')
if [ -n "$KERN" ]; then
  log_pass "Kernel $KERN"
else
  log_fail "Cannot read kernel version"
fi

# 3. Disk space
echo "[3/10] Disk space"
DISK=$($SSH_CMD 'df / 2>/dev/null | tail -1 | awk "{print \$4}"' 2>/dev/null | tr -d '\r\n')
if [ -n "$DISK" ] && [ "$DISK" -gt 100000 ] 2>/dev/null; then
  log_pass "Root free: ${DISK}KB"
elif [ -n "$DISK" ]; then
  log_warn "Root free: ${DISK}KB (low)"
else
  log_fail "Cannot read disk space"
fi

# 4. Memory
echo "[4/10] Memory"
MEM=$($SSH_CMD 'free -m 2>/dev/null | grep Mem | awk "{print \$7}"' 2>/dev/null | tr -d '\r\n')
if [ -n "$MEM" ]; then
  log_pass "Available memory: ${MEM}MB"
else
  log_warn "Cannot read memory"
fi

# 5. Python3
echo "[5/10] Python3"
PY=$($SSH_CMD 'python3 --version 2>&1' 2>/dev/null | tr -d '\r\n')
if echo "$PY" | grep -q "Python 3"; then
  log_pass "$PY"
else
  log_warn "python3 not found"
fi

# 6. Network outbound
echo "[6/10] Network outbound"
NET=$($SSH_CMD 'ping -c1 -W5 1.1.1.1 2>&1 | tail -1' 2>/dev/null | tr -d '\r\n')
if echo "$NET" | grep -q "rtt\|time="; then
  log_pass "Outbound OK ($NET)"
else
  log_fail "No outbound network"
fi

# 7. DNS resolution
echo "[7/10] DNS resolution"
DNS=$($SSH_CMD 'nslookup api.openai.com 2>&1 | head -2' 2>/dev/null | tr -d '\r\n')
if echo "$DNS" | grep -q "Address:"; then
  log_pass "DNS OK"
else
  log_warn "DNS may not work"
fi

# 8. Git repo
echo "[8/10] Git repository"
GIT=$($SSH_CMD 'cd ~/src/universal-omni-master && git rev-parse HEAD 2>/dev/null' 2>/dev/null | tr -d '\r\n')
if [ -n "$GIT" ]; then
  log_pass "Git repo at $(echo $GIT | head -c 7)"
else
  log_fail "No git repo at ~/src/universal-omni-master"
fi

# 9. QEMU (if applicable — skip on laptop)
echo "[9/10] QEMU availability"
QEMU=$($SSH_CMD 'which qemu-system-aarch64 2>/dev/null || which qemu-system-x86_64 2>/dev/null || echo none' 2>/dev/null | tr -d '\r\n')
if [ "$QEMU" != "none" ]; then
  log_pass "QEMU: $QEMU"
else
  log_warn "QEMU not available (OK if this is a VM endpoint)"
fi

# 10. uom tools
echo "[10/10] UOM tools"
TOOLS=$($SSH_CMD 'ls ~/src/universal-omni-master/scripts/uom-verifier.sh ~/src/universal-omni-master/scripts/uom-phone-bootstrap.sh 2>/dev/null | wc -l' 2>/dev/null | tr -d '\r\n')
if [ "$TOOLS" -ge 2 ] 2>/dev/null; then
  log_pass "Core UOM tools present"
else
  log_warn "Some UOM tools missing (found $TOOLS)"
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
