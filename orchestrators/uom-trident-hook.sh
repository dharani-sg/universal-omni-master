#!/bin/sh
# orchestrators/uom-trident-hook.sh — Sourceable hooks for supervisor.sh
# Provides: model rotation on coordinator launch, rate-limit awareness, phone keepalive
# Source from supervisor.sh: . "${UOM_DIR}/orchestrators/uom-trident-hook.sh"

# ══════════════════════════════════════════════════════════════════════════
# MODEL ROTATION HOOK — called before launching coordinator
# ══════════════════════════════════════════════════════════════════════════
trident_pre_coord_launch() {
    _mr="${UOM_DIR}/tools/uom-model-rotate.sh"
    if [ -f "$_mr" ]; then
        # Verify current model is healthy before launching coordinator
        _result=$(sh "$_mr" verify 2>&1)
        case "$_result" in
            *VERIFIED*)
                echo "[trident-hook] model verified: $_result"
                ;;
            *FAILED*|*NONE*)
                echo "[trident-hook] model failed, rotating: $_result"
                _new=$(sh "$_mr" next 2>&1)
                echo "[trident-hook] rotated to: $_new"
                ;;
            *)
                echo "[trident-hook] model check inconclusive: $_result"
                ;;
        esac
    fi
}

# ══════════════════════════════════════════════════════════════════════════
# RATE LIMIT CHECK — returns 0 if OK to proceed, 1 if should back off
# ══════════════════════════════════════════════════════════════════════════
trident_rate_limit_ok() {
    _rlfile="${UOM_RUNTIME_DIR:-.uom-agent/runtime}/rate-limited-until"
    if [ -f "$_rlfile" ]; then
        _until=$(cat "$_rlfile" 2>/dev/null || echo "0")
        _now=$(date +%s)
        if [ "$_now" -lt "$_until" ] 2>/dev/null; then
            _remaining=$((_until - _now))
            echo "[trident-hook] rate-limited for ${_remaining}s"
            return 1
        fi
        rm -f "$_rlfile" 2>/dev/null || true
    fi
    return 0
}

# ══════════════════════════════════════════════════════════════════════════
# PHONE KEEPALIVE — lightweight SSH check
# ══════════════════════════════════════════════════════════════════════════
trident_phone_alive() {
    _host="$1"; _port="${2:-8022}"
    ssh -o ConnectTimeout=3 -o BatchMode=yes \
        -i "${HOME}/.ssh/id_ed25519_phone" \
        -p "$_port" "u0_a608@$_host" true 2>/dev/null
}

# ══════════════════════════════════════════════════════════════════════════
# PROCESS HEARTBEAT — write timestamp for trident to read
# ══════════════════════════════════════════════════════════════════════════
trident_heartbeat() {
    _name="$1"
    _hbdir="${UOM_RUNTIME_DIR:-.uom-agent/runtime}/heartbeat"
    mkdir -p "$_hbdir"
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)
    printf '{"ts":"%s","pid":%s}\n' "$_ts" "$$" > "${_hbdir}/${_name}.json"
}

echo "[trident-hook] loaded"
