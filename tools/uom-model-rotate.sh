#!/bin/sh
# tools/uom-model-rotate.sh — Free model rotation for OpenCode CLI (online only)
# Tests models from the pool, caches the working one, rotates on failure.
# POSIX sh. No bashisms. Respects Retry-After headers.
#
# Usage:
#   sh tools/uom-model-rotate.sh              # Auto-select best model
#   sh tools/uom-model-rotate.sh select       # Same as above
#   sh tools/uom-model-rotate.sh next         # Rotate to next model (on failure)
#   sh tools/uom-model-rotate.sh current      # Print current model
#   sh tools/uom-model-rotate.sh status       # Show rotation status
#   sh tools/uom-model-rotate.sh verify       # Verify current model works

set -u

# ── Paths ──────────────────────────────────────────────────────────────
_SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
_UOM_DIR="$(cd "$_SELF_DIR/.." 2>/dev/null && pwd)"
UOM_RUNTIME_DIR="${UOM_RUNTIME_DIR:-${_UOM_DIR}/.uom-agent/runtime}"
UOM_LOG_DIR="${UOM_LOG_DIR:-${_UOM_DIR}/.uom-agent/logs}"
MODEL_FILE="${UOM_RUNTIME_DIR}/selected_model"
MODEL_HISTORY="${UOM_RUNTIME_DIR}/model_history"
MODEL_LOG="${UOM_LOG_DIR}/model-rotate.log"

mkdir -p "$UOM_RUNTIME_DIR" "$UOM_LOG_DIR"

# ── Model pool (free tier only) ────────────────────────────────────────
# Priority order: fast → capable → small → fallback
MODEL_POOL="${UOM_MODEL_POOL:-opencode/deepseek-v4-flash-free opencode/nemotron-3-ultra-free opencode/north-mini-code-free opencode/big-pickle}"

# ── Retry-After state ──────────────────────────────────────────────────
RATE_LIMIT_FILE="${UOM_RUNTIME_DIR}/rate-limited-until"

# ── Probe timeout ──────────────────────────────────────────────────────
PROBE_TIMEOUT="${UOM_MODEL_PROBE_TIMEOUT:-15}"

# ── Logging ────────────────────────────────────────────────────────────
_mlog() {
    _ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)"
    printf '[model-rotate] %s %s\n' "$_ts" "$*" >> "$MODEL_LOG" 2>/dev/null || true
    printf '[model-rotate] %s %s\n' "$_ts" "$*" >&2
}

# ── Check if online ────────────────────────────────────────────────────
_is_online() {
    ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 || \
    ping -c 1 -W 3 api.opencode.ai >/dev/null 2>&1
}

# ── Check if rate-limited ──────────────────────────────────────────────
_is_rate_limited() {
    if [ ! -f "$RATE_LIMIT_FILE" ]; then
        return 1
    fi
    _until=$(cat "$RATE_LIMIT_FILE" 2>/dev/null || echo "0")
    _now=$(date +%s)
    if [ "$_now" -lt "$_until" ] 2>/dev/null; then
        _remaining=$((_until - _now))
        _mlog "rate-limited for ${_remaining}s more"
        return 0
    fi
    rm -f "$RATE_LIMIT_FILE"
    return 1
}

# ── Set rate limit (from Retry-After or default 60s) ───────────────────
_set_rate_limit() {
    _retry_after="${1:-60}"
    # Validate it's numeric
    case "$_retry_after" in
        ''|*[!0-9]*) _retry_after=60 ;;
    esac
    _now=$(date +%s)
    _until=$((_now + _retry_after))
    printf '%s\n' "$_until" > "$RATE_LIMIT_FILE"
    _mlog "rate-limited until $_until (${_retry_after}s)"
}

# ── Read cached model ──────────────────────────────────────────────────
_cached_model() {
    if [ -f "$MODEL_FILE" ]; then
        cat "$MODEL_FILE" 2>/dev/null | tr -d '[:space:]'
    fi
}

# ── Save model to cache ────────────────────────────────────────────────
_save_model() {
    printf '%s\n' "$1" > "${MODEL_FILE}.tmp" 2>/dev/null && \
        mv "${MODEL_FILE}.tmp" "$MODEL_FILE" 2>/dev/null
}

