# src/tui/snapshots.fish — dispatch layer over bin/omni-snapshot (all guards live there)
function tui_action_snap_list
    set -l root (dirname (status filename))/../..
    $root/bin/omni-snapshot list
end

function tui_action_snap_restore
    set -l root (dirname (status filename))/../..
    set -l snaps ($root/bin/omni-snapshot list)
    if test (count $snaps) -eq 0
        echo "No snapshots available."; return 1
    end
    for i in (seq (count $snaps))
        printf '  %2d) %s\n' $i $snaps[$i]
    end
    read -P "Select snapshot number: " -l n
    string match -qr '^[0-9]+$' -- $n; or begin; echo "invalid"; return 1; end
    test $n -ge 1 -a $n -le (count $snaps); or begin; echo "out of range"; return 1; end
    # omni-snapshot restore has its own typed-yes gate (G4) — TUI adds no bypass
    $root/bin/omni-snapshot restore $snaps[$n]
end

function tui_action_snap_menu
    tui_header "Snapshots"
    echo "  1) List    2) Create manual    3) Prune    4) Restore    5) Boot-once    q) Back"
    read -P "> " -l c
    switch $c
        case 1; tui_action_snap_list
        case 2
            read -P "Label: " -l lbl
            set -l root (dirname (status filename))/../..
            $root/bin/omni-snapshot create manual $lbl
        case 3
            set -l root (dirname (status filename))/../..
            tui_confirm "Prune per retention policy" PRUNE; and $root/bin/omni-snapshot prune
        case 4; tui_action_snap_restore
        case 5
            set -l root (dirname (status filename))/../..
            read -P "Snapshot name: " -l sn
            $root/bin/omni-snapshot boot-once $sn
        case q
    end
end
