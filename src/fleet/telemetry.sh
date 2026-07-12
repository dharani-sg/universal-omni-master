#!/bin/sh
# src/fleet/telemetry.sh — M15: aggregated fleet telemetry collection.

fleet_telemetry_collect() {
    _group="${1:-}"
    fleet_parallel_exec 'command -v omni-detect >/dev/null 2>&1 && omni-detect 2>/dev/null | head -1 || echo "no-omni-detect"' "$_group"
}

fleet_telemetry_summary() {
    _hours="${1:-24}"
    [ -f "$OMNI_FLEET_STATE" ] || { printf 'fleet: no telemetry recorded yet\n'; return 0; }
    _cutoff=$(( $(date +%s) - _hours * 3600 ))

    # POSIX FIX: parentheses in AGE(s) are shell metacharacters when
    # unquoted as printf arguments. Backslash-escaped here.
    printf '%-16s %-10s %-8s %s\n' NODE STATUS AGE\(s\) MESSAGE
    printf '%-16s %-10s %-8s %s\n' ---- ------ ------ -------

    awk -v cutoff="$_cutoff" -v now="$(date +%s)" -F'"' '
        {
            node=""; status=""; msg=""; epoch=0
            for (i=1; i<=NF; i++) {
                if ($i == "node")    { node = $(i+2) }
                if ($i == "status")  { status = $(i+2) }
                if ($i == "message") { msg = $(i+2) }
            }
            e = $0
            sub(/.*"epoch":/, "", e); sub(/[^0-9].*/, "", e)
            epoch = e + 0
            if (epoch >= cutoff) {
                age = now - epoch
                last[node] = sprintf("%-16s %-10s %-8s %s", node, status, age, msg)
            }
        }
        END { for (n in last) print last[n] }
    ' "$OMNI_FLEET_STATE" | sort
}
