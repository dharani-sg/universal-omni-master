# src/tui/common.fish — shared TUI helpers (Fish 4.x)
set -g OMNI_TUI_VERSION "0.12.0"

function tui_header
    set_color -o cyan
    echo "╔═══ Universal Omni-Master ═══ $argv[1] ═══╗"
    set_color normal
end

function tui_confirm --description 'typed confirmation; returns 1 unless exact word entered'
    read -P "$argv[1] (type '$argv[2]' to proceed): " -l ans
    test "$ans" = "$argv[2]"
end

function tui_run --description 'echo + run a command, show rc'
    set_color yellow; echo "→ $argv"; set_color normal
    command $argv
    set -l rc $status
    test $rc -eq 0; and set_color green; or set_color red
    echo "  [rc=$rc]"; set_color normal
    return $rc
end