# ── Append to history ──────────────────────────────────────────────────
_history_append() {
    _model="$1"; _status="$2"
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)
    printf '%s %s %s\n' "$_ts" "$_status" "$_model" >> "$MODEL_HISTORY" 2>/dev/null || true
    # Keep last 50 entries
    if [ -f "$MODEL_HISTORY" ]; then
        tail -50 "$MODEL_HISTORY" > "${MODEL_HISTORY}.tmp" 2>/dev/null && \
            mv "${MODEL_HISTORY}.tmp" "$MODEL_HISTORY" 2>/dev/null || true
    fi
}

# ── Probe a single model ──────────────────────────────────────────────
# Returns 0 if model works, 1 if it fails
# Outputs "ok" or "error:<reason>"
_probe_model() {
    _model="$1"

    if ! command -v opencode >/dev/null 2>&1; then
        echo "error:opencode-not-found"
        return 1
    fi

    _mlog "probing $_model (timeout=${PROBE_TIMEOUT}s)"
    _start=$(date +%s)

    _out=$(printf 'echo "test OK"' | timeout "$PROBE_TIMEOUT" \
        opencode run --model "$_model" 2>&1 || true)

    _end=$(date +%s)
    _elapsed=$((_end - _start))

    # Check for rate limiting (429 / Retry-After)
    case "$_out" in
        *429*|*rate*limit*|*Rate*limit*|*RESOURCE_EXHAUSTED*)
            # Try to extract Retry-After from response
            _ra=$(printf '%s' "$_out" | grep -oP 'Retry-After:\s*\K[0-9]+' 2>/dev/null || echo "60")
            _set_rate_limit "$_ra"
            _mlog "RATE LIMITED: $_model (retry-after=${_ra}s)"
            _history_append "$_model" "rate-limited"
            echo "error:rate-limited"
            return 1
            ;;
        *auth*|*API*key*|*invalid*api*|*PERMISSION_DENIED*)
            _mlog "AUTH FAIL: $_model"
            _history_append "$_model" "auth-fail"
            echo "error:auth-required"
            return 1
            ;;
        *timeout*|*timed*out*|*Deadline*)
            _mlog "TIMEOUT: $_model (${_elapsed}s)"
            _history_append "$_model" "timeout"
            echo "error:timeout"
            return 1
            ;;
        *error*5[0-9][0-9]*|*Internal*|*Bad*Gateway*)
            _mlog "SERVER ERROR: $_model"
            _history_append "$_model" "server-error"
            echo "error:server-error"
            return 1
            ;;
    esac

    # Check for successful content
    case "$_out" in
        *test*OK*|*function*|*hello*|*Hello*|*echo*|*POSIX*)
            _mlog "OK: $_model (${_elapsed}s)"
            _history_append "$_model" "ok"
            echo "ok"
            return 0
            ;;
    esac

    # If non-empty and no error, accept
    if [ -n "$_out" ]; then
        _mlog "OK (non-empty): $_model (${_elapsed}s)"
        _history_append "$_model" "ok"
        echo "ok"
        return 0
    fi

    _mlog "EMPTY: $_model"
    _history_append "$_model" "empty"
    echo "error:empty-response"
    return 1
}

# ── Select best model from pool ────────────────────────────────────────
_cmd_select() {
    if ! _is_online; then
        _mlog "offline — cannot select model"
        echo "OFFLINE"
        return 1
    fi

    if _is_rate_limited; then
        _cached=$(_cached_model)
        if [ -n "$_cached" ]; then
            _mlog "rate-limited, using cached: $_cached"
            echo "$_cached"
            return 0
        fi
    fi

    _mlog "selecting best model from pool"
    for _model in $MODEL_POOL; do
        _result=$(_probe_model "$_model")
        case "$_result" in
            ok)
                _save_model "$_model"
                _mlog "SELECTED: $_model"
                echo "$_model"
                return 0
                ;;
            error:rate-limited)
                # Don't try more models if rate-limited
                _mlog "stopping selection — rate limited"
                break
                ;;
            *)
                _mlog "SKIP: $_model ($_result)"
                continue
                ;;
        esac
    done

    # Fallback to cached
    _cached=$(_cached_model)
    if [ -n "$_cached" ]; then
        _mlog "all models failed, using cached: $_cached"
        echo "$_cached"
        return 0
    fi

    _mlog "NO MODELS AVAILABLE"
    echo "NONE"
    return 1
}

