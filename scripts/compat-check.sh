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
    _lspci_fx="$FX/$_name/lspci.txt"
    if [ -f "$_lspci_fx" ]; then
        OMNI_SYSROOT="$FX/$_name" OMNI_LSPCI="$_lspci_fx" OMNI_LOG_LEVEL=error "$DETECT" > "$_out" 2>/dev/null
    else
        OMNI_SYSROOT="$FX/$_name" OMNI_LOG_LEVEL=error "$DETECT" > "$_out" 2>/dev/null
    fi
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

echo
echo "=== Hardware-layer assertions (previously untested) ==="
f=$(run_one arch)
check arch cpu_vendor AuthenticAMD "$f"
check arch cpu_count 4 "$f"
check arch gpu_vendors NVIDIA "$f"
check arch power_source ac "$f"

f=$(run_one debian)
check debian cpu_vendor GenuineIntel "$f"
check debian gpu_vendors Intel "$f"
check debian power_source battery "$f"

f=$(run_one void)
check void cpu_vendor GenuineIntel "$f"
check void gpu_vendors AMD,Intel "$f"
check void gpu_hybrid yes "$f"
check void power_source ac "$f"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
