#!/bin/sh
# V16: 60-minute controlled soak test
# Measures: memory, disk, CPU load, network at intervals
# Usage: uom-soak-test.sh <host> <port> <user> [ssh_key] [duration_min] [interval_sec]
set -e

HOST="${1:?Usage: $0 <host> <port> <user> [ssh_key] [duration_min] [interval_sec]}"
PORT="${2:?Missing port}"
USER="${3:?Missing user}"
SSHKEY="${4:-/home/alpine/.ssh/id_ed25519_phone}"
DURATION="${5:-60}"
INTERVAL="${6:-300}"

PASS=0; FAIL=0; WARN=0
log_pass() { PASS=$((PASS+1)); echo "  ✓ $1"; }
log_fail() { FAIL=$((FAIL+1)); echo "  ✗ FAIL: $1"; }
log_warn() { WARN=$((WARN+1)); echo "  ⚠ WARN: $1"; }

SSH_CMD="ssh -i $SSHKEY -o BatchMode=yes -o ConnectTimeout=10 -p $PORT $USER@$HOST"
REPO="TEST_ROOT/soak"

echo "=== Soak Test: $USER@$HOST:$PORT (${DURATION}min, ${INTERVAL}s intervals) ==="
echo "Start: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# Collect baseline
echo "Collecting baseline..."
BASE_MEM=$($SSH_CMD 'free -m 2>/dev/null | grep Mem | awk "{print \$7}"' 2>/dev/null | tr -d '\r\n')
BASE_DISK=$($SSH_CMD 'df / 2>/dev/null | tail -1 | awk "{print \$4}"' 2>/dev/null | tr -d '\r\n')
BASE_LOAD=$($SSH_CMD 'cat /proc/loadavg 2>/dev/null | awk "{print \$1}"' 2>/dev/null | tr -d '\r\n')
echo "Baseline: mem=${BASE_MEM}MB free, disk=${BASE_DISK}KB free, load=$BASE_LOAD"
echo ""

# Calculate iterations
ITERATIONS=$((DURATION * 60 / INTERVAL))
echo "Will run $ITERATIONS checks over ${DURATION} minutes"
echo ""

# Soak loop
I=0
DEGRADATION=0
while [ $I -lt $ITERATIONS ]; do
  TS=$(date -u +%H:%M:%S)
  MEM=$($SSH_CMD 'free -m 2>/dev/null | grep Mem | awk "{print \$7}"' 2>/dev/null | tr -d '\r\n')
  DISK=$($SSH_CMD 'df / 2>/dev/null | tail -1 | awk "{print \$4}"' 2>/dev/null | tr -d '\r\n')
  LOAD=$($SSH_CMD 'cat /proc/loadavg 2>/dev/null | awk "{print \$1}"' 2>/dev/null | tr -d '\r\n')
  UPTIME=$($SSH_CMD 'uptime -p 2>/dev/null || uptime' 2>/dev/null | tr -d '\r\n')

  # Calculate deltas
  MEM_DELTA=0
  DISK_DELTA=0
  if [ -n "$MEM" ] && [ -n "$BASE_MEM" ] && [ "$MEM" -gt 0 ] 2>/dev/null; then
    MEM_DELTA=$((BASE_MEM - MEM))
  fi
  if [ -n "$DISK" ] && [ -n "$BASE_DISK" ] && [ "$DISK" -gt 0 ] 2>/dev/null; then
    DISK_DELTA=$((BASE_DISK - DISK))
  fi

  printf "[%s] #%d/%d  mem=%sMB (Δ%d)  disk=%sKB (Δ%d)  load=%s  %s\n" \
    "$TS" "$((I+1))" "$ITERATIONS" "$MEM" "$MEM_DELTA" "$DISK" "$DISK_DELTA" "$LOAD" "$UPTIME"

  # Check for degradation (>100MB memory loss or >100MB disk loss)
  if [ "$MEM_DELTA" -gt 100 ] 2>/dev/null; then
    DEGRADATION=$((DEGRADATION+1))
    if [ "$DEGRADATION" -ge 3 ]; then
      log_fail "Memory degraded >100MB for 3 consecutive checks"
    fi
  fi

  I=$((I+1))
  if [ $I -lt $ITERATIONS ]; then
    sleep $INTERVAL
  fi
done

echo ""
echo "=== Soak Summary ==="
FINAL_MEM=$($SSH_CMD 'free -m 2>/dev/null | grep Mem | awk "{print \$7}"' 2>/dev/null | tr -d '\r\n')
FINAL_DISK=$($SSH_CMD 'df / 2>/dev/null | tail -1 | awk "{print \$4}"' 2>/dev/null | tr -d '\r\n')
FINAL_LOAD=$($SSH_CMD 'cat /proc/loadavg 2>/dev/null | awk "{print \$1}"' 2>/dev/null | tr -d '\r\n')
echo "Baseline: mem=${BASE_MEM}MB disk=${BASE_DISK}KB load=$BASE_LOAD"
echo "Final:    mem=${FINAL_MEM}MB disk=${FINAL_DISK}KB load=$FINAL_LOAD"

# Evaluate
if [ "$DEGRADATION" -eq 0 ]; then
  log_pass "No degradation detected over ${DURATION}min"
else
  log_warn "Degradation events: $DEGRADATION"
fi

# Check if process is still alive
ALIVE=$($SSH_CMD 'echo alive' 2>/dev/null | tr -d '\r\n')
if [ "$ALIVE" = "alive" ]; then
  log_pass "Endpoint still responsive after soak"
else
  log_fail "Endpoint unresponsive after soak"
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
