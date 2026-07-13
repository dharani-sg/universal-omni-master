#!/bin/sh
# src/saas/meter.sh — M23.1: SaaS tier switching, usage metering, license cache.
# POSIX only. No eval. No jq. Backend JSON parsing is narrow and controlled.

OMNI_SAAS_ENDPOINT="${OMNI_SAAS_ENDPOINT:-https://api.omni-saas.local/v1}"
OMNI_SAAS_CACHE="${OMNI_SAAS_CACHE:-/var/lib/omni-master/saas}"
OMNI_SAAS_GRACE_HOURS="${OMNI_SAAS_GRACE_HOURS:-24}"

saas_cache_write_allowed() {
    [ -z "${OMNI_SYSROOT:-}" ]
}

_saas_cache_file() {
    printf '%s/license.cache\n' "$OMNI_SAAS_CACHE"
}

_saas_meter_file() {
    printf '%s/meter.ndjson\n' "$OMNI_SAAS_CACHE"
}

# _saas_parse_json_val <json> <key>
# Narrow backend-specific JSON extraction.
# Handles: "key": true, "key": "value", "key": 123, "key": pay_per_use
_saas_parse_json_val() {
    _json="$1"
    _key="$2"
    printf '%s\n' "$_json" |
        sed -n 's/.*"'"$_key"'"[[:space:]]*:[[:space:]]*"\{0,1\}\([^",} ]*\)"\{0,1\}.*/\1/p' |
        head -1
}

_saas_cache_get() {
    _key="$1"
    _file=$(_saas_cache_file)
    [ -f "$_file" ] || return 1
    _line=$(grep "^${_key}=" "$_file" 2>/dev/null | head -1)
    [ -z "$_line" ] && return 1
    printf '%s\n' "${_line#${_key}=}"
}

_saas_cache_write() {
    saas_cache_write_allowed || return 0

    _file=$(_saas_cache_file)
    mkdir -p "$OMNI_SAAS_CACHE" 2>/dev/null || true

    _tmp="${_file}.tmp.$$"
    : > "$_tmp"

    printf 'ts=%s\n' "${1:-0}" >> "$_tmp"
    printf 'tier=%s\n' "${2:-unknown}" >> "$_tmp"
    printf 'expiry=%s\n' "${3:-0}" >> "$_tmp"
    printf 'credits=%s\n' "${4:-0}" >> "$_tmp"
    printf 'usage_count=%s\n' "${5:-0}" >> "$_tmp"
    printf 'usage_window=%s\n' "${6:-none}" >> "$_tmp"

    mv "$_tmp" "$_file" 2>/dev/null || true
}

_saas_cache_update_key() {
    saas_cache_write_allowed || return 0

    _key="$1"
    _val="$2"
    _file=$(_saas_cache_file)
    mkdir -p "$OMNI_SAAS_CACHE" 2>/dev/null || true

    _tmp="${_file}.tmp.$$"
    if [ -f "$_file" ]; then
        grep -v "^${_key}=" "$_file" > "$_tmp" 2>/dev/null || :
    else
        : > "$_tmp"
    fi

    printf '%s=%s\n' "$_key" "$_val" >> "$_tmp"
    mv "$_tmp" "$_file" 2>/dev/null || true
}

_saas_number_or_zero() {
    case "$1" in
        ''|*[!0-9]*) printf '0\n' ;;
        *) printf '%s\n' "$1" ;;
    esac
}

_saas_cache_valid_offline() {
    _file=$(_saas_cache_file)
    [ -f "$_file" ] || return 1

    _now=$(date +%s)

    _ts=$(_saas_cache_get ts 2>/dev/null || printf 0)
    _tier=$(_saas_cache_get tier 2>/dev/null || printf unknown)
    _expiry=$(_saas_cache_get expiry 2>/dev/null || printf 0)
    _credits=$(_saas_cache_get credits 2>/dev/null || printf 0)

    _ts=$(_saas_number_or_zero "$_ts")
    _expiry=$(_saas_number_or_zero "$_expiry")
    _credits=$(_saas_number_or_zero "$_credits")

    _age_hours=$(( (_now - _ts) / 3600 ))
    if [ "$_age_hours" -ge "$OMNI_SAAS_GRACE_HOURS" ]; then
        printf 'saas: offline cache expired\n' >&2
        return 1
    fi

    case "$_tier" in
        trial)
            if [ "$_expiry" -gt 0 ] && [ "$_now" -le "$_expiry" ]; then
                printf 'saas: offline trial valid\n' >&2
                return 0
            fi
            printf 'saas: trial expired\n' >&2
            return 1
            ;;
        pay_per_use)
            if [ "$_credits" -gt 0 ]; then
                printf 'saas: offline pay_per_use valid, credits=%s\n' "$_credits" >&2
                return 0
            fi
            printf 'saas: pay_per_use credits exhausted\n' >&2
            return 1
            ;;
        subscription_weekly|subscription_monthly)
            if [ "$_expiry" -eq 0 ] || [ "$_now" -le "$_expiry" ]; then
                printf 'saas: offline subscription valid\n' >&2
                return 0
            fi
            printf 'saas: subscription expired\n' >&2
            return 1
            ;;
        *)
            printf 'saas: unknown cached tier: %s\n' "$_tier" >&2
            return 1
            ;;
    esac
}

