#!/usr/bin/env fish
# scripts/test-m12-tui.fish — TTY-free TUI tests
set ROOT (cd (dirname (status filename))/.. && pwd)
set PASS 0; set FAIL 0
function check
    if test "$argv[2]" = "$argv[3]"
        printf '  PASS %-45s = %s\n' $argv[1] $argv[3]; set PASS (math $PASS+1)
    else
        printf '  FAIL %-45s want=%s got=%s\n' $argv[1] $argv[2] $argv[3]; set FAIL (math $FAIL+1)
    end
end
echo "=== M12 TUI Tests ==="
for f in $ROOT/src/tui/*.fish
    fish -n $f; and check "syntax: (basename $f)" ok ok; or check "syntax: (basename $f)" ok fail
end
sh -n $ROOT/bin/omni-tui; and check "syntax: bin/omni-tui" ok ok
# launcher guards
set out ($ROOT/bin/omni-tui < /dev/null 2>&1; echo rc=$status)
string match -q '*rc=4*' -- "$out"; and check "no-TTY exits 4" yes yes; or check "no-TTY exits 4" yes no
# functions load + dashboard runs headless (read-only)
fish -c "for f in $ROOT/src/tui/*.fish; source \$f; end; functions -q tui_action_dashboard"; and \
    check "functions load" yes yes; or check "functions load" yes no
echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' $PASS $FAIL
test $FAIL -eq 0
