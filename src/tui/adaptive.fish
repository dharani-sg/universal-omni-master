# src/tui/adaptive.fish — M17 adaptive Fish TUI reflow.
# Sourced by main.fish AFTER common.fish (reuses _tui_cols). No top-level
# executable code, no eval, Fish 4.x --no-config safe.

function _tui_layout_mode --description "3-tier layout using M12's _tui_cols"
    set -l cols (_tui_cols)
    if test "$cols" -lt 60
        echo portrait
    else if test "$cols" -lt 100
        echo compact
    else
        echo landscape
    end
end

function _tui_reflow --description "Set TUI_LAYOUT/TUI_STACK/TUI_BOX_WIDTH globals"
    set -g TUI_LAYOUT (_tui_layout_mode)
    set -l cols (_tui_cols)
    switch "$TUI_LAYOUT"
        case portrait compact
            set -g TUI_STACK vertical
            set -g TUI_BOX_WIDTH $cols
        case '*'
            set -g TUI_STACK horizontal
            set -g TUI_BOX_WIDTH 100
    end
end

function _tui_truncate --description "Truncate string to fit width (min 4)"
    set -l s $argv[1]
    set -l w $argv[2]
    if test "$w" -lt 4
        set w 4
    end
    if test (string length -- "$s") -gt $w
        string sub -l $w -- "$s"
    else
        echo -- "$s"
    end
end

function _tui_dashboard_healer --description "Render healer widget"
    _tui_reflow
    set -l status $argv[1]
    set -l restarts $argv[2]
    if test "$TUI_LAYOUT" = portrait
        echo "== Healer =="
        echo "status:   $status"
        echo "restarts: $restarts"
    else if test "$TUI_LAYOUT" = compact
        echo "-- Healer --"
        printf "status=%s  restarts=%s\n" $status $restarts
    else
        printf "| Healer: %-10s | restarts: %-4s |\n" $status $restarts
    end
end

function _tui_dashboard_snapshots --description "Render snapshot widget"
    _tui_reflow
    set -l count $argv[1]
    set -l latest $argv[2]
    set -l w (math $TUI_BOX_WIDTH - 8)
    if test "$TUI_LAYOUT" = portrait
        echo "== Snapshots =="
        echo "count:  $count"
        echo "latest: "(_tui_truncate "$latest" $w)
    else if test "$TUI_LAYOUT" = compact
        echo "-- Snapshots --"
        printf "count=%s latest=%s\n" $count $latest
    else
        printf "| Snapshots: %-4s | latest: %-20s |\n" $count $latest
    end
end

function _tui_dashboard_fleet --description "Render fleet grid widget"
    _tui_reflow
    set -l hosts $argv
    set -l w (math $TUI_BOX_WIDTH - 4)
    if test "$TUI_LAYOUT" = portrait
        echo "== Fleet =="
        for host in $hosts
            echo " - "(_tui_truncate "$host" $w)
        end
    else if test "$TUI_LAYOUT" = compact
        echo "-- Fleet ("(count $hosts)" hosts) --"
        for host in $hosts
            echo "  * $host"
        end
    else
        printf "| Fleet (%d hosts) |\n" (count $hosts)
        for host in $hosts
            printf "|  %-30s |\n" $host
        end
    end
end

function _tui_stack_widgets --description "Vertical/horizontal stack of dashboards"
    _tui_reflow
    _tui_dashboard_healer $argv[1] $argv[2]
    if test "$TUI_STACK" = vertical
        echo ""
    end
    _tui_dashboard_snapshots $argv[3] $argv[4]
    if test "$TUI_STACK" = vertical
        echo ""
    end
    _tui_dashboard_fleet $argv[5..-1]
end