# saas_check_license <key>
# Backend-first: catches tier switches immediately.
# Offline fallback: enforces trial expiry / PPU credits / subscription expiry.
saas_check_license() {
    _key="${1:?saas_check_license: key required}"
    _now=$(date +%s)

    if command -v curl >/dev/null 2>&1; then
        _payload=$(printf '{"key":"%s"}' "$_key")
        _response=$(curl -s -m 5 -X POST -H "Content-Type: application/json" \
            -d "$_payload" "$OMNI_SAAS_ENDPOINT/validate" 2>/dev/null)

        if [ -n "$_response" ]; then
            _valid=$(_saas_parse_json_val "$_response" valid)
            _tier=$(_saas_parse_json_val "$_response" tier)
            _expiry=$(_saas_parse_json_val "$_response" expiry)
            _credits=$(_saas_parse_json_val "$_response" credits)
            _usage_count=$(_saas_parse_json_val "$_response" usage_count)
            _usage_window=$(_saas_parse_json_val "$_response" usage_window)

            [ -z "$_tier" ] && _tier=unknown
            _expiry=$(_saas_number_or_zero "$_expiry")
            _credits=$(_saas_number_or_zero "$_credits")
            _usage_count=$(_saas_number_or_zero "$_usage_count")
            [ -z "$_usage_window" ] && _usage_window=none

            if [ "$_valid" = "true" ]; then
                _saas_cache_write "$_now" "$_tier" "$_expiry" "$_credits" "$_usage_count" "$_usage_window"
                return 0
            fi

            printf 'saas: backend rejected license\n' >&2
            return 1
        fi
    fi

    _saas_cache_valid_offline
}

saas_status() {
    _file=$(_saas_cache_file)

    if [ ! -f "$_file" ]; then
        printf 'status=missing_cache\n'
        return 1
    fi

    printf 'tier=%s\n' "$(_saas_cache_get tier 2>/dev/null || printf unknown)"
    printf 'expiry=%s\n' "$(_saas_cache_get expiry 2>/dev/null || printf 0)"
    printf 'credits=%s\n' "$(_saas_cache_get credits 2>/dev/null || printf 0)"
    printf 'usage_count=%s\n' "$(_saas_cache_get usage_count 2>/dev/null || printf 0)"
    printf 'usage_window=%s\n' "$(_saas_cache_get usage_window 2>/dev/null || printf none)"
}

saas_consume_credit() {
    saas_cache_write_allowed || return 0

    _tier=$(_saas_cache_get tier 2>/dev/null || printf unknown)
    [ "$_tier" = "pay_per_use" ] || return 0

    _credits=$(_saas_cache_get credits 2>/dev/null || printf 0)
    _credits=$(_saas_number_or_zero "$_credits")

    if [ "$_credits" -le 0 ]; then
        printf 'saas: no pay_per_use credits remaining\n' >&2
        return 1
    fi

    _new=$((_credits - 1))
    _saas_cache_update_key credits "$_new"
    return 0
}

saas_increment_usage() {
    saas_cache_write_allowed || return 0

    _count=$(_saas_cache_get usage_count 2>/dev/null || printf 0)
    _count=$(_saas_number_or_zero "$_count")
    _count=$((_count + 1))
    _saas_cache_update_key usage_count "$_count"
}

saas_meter_event() {
    _event="${1:?saas_meter_event: event required}"
    _ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    _meter_file=$(_saas_meter_file)

    if saas_cache_write_allowed; then
        mkdir -p "$OMNI_SAAS_CACHE" 2>/dev/null || true
        printf '{"ts":"%s","event":"%s"}\n' "$_ts" "$_event" >> "$_meter_file" 2>/dev/null || true
        saas_increment_usage
        case "$_event" in
            deploy_success|node_deployed|billable_*)
                saas_consume_credit >/dev/null 2>&1 || true
                ;;
        esac
    fi

    if command -v curl >/dev/null 2>&1; then
        _payload=$(printf '{"event":"%s","ts":"%s"}' "$_event" "$_ts")
        curl -s -m 5 -X POST -H "Content-Type: application/json" \
            -d "$_payload" "$OMNI_SAAS_ENDPOINT/meter" >/dev/null 2>&1 || true
    fi

    return 0
}
