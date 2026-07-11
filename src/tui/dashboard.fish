# src/tui/dashboard.fish — read-only status view (no mutations possible here)
function tui_action_dashboard
    set -l root (dirname (status filename))/../..
    tui_header "Dashboard"
    echo
    echo "── omni-healer ──"
    $root/bin/omni-healer status 2>/dev/null; or echo "  not running"
    echo
    echo "── snapshots ──"
    $root/bin/omni-snapshot status 2>/dev/null; or echo "  (non-Btrfs or unavailable)"
    echo
    echo "── last 5 audit events ──"
    if test -r /var/log/omni-audit.json
        tail -5 /var/log/omni-audit.json
    else
        echo "  no audit log readable"
    end
end
