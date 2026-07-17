#!/data/data/com.termux/files/usr/bin/sh
# orchestrators/uom-watchdog.sh — Laptop reachability monitor for phone
# Runs on phone: checks laptop status every 60s
# Triggers solo orchestrator after FAIL_THRESHOLD consecutive failures
# Usage: while true; do sh uom-watchdog.sh; sleep 60; done

set -u

UOM_DIR="${HOME}/src/universal-omni-master"
FAIL_FILE="${HOME}/.uom-termux-user/laptop_fail_count"
FAIL_THRESHOLD=3
STATE_FILE="${UOM_DIR}/.uom-agent/state.json"
LOG_FILE="${HOME}/.uom-termux-user/watchdog.log"

mkdir -p "$(dirname "${LOG_FILE}")" "$(dirname "${FAIL_FILE}")"

_log() {
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)
    printf '[watchdog] %s %s\n' "${_ts}" "$*" >> "${LOG_FILE}"
}

. "${UOM_DIR}/tools/uom-ip-discover.sh" 2>/dev/null || true

SOLO_PID_FILE="${HOME}/.uom-termux-user/solo-orchestrator.pid"

_laptop_reachable() {
    discover_laptop_ip >/dev/null 2>&1 || \
        ssh -o ConnectTimeout=2 -o BatchMode=yes -p 18022 127.0.0.1 true 2>/dev/null
}

if _laptop_reachable; then
    echo 0 > "${FAIL_FILE}"
    _log "Laptop reachable"

    CURRENT=$(jq -r .active_agent "${STATE_FILE}" 2>/dev/null || echo "unknown")
    if [ "${CURRENT}" = "phone-solo" ]; then
        _log "Laptop back online. Setting state to dual-pending (awaiting confirm)."
        jq '.active_agent="dual-pending"' "${STATE_FILE}" > /tmp/state_tmp.json 2>/dev/null && \
            mv /tmp/state_tmp.json "${STATE_FILE}"

        # Kill solo orchestrator if running
        if [ -f "${SOLO_PID_FILE}" ]; then
            _pid=$(cat "${SOLO_PID_FILE}")
            kill "${_pid}" 2>/dev/null || true
            rm -f "${SOLO_PID_FILE}"
            _log "Solo orchestrator (PID ${_pid}) stopped"
        fi
    fi
else
    FAILS=$(cat "${FAIL_FILE}" 2>/dev/null || echo 0)
    FAILS=$((FAILS + 1))
    echo "${FAILS}" > "${FAIL_FILE}"
    _log "Laptop unreachable. Fail count: ${FAILS}/${FAIL_THRESHOLD}"

    if [ "${FAILS}" -ge "${FAIL_THRESHOLD}" ]; then
        _log "THRESHOLD REACHED — triggering solo orchestrator"

        # Check if solo orchestrator is already running
        if [ -f "${SOLO_PID_FILE}" ] && kill -0 "$(cat "${SOLO_PID_FILE}")" 2>/dev/null; then
            _log "Solo orchestrator already running"
        else
            _log "Starting solo orchestrator..."
            nohup sh "${UOM_DIR}/orchestrators/uom-solo-orchestrator.sh" >/dev/null 2>&1 &
            echo $! > "${SOLO_PID_FILE}"
            _log "Solo orchestrator started (PID $(cat "${SOLO_PID_FILE}"))"
        fi
    fi
fi
