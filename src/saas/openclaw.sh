#!/bin/sh
# src/saas/openclaw.sh — M26: OpenClaw Commercial Telemetry Bridge.
# Pure POSIX. Aggregates local NDJSON logs for external sales AI.

OMNI_OPENCLAW_ENDPOINT="${OMNI_OPENCLAW_ENDPOINT:-https://api.openclaw.local/v1/sync}"
OMNI_TELEMETRY_DIR="${OMNI_TELEMETRY_DIR:-/var/lib/omni-master/saas}"

openclaw_generate_payload() {
    _ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    _meter_file="$OMNI_TELEMETRY_DIR/meter.ndjson"
    _compliance_file="$OMNI_TELEMETRY_DIR/compliance.ndjson"

    _ai_patches=0
    _deploy_success=0
    _compliance_drift=0

    if [ -f "$_meter_file" ]; then
        _ai_patches=$(grep -c '"event":"ai_patch_query"' "$_meter_file" 2>/dev/null) || _ai_patches=0
        _deploy_success=$(grep -c '"event":"deploy_success"' "$_meter_file" 2>/dev/null) || _deploy_success=0
    fi

    if [ -f "$_compliance_file" ]; then
        _compliance_drift=$(wc -l < "$_compliance_file" 2>/dev/null | tr -d ' ') || _compliance_drift=0
    fi

    printf '{\n'
    printf '  "ts": "%s",\n' "$_ts"
    printf '  "metrics": {\n'
    printf '    "ai_patches_applied": %s,\n' "$_ai_patches"
    printf '    "successful_deployments": %s,\n' "$_deploy_success"
    printf '    "compliance_enforcements": %s\n' "$_compliance_drift"
    printf '  }\n'
    printf '}\n'
}

openclaw_sync() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        printf 'openclaw: REFUSING network sync — OMNI_SYSROOT set\n' >&2
        return 126
    fi

    _payload=$(openclaw_generate_payload)

    if command -v curl >/dev/null 2>&1; then
        curl -s -m 10 -X POST \
            -H "Content-Type: application/json" \
            -d "$_payload" \
            "$OMNI_OPENCLAW_ENDPOINT" >/dev/null 2>&1
        return $?
    fi

    printf 'openclaw: curl unavailable, sync aborted\n' >&2
    return 1
}
