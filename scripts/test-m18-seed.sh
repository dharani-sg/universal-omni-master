#!/bin/sh
set -u

ROOT=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
PASS=0
FAIL=0

_c() {
    if [ "$2" = "$3" ]; then
        printf '  PASS %-55s = %s\n' "$1" "$3"
        PASS=$((PASS + 1))
    else
        printf '  FAIL %-55s want=%s got=%s\n' "$1" "$2" "$3"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== M18 Omni-Seed Tests ==="

sh -n "$ROOT/scripts/omni-seed.sh" && _c "syntax: omni-seed.sh" ok ok || _c "syntax: omni-seed.sh" ok fail

WORK="${TMPDIR:-/tmp}/omni-m18-$$"
mkdir -p "$WORK"
STATE="$WORK/seed-state.conf"
MONO="$WORK/omni.sh"

# Use local repo builder path by invoking script from the repo path.
rc=0
OMNI_SEED_STATE="$STATE" OMNI_SEED_MONOLITH="$MONO" \
    "$ROOT/scripts/omni-seed.sh" >/dev/null 2>&1 || rc=$?
_c "seed without distro/disk exits 0" 0 "$rc"
_c "monolith created" yes "$([ -s "$MONO" ] && echo yes || echo no)"
_c "state file created" yes "$([ -f "$STATE" ] && echo yes || echo no)"
grep -q '^step_monolith=done$' "$STATE"
_c "state marks monolith done" 0 "$?"
grep -q '^step_plan=skipped$' "$STATE"
_c "state marks plan skipped" 0 "$?"

# Existing state requires --resume or --fresh.
rc=0
OMNI_SEED_STATE="$STATE" OMNI_SEED_MONOLITH="$MONO" \
    "$ROOT/scripts/omni-seed.sh" >/dev/null 2>&1 || rc=$?
_c "existing state without --resume exits 3" 3 "$rc"

# --resume with no distro/disk is OK and idempotent.
rc=0
OMNI_SEED_STATE="$STATE" OMNI_SEED_MONOLITH="$MONO" \
    "$ROOT/scripts/omni-seed.sh" --resume >/dev/null 2>&1 || rc=$?
_c "resume existing state exits 0" 0 "$rc"

# --fresh recreates state.
rc=0
OMNI_SEED_STATE="$STATE" OMNI_SEED_MONOLITH="$MONO" \
    "$ROOT/scripts/omni-seed.sh" --fresh >/dev/null 2>&1 || rc=$?
_c "fresh state exits 0" 0 "$rc"

# --apply is blocked in M18-A.
rc=0
OMNI_SEED_STATE="$STATE" OMNI_SEED_MONOLITH="$MONO" \
    "$ROOT/scripts/omni-seed.sh" --apply >/dev/null 2>&1 || rc=$?
_c "apply deferred exits 2" 2 "$rc"

# Layout hint via COLUMNS (no TTY needed)
out=$(COLUMNS=40 sh -c ". '$ROOT/scripts/omni-seed.sh' --help >/dev/null 2>&1" 2>/dev/null || true)
# The above cannot easily call internal functions because seed_main runs.
# Instead assert indirectly using log output:
_msg=$(COLUMNS=40 OMNI_SEED_STATE="$WORK/layout.conf" OMNI_SEED_MONOLITH="$WORK/layout.sh" \
    "$ROOT/scripts/omni-seed.sh" 2>&1 >/dev/null || true)
case "$_msg" in
    *"terminal layout: portrait"*) _c "COLUMNS=40 -> portrait log" yes yes ;;
    *) _c "COLUMNS=40 -> portrait log" yes no ;;
esac

# Plan path: should call monolith deploy plan and exit 0.
rc=0
OMNI_SEED_STATE="$WORK/plan-state.conf" OMNI_SEED_MONOLITH="$WORK/plan-mono.sh" \
    "$ROOT/scripts/omni-seed.sh" --distro alpine --disk sda --fs btrfs >/dev/null 2>&1 || rc=$?
_c "seed plan path exits 0" 0 "$rc"

grep -q '^step_plan=done$' "$WORK/plan-state.conf"
_c "state marks plan done" 0 "$?"

rm -rf "$WORK"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

# ── M18-B: hardened apply path ────────────────────────────────────────────
echo "--- M18-B apply guards ---"

WORK2="${TMPDIR:-/tmp}/omni-m18b-$$"
mkdir -p "$WORK2"

rc=0
OMNI_SEED_STATE="$WORK2/state.conf" OMNI_SEED_MONOLITH="$WORK2/mono.sh" \
    "$ROOT/scripts/omni-seed.sh" --apply >/dev/null 2>&1 || rc=$?
_c "apply without --disk exits 2" 2 "$rc"

rc=0
OMNI_SEED_STATE="$WORK2/state2.conf" OMNI_SEED_MONOLITH="$WORK2/mono2.sh" \
    "$ROOT/scripts/omni-seed.sh" --apply --disk loop0 >/dev/null 2>&1 || rc=$?
_c "apply with unsafe disk name exits 2" 2 "$rc"

rc=0
printf 'no\n' | OMNI_SEED_STATE="$WORK2/state3.conf" OMNI_SEED_MONOLITH="$WORK2/mono3.sh" \
    "$ROOT/scripts/omni-seed.sh" --apply --disk sda --distro alpine >/dev/null 2>&1 || rc=$?
_c "apply aborts on wrong first confirmation" 1 "$rc"

rc=0
printf 'YES\nno\n' | OMNI_SEED_STATE="$WORK2/state4.conf" OMNI_SEED_MONOLITH="$WORK2/mono4.sh" \
    "$ROOT/scripts/omni-seed.sh" --apply --disk sda --distro alpine >/dev/null 2>&1 || rc=$?
_c "apply aborts on wrong second confirmation" 1 "$rc"

rm -rf "$WORK2"

# ── M18-B: durable checkpoint mirror ───────────────────────────────────────
echo "--- M18-B checkpoint mirror ---"

WORK3="${TMPDIR:-/tmp}/omni-m18b-mirror-$$"
mkdir -p "$WORK3/target/boot/efi"

. "$ROOT/src/core/logging.sh" 2>/dev/null || true
. "$ROOT/src/deploy/state.sh"

OMNI_STATE_FILE="$WORK3/state.conf"
OMNI_STATE_LOCK="$WORK3/state.lock"
DEPLOY_TARGET="$WORK3/target"
export OMNI_STATE_FILE OMNI_STATE_LOCK DEPLOY_TARGET

deploy_state_init alpine sda btrfs

rc=0
deploy_checkpoint_mirror >/dev/null 2>&1 || rc=$?
_c "mirror to ESP succeeds" 0 "$rc"
_c "ESP mirror file exists" yes "$([ -f "$WORK3/target/boot/efi/EFI/omni/checkpoint.state" ] && echo yes || echo no)"

rm -rf "$WORK3/target/boot"
rc=0
deploy_checkpoint_mirror >/dev/null 2>&1 || rc=$?
_c "mirror falls back to target root" 0 "$rc"
_c "target root mirror file exists" yes "$([ -f "$WORK3/target/.omni-checkpoint.state" ] && echo yes || echo no)"

rc=0
OMNI_SYSROOT=/tmp/fx deploy_checkpoint_mirror >/dev/null 2>&1 || rc=$?
_c "mirror OMNI_SYSROOT guard 126" 126 "$rc"

rm -rf "$WORK3"

echo "=================================================="
printf 'M18-B RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
