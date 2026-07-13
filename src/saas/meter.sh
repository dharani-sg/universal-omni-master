#!/bin/sh
# src/saas/meter.sh — M23: SaaS metering and license validation.
# POSIX only. No eval. No jq. JSON parsing is narrow and backend-specific.

OMNI_SAAS_ENDPOINT="${OMNI_SAAS_ENDPOINT:-https://api.omni-saas.local/v1}"
OMNI_SAAS_CACHE="${OMNI_SAAS_CACHE:-/var/lib/omni-master/saas}"
OMNI_SAAS_GRACE_HOURS="${OMNI_SAAS_GRACE_HOURS:-24}"

saas_cache_write_allowed() {
    [ -z "${OMNI_SYSROOT:-}" ]
}

saas_check_license() {
    _key="${1:?saas_check_license: key required}"
    _cache_file="$OMNI_SAAS_CACHE/license.cache"
    _now=$(date +%s)

    if [ -f "$_cache_file" ]; then
        _cached_ts=$(sed -n '1p' "$_cache_file" 2>/dev/null)
        case "$_cached_ts" in
            ''|*[!0-9]*) _cached_ts=0 ;;
        esac
        _diff=$(( (_now - _cached_ts) / 3600 ))
        if [ "$_diff" -lt "$OMNI_SAAS_GRACE_HOURS" ]; then
            printf 'saas: offline grace active\n' >&2
            return 0
        fi
    fi

    command -v curl >/dev/null 2>&1 || {
        printf 'saas: curl unavailable and no valid cache\n' >&2
        return 1
    }

    _payload=$(printf '{"key":"%s"}' "$_key")
    _response=$(curl -s -X POST -H "Content-Type: application/json" \
        -d "$_payload" "$OMNI_SAAS_ENDPOINT/validate" 2>/dev/null)

    if printf '%s\n' "$_response" | grep -q '"valid"[[:space:]]*:[[:space:]]*true'; then
        if saas_cache_write_allowed; then
            mkdir -p "$OMNI_SAAS_CACHE" 2>/dev/null || true
            printf '%s\n' "$_now" > "$_cache_file" 2>/dev/null || true
        fi
        return 0
    fi

    printf 'saas: license invalid or backend unreachable\n' >&2
    return 1
}

saas_meter_event() {
    _event="${1:?saas_meter_event: event required}"
    _ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    _log_file="$OMNI_SAAS_CACHE/meter.ndjson"

    if saas_cache_write_allowed; then
        mkdir -p "$OMNI_SAAS_CACHE" 2>/dev/null || true
        printf '{"ts":"%s","event":"%s"}\n' "$_ts" "$_event" >> "$_log_file" 2>/dev/null || true
    fi

    # Synchronous best-effort upload; no background process.
    if command -v curl >/dev/null 2>&1; then
        _payload=$(printf '{"event":"%s","ts":"%s"}' "$_event" "$_ts")
        curl -s -X POST -H "Content-Type: application/json" \
            -d "$_payload" "$OMNI_SAAS_ENDPOINT/meter" >/dev/null 2>&1 || true
    fi

    return 0
}
