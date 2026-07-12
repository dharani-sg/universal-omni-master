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
