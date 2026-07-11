#!/usr/bin/env fish
set ROOT (realpath (path dirname (status filename))/..)
set PASS 0; set FAIL 0
function check
    if test "$argv[2]" = "$argv[3]"
        printf '  PASS %-52s = %s\n' $argv[1] $argv[3]; set -g PASS (math $PASS + 1)
    else
        printf '  FAIL %-52s want=%s got=%s\n' $argv[1] $argv[2] $argv[3]; set -g FAIL (math $FAIL + 1)
    end
end

echo "=== M12 TUI Tests ==="
for _f in $ROOT/src/tui/*.fish $ROOT/scripts/test-m12-tui.fish
    fish --no-config --no-execute $_f 2>/dev/null
    check "syntax: "(basename $_f) 0 $status
end
sh -n $ROOT/bin/omni-tui 2>/dev/null
check "syntax: bin/omni-tui" 0 $status

env TERM=dumb $ROOT/bin/omni-tui --plain </dev/null >/dev/null 2>&1
check "--plain exits 0" 0 $status
env TERM=dumb $ROOT/bin/omni-tui dashboard </dev/null >/dev/null 2>&1
check "dashboard exits 0" 0 $status
env TERM=dumb $ROOT/bin/omni-tui snapshots </dev/null >/dev/null 2>&1
check "snapshots exits 0" 0 $status
env TERM=dumb $ROOT/bin/omni-tui help </dev/null >/dev/null 2>&1
check "help exits 0" 0 $status
env OMNI_SYSROOT=/tmp/fx $ROOT/bin/omni-tui --plain internal-test-mutation </dev/null >/dev/null 2>&1
check "mutation guard rc=126" 126 $status
env PATH=/__no_bin__ $ROOT/bin/omni-tui help >/dev/null 2>&1
check "no-fish rc=3" 3 $status
env TERM=dumb $ROOT/bin/omni-tui </dev/null >/dev/null 2>&1
check "no-arg interactive rc=4" 4 $status

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' $PASS $FAIL
test $FAIL -eq 0