# ── Rotate to next model (on failure) ──────────────────────────────────
_cmd_next() {
    _current=$(_cached_model)
    _mlog "rotating from current: ${_current:-<none>}"

    if ! _is_online; then
        _mlog "offline — cannot rotate"
        echo "${_current:-NONE}"
        return 1
    fi

    # Find current in pool, try next
    _found=0
    for _model in $MODEL_POOL; do
        if [ "$_found" -eq 1 ]; then
            _result=$(_probe_model "$_model")
            case "$_result" in
                ok)
                    _save_model "$_model"
                    _mlog "ROTATED to: $_model"
                    echo "$_model"
                    return 0
                    ;;
                error:rate-limited)
                    break
                    ;;
                *)
                    continue
                    ;;
            esac
        fi
        if [ "$_model" = "$_current" ]; then
            _found=1
        fi
    done

    # Try from beginning if we were at end
    if [ "$_found" -eq 0 ]; then
        for _model in $MODEL_POOL; do
            _result=$(_probe_model "$_model")
            case "$_result" in
                ok)
                    _save_model "$_model"
                    _mlog "ROTATED to: $_model"
                    echo "$_model"
                    return 0
                    ;;
                error:rate-limited) break ;;
                *) continue ;;
            esac
        done
    fi

    _mlog "rotation failed — no models available"
    echo "${_current:-NONE}"
    return 1
}

# ── Print current model ────────────────────────────────────────────────
_cmd_current() {
    _cached=$(_cached_model)
    if [ -n "$_cached" ]; then
        echo "$_cached"
    else
        echo "NONE"
        return 1
    fi
}

# ── Verify current model works ─────────────────────────────────────────
_cmd_verify() {
    _current=$(_cached_model)
    if [ -z "$_current" ]; then
        _mlog "no model cached"
        return 1
    fi

    _result=$(_probe_model "$_current")
    case "$_result" in
        ok)
            echo "VERIFIED: $_current"
            return 0
            ;;
        *)
            echo "FAILED: $_current ($_result)"
            return 1
            ;;
    esac
}

# ── Status ─────────────────────────────────────────────────────────────
_cmd_status() {
    _current=$(_cached_model)
    _online=$(_is_online && echo "yes" || echo "no")
    _rlimited=$(_is_rate_limited && echo "yes" || echo "no")
    _pool_count=$(echo "$MODEL_POOL" | wc -w)

    printf 'model=%s\n' "${_current:-<none>}"
    printf 'online=%s\n' "$_online"
    printf 'rate_limited=%s\n' "$_rlimited"
    printf 'pool_size=%s\n' "$_pool_count"
    printf 'pool=%s\n' "$MODEL_POOL"

    if [ -f "$RATE_LIMIT_FILE" ]; then
        _until=$(cat "$RATE_LIMIT_FILE" 2>/dev/null || echo "0")
        _now=$(date +%s)
        _remaining=$((_until - _now))
        [ "$_remaining" -gt 0 ] 2>/dev/null && printf 'rate_limit_expires=%ss\n' "$_remaining"
    fi

    if [ -f "$MODEL_HISTORY" ]; then
        printf '\nRecent history:\n'
        tail -10 "$MODEL_HISTORY"
    fi
}

# ── Main ───────────────────────────────────────────────────────────────
_cmd="${1:-select}"
case "$_cmd" in
    select)   _cmd_select ;;
    next)     _cmd_next ;;
    current)  _cmd_current ;;
    verify)   _cmd_verify ;;
    status)   _cmd_status ;;
    *)
        echo "Usage: $0 {select|next|current|verify|status}" >&2
        exit 1
        ;;
esac
