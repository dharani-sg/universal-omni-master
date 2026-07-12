#!/usr/bin/env fish
set ROOT (realpath (path dirname (status filename))/..)
set PASS 0; set FAIL 0
function check
    if test "$argv[2]" = "$argv[3]"
        printf '  PASS %-45s = %s\n' $argv[1] $argv[3]; set -g PASS (math $PASS + 1)
    else
        printf '  FAIL %-45s want=%s got=%s\n' $argv[1] $argv[2] $argv[3]; set -g FAIL (math $FAIL + 1)
    end
end

echo "=== M17 Adaptive Fish Tests ==="
fish --no-config -n $ROOT/src/tui/adaptive.fish
check "syntax: adaptive.fish" 0 $status

fish --no-config -c "
    source $ROOT/src/tui/common.fish
    source $ROOT/src/tui/adaptive.fish
    function _tui_cols; echo 40; end
    _tui_layout_mode
" | read -l _out40
check "40 cols -> portrait" portrait "$_out40"

fish --no-config -c "
    source $ROOT/src/tui/common.fish
    source $ROOT/src/tui/adaptive.fish
    function _tui_cols; echo 80; end
    _tui_layout_mode
" | read -l _out80
check "80 cols -> compact" compact "$_out80"

fish --no-config -c "
    source $ROOT/src/tui/common.fish
    source $ROOT/src/tui/adaptive.fish
    function _tui_cols; echo 120; end
    _tui_layout_mode
" | read -l _out120
check "120 cols -> landscape" landscape "$_out120"

fish --no-config -c "
    source $ROOT/src/tui/common.fish
    source $ROOT/src/tui/adaptive.fish
    function _tui_cols; echo 40; end
    _tui_reflow
    echo \$TUI_STACK
" | read -l _stack
check "portrait sets TUI_STACK vertical" vertical "$_stack"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' $PASS $FAIL
test $FAIL -eq 0
