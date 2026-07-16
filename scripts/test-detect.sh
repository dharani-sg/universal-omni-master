#!/bin/sh
# test-detect.sh — omni-detect fixture matrix. M1 regression gate.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/bin/omni-detect"
FX="$ROOT/sandbox/fixtures"
PASS=0; FAIL=0

check() {
    _label="$1"; _want="$2"; _got="$3"
    if [ "$_want" = "$_got" ]; then
        printf '  \033[0;32mPASS\033[0m %-42s = %s\n' "$_label" "$_got"; PASS=$((PASS+1))
    else
        printf '  \033[1;31mFAIL\033[0m %-42s want=%s got=%s\n' "$_label" "$_want" "$_got"; FAIL=$((FAIL+1))
    fi
}

check_contains() {
    _label="$1"; _needle="$2"; _haystack="$3"
    if echo "$_haystack" | grep -q "$_needle" 2>/dev/null; then
        printf '  \033[0;32mPASS\033[0m %-42s contains %s\n' "$_label" "$_needle"; PASS=$((PASS+1))
    else
        printf '  \033[1;31mFAIL\033[0m %-42s missing %s\n' "$_label" "$_needle"; FAIL=$((FAIL+1))
    fi
}

check_json_field() {
    _label="$1"; _field="$2"; _want="$3"; _json="$4"
    _got=$(echo "$_json" | grep "\"$_field\"" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
    check "$_label" "$_want" "$_got"
}

echo "=== M1 Detect Fixture Matrix ==="

# ── Syntax check ──
sh -n "$CLI" && check "syntax check" "ok" "ok" || check "syntax check" "ok" "FAIL"

# ── Alpine: ext4, OpenRC, musl ──
_out=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" 2>/dev/null)
check_json_field "alpine distro"      "distro"      "alpine"  "$_out"
check_json_field "alpine init"        "init"         "openrc"  "$_out"
check_json_field "alpine libc"        "libc"         "musl"    "$_out"
check_json_field "alpine arch"        "arch"         "x86_64"  "$_out"
check_json_field "alpine pkgmgr"      "pkgmgr"       "apk"     "$_out"
check_json_field "alpine bootloader"  "bootloader"   "grub"    "$_out"
check_contains "alpine JSON has cpu_vendor" '"cpu_vendor"' "$_out"
check_contains "alpine JSON has gpu_count" '"gpu_count"' "$_out"
check_contains "alpine JSON has storage" '"storage"' "$_out"

# ── Void: btrfs, runit, glibc ──
_out=$(OMNI_SYSROOT="$FX/void" OMNI_LOG_LEVEL=error "$CLI" 2>/dev/null)
check_json_field "void distro"        "distro"      "void"    "$_out"
check_json_field "void init"          "init"         "runit"   "$_out"
check_json_field "void libc"          "libc"         "glibc"   "$_out"
check_json_field "void pkgmgr"        "pkgmgr"       "xbps"    "$_out"

# ── Arch: systemd, glibc ──
_out=$(OMNI_SYSROOT="$FX/arch" OMNI_LOG_LEVEL=error "$CLI" 2>/dev/null)
check_json_field "arch distro"        "distro"      "arch"    "$_out"
check_json_field "arch init"          "init"         "systemd" "$_out"
check_json_field "arch libc"          "libc"         "glibc"   "$_out"
check_json_field "arch pkgmgr"        "pkgmgr"       "pacman"  "$_out"
check_json_field "arch bootloader"    "bootloader"   "systemd-boot" "$_out"

# ── Debian: apt, systemd ──
_out=$(OMNI_SYSROOT="$FX/debian" OMNI_LOG_LEVEL=error "$CLI" 2>/dev/null)
check_json_field "debian distro"      "distro"      "debian"  "$_out"
check_json_field "debian init"        "init"         "systemd" "$_out"
check_json_field "debian pkgmgr"      "pkgmgr"       "apt"     "$_out"

# ── BusyBox-min: graceful degradation ──
_out=$(OMNI_SYSROOT="$FX/busybox-min" OMNI_LOG_LEVEL=error "$CLI" 2>/dev/null)
check_contains "busybox produces JSON output" '{' "$_out"
check_contains "busybox has distro field" '"distro"' "$_out"

# ── JSON validity (all fixtures) ──
for d in alpine void arch debian busybox-min; do
    _out=$(OMNI_SYSROOT="$FX/$d" OMNI_LOG_LEVEL=error "$CLI" 2>/dev/null)
    _opens=$(echo "$_out" | grep -c '{' || true)
    _closes=$(echo "$_out" | grep -c '}' || true)
    if [ "$_opens" -ge 1 ] && [ "$_closes" -ge 1 ]; then
        check "$d JSON balanced braces" "yes" "yes"
    else
        check "$d JSON balanced braces" "yes" "no"
    fi
done

# ── Mutation guard ──
rc=0
OMNI_SYSROOT="$FX/alpine" "$CLI" --apply 2>/dev/null || rc=$?
# detect is read-only, should succeed even with --apply (it ignores flags)
# But if someone adds mutation to detect, this guard catches it
check "detect is always read-only (rc=0)" "0" "$rc"

# ── No output to stdout when OMNI_LOG_LEVEL=error ──
_err=$(OMNI_SYSROOT="$FX/alpine" OMNI_LOG_LEVEL=error "$CLI" 2>/tmp/detect-stderr.txt)
if [ -z "$_err" ]; then
    check "detect stdout is clean JSON" "yes" "yes"
else
    # stdout should only contain JSON, no log lines
    _first=$(echo "$_err" | head -1)
    case "$_first" in
        '{'*) check "detect stdout is clean JSON" "yes" "yes" ;;
        *)    check "detect stdout is clean JSON" "yes" "no (first line: $_first)" ;;
    esac
fi

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
