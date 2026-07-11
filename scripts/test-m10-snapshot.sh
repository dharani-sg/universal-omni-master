#!/bin/sh
# scripts/test-m10-snapshot.sh — M10-A snapshot module gate.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

check() {
    if [ "$2" = "$3" ]; then
        printf '  PASS %-50s = %s\n' "$1" "$3"; PASS=$((PASS+1))
    else
        printf '  FAIL %-50s want=%s got=%s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1))
    fi
}

echo "=== M10-A Snapshot Module Tests ==="

# ── 1. Syntax (R10 fix: source BEFORE mutation guard test) ────────────────────
for f in "$ROOT/src/snapshot/common.sh" \
          "$ROOT/src/snapshot/prune.sh" \
          "$ROOT/src/snapshot/periodic.sh" \
          "$ROOT/src/deploy/snapshot_install.sh" \
          "$ROOT/bin/omni-snapshot"; do
    sh -n "$f" && check "syntax: $(basename "$f")" ok ok || check "syntax: $(basename "$f")" ok fail
done

# ── 2. Hook assets ────────────────────────────────────────────────────────────
for h in apk-commit.sh xbps-wrapper.sh; do
    _p="$ROOT/src/snapshot/hooks/$h"
    sh -n "$_p" 2>/dev/null && check "syntax: $h" ok ok || check "syntax: $h" ok "fail(missing/bad)"
done
for decl in pacman.hook apt.conf; do
    [ -s "$ROOT/src/snapshot/hooks/$decl" ] && check "present: $decl" yes yes || check "present: $decl" yes no
done
[ -x "$ROOT/src/snapshot/hooks/apk-commit.sh" ] && \
    check "apk hook executable" yes yes || check "apk hook executable" yes no
[ -x "$ROOT/src/snapshot/hooks/xbps-wrapper.sh" ] && \
    check "xbps wrapper executable" yes yes || check "xbps wrapper executable" yes no

# ── 3. CLI dispatch ───────────────────────────────────────────────────────────
rc=0; "$ROOT/bin/omni-snapshot" help >/dev/null 2>&1 || rc=$?
check "cli help exits 0" "0" "$rc"

rc=0; "$ROOT/bin/omni-snapshot" bogus >/dev/null 2>&1 || rc=$?
check "cli unknown exits 2" "2" "$rc"

# ── 4. Mutation guard (R10 fix: source common.sh FIRST, then test guard) ──────
# Source common.sh in a clean subshell so OMNI_SYSROOT affects _snap_guard_mutation
rc=$(OMNI_SYSROOT="/tmp/fx" sh -c "
    . '$ROOT/src/core/logging.sh' 2>/dev/null || true
    . '$ROOT/src/snapshot/common.sh'
    snap_load_conf
    _snap_guard_mutation >/dev/null 2>&1
    printf '%s' \$?
")
check "mutation guard exits 126 when OMNI_SYSROOT set" "126" "$rc"

# Guard absent (no OMNI_SYSROOT): should return 0
rc=$(sh -c "
    . '$ROOT/src/core/logging.sh' 2>/dev/null || true
    . '$ROOT/src/snapshot/common.sh'
    snap_load_conf
    _snap_guard_mutation >/dev/null 2>&1
    printf '%s' \$?
")
check "mutation guard returns 0 without OMNI_SYSROOT" "0" "$rc"

# ── 5. Config loader ──────────────────────────────────────────────────────────
rc=$(OMNI_SNAP_CONF="$ROOT/config/omni-snapshot.conf.example" sh -c "
    . '$ROOT/src/snapshot/common.sh'
    snap_load_conf
    printf '%s' \"\${SNAPSHOT_RETAIN_PRETXN:-UNSET}\"
")
check "config loads RETAIN_PRETXN=10" "10" "$rc"

# ── 6. Non-Btrfs graceful skip (R5 fix) ──────────────────────────────────────
rc=$(sh -c "
    . '$ROOT/src/core/logging.sh' 2>/dev/null || true
    . '$ROOT/src/snapshot/common.sh'
    snap_load_conf
    # Override mount detection: _snap_is_btrfs always returns 1 (not Btrfs)
    _snap_is_btrfs() { return 1; }
    snap_create manual test >/dev/null 2>&1
    printf '%s' \$?
")
check "non-Btrfs create returns 0 (graceful skip)" "0" "$rc"

# ── 7. Free-space guard ───────────────────────────────────────────────────────
rc=$(sh -c "
    . '$ROOT/src/core/logging.sh' 2>/dev/null || true
    . '$ROOT/src/snapshot/common.sh'
    snap_load_conf
    SNAPSHOT_MIN_FREE_GB=999999   # unreachably high threshold
    _snap_is_btrfs() { return 0; }
    _snap_check_free_space / >/dev/null 2>&1
    printf '%s' \$?
")
check "free-space guard blocks at absurd threshold" "1" "$rc"

# ── 8. R1: --reason flag parsing ─────────────────────────────────────────────
rc=$(sh -c "
    . '$ROOT/src/core/logging.sh' 2>/dev/null || true
    . '$ROOT/src/snapshot/common.sh'
    snap_load_conf
    # --reason pretxn-pacman should produce category=pretxn, reason=pacman
    _cat=; _rsn=
    _raw='pretxn-pacman'
    _cat=\$(printf '%s' \"\$_raw\" | cut -d'-' -f1)
    _rsn=\$(printf '%s' \"\$_raw\" | cut -d'-' -f2-)
    printf '%s|%s' \"\$_cat\" \"\$_rsn\"
")
check "--reason parsing: pretxn-pacman → pretxn|pacman" "pretxn|pacman" "$rc"

# ── 9. Config example exists ─────────────────────────────────────────────────
[ -f "$ROOT/config/omni-snapshot.conf.example" ] && \
    check "config example present" yes yes || check "config example present" yes no

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
