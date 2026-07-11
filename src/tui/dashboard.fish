#!/usr/bin/env fish
# src/tui/dashboard.fish — read-only status view. Uses $OMNI_ROOT.

function tui_action_dashboard
    tui_header "Dashboard"
    echo

    tui_separator; echo "HEALER STATUS"; tui_separator
    if test -x "$OMNI_ROOT/bin/omni-healer"
        $OMNI_ROOT/bin/omni-healer status 2>/dev/null; or echo "  not running"
    else
        echo "  omni-healer: not installed"
    end
    echo

    tui_separator; echo "SNAPSHOT STATUS"; tui_separator
    if test -x "$OMNI_ROOT/bin/omni-snapshot"
        $OMNI_ROOT/bin/omni-snapshot status 2>/dev/null; or echo "  (unavailable)"
    else
        echo "  omni-snapshot: not installed"
    end
    echo

    tui_separator; echo "LAST 5 AUDIT EVENTS"; tui_separator
    if test -r /var/log/omni-audit.json
        tail -5 /var/log/omni-audit.json
    else
        echo "  /var/log/omni-audit.json not readable"
    end
    echo
    return 0   # dashboard is read-only; always succeeds
end
