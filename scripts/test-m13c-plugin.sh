#!/bin/sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
_c() { [ "$2" = "$3" ] && { printf '  PASS %-45s = %s\n' "$1" "$3"; PASS=$((PASS+1)); } || { printf '  FAIL %-45s want=%s got=%s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); }; }

echo "=== M13-C Plugin Engine Tests ==="
. "$ROOT/src/core/logging.sh" 2>/dev/null || true
. "$ROOT/src/plugin/engine.sh"
sh -n "$ROOT/src/plugin/engine.sh" && _c "engine syntax" ok ok || _c "engine syntax" ok fail

# Fixture plugin tree
PDIR="${TMPDIR:-/tmp}/omni-plugins-$$"
export OMNI_PLUGIN_DIR="$PDIR"
mkdir -p "$PDIR/probe" "$PDIR/pre_deploy"

printf '#!/bin/sh\nexit 0\n'                    > "$PDIR/probe/10-good.sh"
printf '#!/bin/sh\nexit 1\n'                    > "$PDIR/probe/20-bad.sh"
printf '#!/bin/sh\nMARKER=clobbered\nexit 0\n'  > "$PDIR/probe/30-clobber.sh"
printf '#!/bin/sh\nexit 0\n'                    > "$PDIR/pre_deploy/10-ok.sh"
chmod +x "$PDIR"/probe/*.sh "$PDIR"/pre_deploy/*.sh
# non-executable plugins must be SKIPPED (opt-in via +x)
printf '#!/bin/sh\nexit 1\n' > "$PDIR/probe/40-noexec.sh"

# invalid hook rejected
rc=0; plugin_run_hooks bogus_hook >/dev/null 2>&1 || rc=$?
_c "invalid hook rc=2" 2 "$rc"

# probe: one bad plugin -> overall 1, but parent SURVIVES
MARKER=original
rc=0; plugin_run_hooks probe >/dev/null 2>&1 || rc=$?
_c "probe with failing plugin rc=1" 1 "$rc"
_c "subshell isolation (MARKER intact)" original "$MARKER"

# remove bad plugin -> probe passes
rm -f "$PDIR/probe/20-bad.sh"
rc=0; plugin_run_hooks probe >/dev/null 2>&1 || rc=$?
_c "probe all-good rc=0" 0 "$rc"

# mutation guard on mutating hook
rc=0; OMNI_SYSROOT=/tmp/fx plugin_run_hooks pre_deploy >/dev/null 2>&1 || rc=$?
_c "pre_deploy OMNI_SYSROOT guard 126" 126 "$rc"

# probe is read-only: NOT guarded
rc=0; OMNI_SYSROOT=/tmp/fx plugin_run_hooks probe >/dev/null 2>&1 || rc=$?
_c "probe not guarded (read-only)" 0 "$rc"

# empty hook dir -> 0
mkdir -p "$PDIR/post_deploy"
rc=0; plugin_run_hooks post_deploy >/dev/null 2>&1 || rc=$?
_c "empty hook dir rc=0" 0 "$rc"

# manifest reader (no eval)
mkdir -p "$PDIR/demo"; printf 'name=demo\nversion=1.2\n' > "$PDIR/demo/manifest.conf"
_c "manifest name" demo "$(plugin_manifest_get "$PDIR/demo" name)"
_c "manifest version" 1.2 "$(plugin_manifest_get "$PDIR/demo" version)"

rm -rf "$PDIR"
echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
