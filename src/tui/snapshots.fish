#!/usr/bin/env fish
# src/tui/snapshots.fish — M10/M11 lifecycle and restore dispatch.
# All snapshot mutation guards live in omni-snapshot CLI.
# Restore requires: scroll+select + type name + type RESTORE (spec §4).

function tui_action_snap_list
    if test -x "$OMNI_ROOT/bin/omni-snapshot"
        $OMNI_ROOT/bin/omni-snapshot list
    else
        echo "omni-snapshot not installed"
        return 1
    end
end

function tui_action_snap_restore
    # D15: mutation guard at TUI layer before any user interaction
    _tui_guard_mutation; or return 126

    set -l _snaps ($OMNI_ROOT/bin/omni-snapshot list 2>/dev/null)
    if test (count $_snaps) -eq 0
        echo "No snapshots available."; return 1
    end

    echo
    echo "Available snapshots:"
    for _i in (seq (count $_snaps))
        printf '  %2d)  %s\n' $_i $_snaps[$_i]
    end
    echo

    read --prompt-str "Select snapshot number: " -l _n
    if not string match -qr '^[0-9]+$' -- $_n
        echo "Invalid input."; return 1
    end
    if test $_n -lt 1; or test $_n -gt (count $_snaps)
        echo "Out of range."; return 1
    end

    set -l _target $_snaps[$_n]
    echo
    echo "  Selected: $_target"
    echo

    # D10/spec §4 snapshot confirmation: type exact name + type RESTORE
    if tui_confirm_two "snapshot name" "$_target" RESTORE
        echo
        # omni-snapshot restore has its own internal confirmation gate (G4)
        # TUI does NOT bypass it — two confirmation layers are intentional
        tui_run $OMNI_ROOT/bin/omni-snapshot restore $_target
    else
        echo "Aborted — no changes made."
    end
end

function tui_action_snap_menu
    tui_header "Snapshot Manager"
    echo
    echo "  1) List snapshots"
    echo "  2) Create manual snapshot"
    echo "  3) Prune (enforce retention)"
    echo "  4) Stage restore"
    echo "  5) Boot-once"
    echo "  q) Back"
    echo
    read --prompt-str "> " -l _c
    switch $_c
        case 1
            tui_action_snap_list

        case 2
            read --prompt-str "Label for snapshot: " -l _lbl
            if test -n "$_lbl"
                tui_run $OMNI_ROOT/bin/omni-snapshot create manual $_lbl
            else
                echo "Label required."
            end

        case 3
            _tui_guard_mutation; or return 126
            if tui_confirm "Enforce retention policy (will delete old snapshots)" PRUNE
                tui_run $OMNI_ROOT/bin/omni-snapshot prune
            else
                echo "Aborted."
            end

        case 4
            tui_action_snap_restore

        case 5
            _tui_guard_mutation; or return 126
            set -l _snaps ($OMNI_ROOT/bin/omni-snapshot list 2>/dev/null)
            if test (count $_snaps) -eq 0
                echo "No snapshots available."; return 1
            end
            for _i in (seq (count $_snaps))
                printf '  %2d)  %s\n' $_i $_snaps[$_i]
            end
            read --prompt-str "Select snapshot number for boot-once: " -l _n
            if string match -qr '^[0-9]+$' -- $_n
                and test $_n -ge 1; and test $_n -le (count $_snaps)
                tui_run $OMNI_ROOT/bin/omni-snapshot boot-once $_snaps[$_n]
            else
                echo "Invalid selection."
            end

        case q
            return 0

        case '*'
            echo "Unknown option: $_c"
    end
end
