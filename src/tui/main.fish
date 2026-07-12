#!/usr/bin/env fish
# src/tui/main.fish — routing coordinator. Run only via fish --no-config.

set -l _tui_dir (path dirname (status filename))
if not set -q OMNI_ROOT; or test -z "$OMNI_ROOT"
    set -gx OMNI_ROOT (path resolve "$_tui_dir/../..")
end

for _m in common adaptive dashboard installer snapshots
    set -l _f "$_tui_dir/$_m.fish"
    test -r "$_f"; or begin; echo "missing $_f" >&2; exit 1; end
    source "$_f"
end

argparse 'p/plain' 'h/help' -- $argv; or exit 2
set -q _flag_plain; and set -gx NO_COLOR 1
set -q _flag_help;  and begin; tui_print_help; exit 0; end

set -l _cmd ""
if test (count $argv) -gt 0
    set _cmd $argv[1]
else if set -q _flag_plain
    set _cmd dashboard
end

switch "$_cmd"
    case dashboard
        tui_action_dashboard --plain; exit 0
    case snapshots
        tui_action_snap_list; exit 0
    case installer
        if not isatty stdin; or not isatty stdout
            printf 'installer requires TTY\n' >&2; exit 4
        end
        tui_action_installer; exit $status
    case help
        tui_print_help; exit 0
    case internal-test-mutation
        _tui_guard_mutation; exit $status
    case ''
        # fall through to interactive
    case '*'
        printf 'unknown subcommand: %s\n' "$_cmd" >&2; exit 2
end

if not isatty stdin; or not isatty stdout
    printf 'interactive mode requires a TTY\n' >&2; exit 4
end

while true
    tui_header "Main Menu"
    echo "  1) Dashboard   2) Snapshots   3) Installer   q) Quit"
    echo
    read --prompt-str "> " -l _c; or exit 0
    switch "$_c"
        case 1; tui_action_dashboard
        case 2; tui_action_snap_menu
        case 3; tui_action_installer
        case q Q quit exit; exit 0
        case ''; continue
        case '*'; echo "Unknown: $_c"
    end
    echo
end
