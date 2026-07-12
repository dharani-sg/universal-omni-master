#!/bin/sh
# src/fleet/security_audit.sh — M15: fleet-wide TPM2/UKI/SBAT auditing.

fleet_security_audit() {
    _group="${1:-}"
    _remote_cmd='command -v omni-security >/dev/null 2>&1 && omni-security probe 2>&1 || echo "status=no_omni_security"'
    fleet_parallel_exec "$_remote_cmd" "$_group"
}

fleet_security_report() {
    _hours="${1:-24}"
    [ -f "$OMNI_FLEET_STATE" ] || { printf 'fleet-security: no data yet\n'; return 0; }
    _cutoff=$(( $(date +%s) - _hours * 3600 ))

    printf '%-16s %-12s %s\n' NODE FLAG DETAIL
    printf '%-16s %-12s %s\n' ---- ---- ------

    awk -v cutoff="$_cutoff" -F'"' '
        {
            node=""; msg=""
            for (i=1; i<=NF; i++) {
                if ($i == "node")    { node = $(i+2) }
                if ($i == "message") { msg = $(i+2) }
            }
            e = $0
            sub(/.*"epoch":/, "", e); sub(/[^0-9].*/, "", e)
            if ((e + 0) >= cutoff) {
                flag = "unknown"
                if (msg ~ /status=ready/)        { flag = "ok" }
                if (msg ~ /status=unavailable/)  { flag = "unavailable" }
                if (msg ~ /status=degraded/)     { flag = "degraded" }
                if (msg ~ /no_omni_security/)     { flag = "missing_tool" }
                lines[node] = sprintf("%-16s %-12s %s", node, flag, msg)
            }
        }
        END { for (n in lines) print lines[n] }
    ' "$OMNI_FLEET_STATE" | sort
}
