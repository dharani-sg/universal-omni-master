#!/bin/sh
# compat-check.sh — run omni-detect against fixture sysroots and assert results.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FX="$ROOT/sandbox/fixtures"
DETECT="$ROOT/bin/omni-detect"
PASS=0; FAIL=0

# jq-free JSON field extractor (our JSON is one-key-per-line)
jget() { grep "\"$2\":" "$1" | head -n1 | sed 's/.*: "//; s/".*//'; }

check() {
    _name="$1"; _key="$2"; _want="$3"; _file="$4"
    _got=$(jget "$_file" "$_key")
    if [ "$_got" = "$_want" ]; then
        printf '  \033[0;32mPASS\033[0m %-12s %-12s = %s\n' "$_name" "$_key" "$_got"
        PASS=$((PASS+1))
    else
        printf '  \033[1;31mFAIL\033[0m %-12s %-12s want=%s got=%s\n' "$_name" "$_key" "$_want" "$_got"
        FAIL=$((FAIL+1))
    fi
}

run_one() {
    _name="$1"
    _out="$ROOT/sandbox/run/$_name.json"
    mkdir -p "$ROOT/sandbox/run"
    OMNI_SYSROOT="$FX/$_name" OMNI_LOG_LEVEL=error "$DETECT" > "$_out" 2>/dev/null
    echo "$_out"
}

echo "=== Universal Omni-Master compatibility matrix ==="

f=$(run_one alpine)
check alpine distro alpine "$f"; check alpine init openrc "$f"
check alpine libc musl "$f";     check alpine pkgmgr apk "$f"
check alpine priv_helper doas "$f"

f=$(run_one void)
check void distro void "$f";     check void init runit "$f"
check void libc glibc "$f";      check void pkgmgr xbps "$f"

f=$(run_one arch)
check arch distro arch "$f";     check arch init systemd "$f"
check arch libc glibc "$f";      check arch pkgmgr pacman "$f"
check arch seat_model logind "$f"

f=$(run_one debian)
check debian distro debian "$f"; check debian init systemd "$f"
check debian pkgmgr apt "$f"

f=$(run_one busybox-min)
check busybox-min init unknown "$f"; check busybox-min libc musl "$f"
check busybox-min pkgmgr none "$f"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
