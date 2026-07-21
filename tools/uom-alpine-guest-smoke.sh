#!/bin/sh
# tools/uom-alpine-guest-smoke.sh — basic guest health checks
# No eval. One JSON document to stdout. Logs to stderr.
# Exit 0 iff all checks pass.

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
RESULTS=""

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >&2
}

check() {
  _name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    PASS_COUNT=$((PASS_COUNT + 1))
    RESULTS="${RESULTS}{\"check\":\"${_name}\",\"result\":\"PASS\"},"
    log "PASS: $_name"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    RESULTS="${RESULTS}{\"check\":\"${_name}\",\"result\":\"FAIL\"},"
    log "FAIL: $_name"
  fi
}

skip() {
  _name="$1"
  _reason="$2"
  SKIP_COUNT=$((SKIP_COUNT + 1))
  RESULTS="${RESULTS}{\"check\":\"${_name}\",\"result\":\"SKIP\",\"reason\":\"${_reason}\"},"
  log "SKIP: $_name — $_reason"
}

# --- Individual check functions ---

check_disk_usage() {
  _pct=$(df -h / 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
  test "${_pct:-100}" -lt 90
}

check_disk_free() {
  _kfree=$(df / 2>/dev/null | awk 'NR==2{print $4}')
  test "${_kfree:-0}" -gt 1048576
}

check_memory() {
  _mb=$(free -m 2>/dev/null | awk '/Mem:/{print $2}')
  test "${_mb:-0}" -gt 512
}

check_ncpu() {
  _n=$(nproc 2>/dev/null || echo 0)
  test "${_n:-0}" -ge 1
}

check_loopback() {
  ip link show lo | grep -q UP
}

check_sshd() {
  pgrep sshd >/dev/null 2>&1 || pgrep sshd-session >/dev/null 2>&1
}

check_git() {
  git --version >/dev/null
}

check_rsync() {
  rsync --version >/dev/null
}

check_jq() {
  echo '{"a":1}' | jq -e '.a' >/dev/null
}

check_python3() {
  python3 -c "import json; print(1+1)" >/dev/null
}

check_strace() {
  strace -V >/dev/null
}

check_file_util() {
  file /bin/sh >/dev/null
}

check_tmp_write() {
  _f=$(mktemp /tmp/.smoke-test-XXXXXX) && rm -f "$_f"
}

check_home_write() {
  _f=$(mktemp "${HOME:-/tmp}/.smoke-test-XXXXXX") && rm -f "$_f"
}

check_dns() {
  getent hosts google.com >/dev/null
}

# --- Main ---

log "=== Alpine Guest Smoke Test ==="
log "Host: $(hostname) Kernel: $(uname -r)"

check "DISK_USAGE"     check_disk_usage
check "DISK_FREE"      check_disk_free
check "MEMORY"         check_memory
check "NCPU"           check_ncpu
check "LO_UP"          check_loopback
check "SSHD"           check_sshd
check "GIT"            check_git
check "RSYNC"          check_rsync
check "JQ"             check_jq
check "PYTHON3"        check_python3
check "STRACE"         check_strace
check "FILE"           check_file_util
check "TMP_WRITE"      check_tmp_write
check "HOME_WRITE"     check_home_write
check "DNS"            check_dns

TOTAL=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
log ""
log "=== Smoke Results: PASS=${PASS_COUNT} FAIL=${FAIL_COUNT} SKIP=${SKIP_COUNT} Total=${TOTAL} ==="

RESULTS="${RESULTS%,}"
DIAGDIR="${HOME:-/tmp}/.uom-agent/diagnostics/smoke"
mkdir -p "$DIAGDIR"

cat << ENDJSON
{"ts":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","pass":${PASS_COUNT},"fail":${FAIL_COUNT},"skip":${SKIP_COUNT},"total":${TOTAL},"checks":[${RESULTS}]}
ENDJSON

cat << ENDJSON > "$DIAGDIR/smoke.json"
{"ts":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","pass":${PASS_COUNT},"fail":${FAIL_COUNT},"skip":${SKIP_COUNT},"total":${TOTAL},"checks":[${RESULTS}]}
ENDJSON

exit $([ "$FAIL_COUNT" -eq 0 ] && echo 0 || echo 1)
