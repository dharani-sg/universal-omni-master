#!/bin/sh
# bin/uom-resume.sh — Resume UOM session: detect state, reattach/recover
# Run after returning to laptop or when reconnecting
# Usage: sh bin/uom-resume.sh

set -u

UOM_DIR="${HOME}/src/universal-omni-master"
STATE_FILE="${UOM_DIR}/.uom-agent/state.json"
LOG_FILE="${HOME}/.uom-termux-user/resume.log"

. "${UOM_DIR}/tools/uom-ip-discover.sh" 2>/dev/null || true

mkdir -p "$(dirname "${LOG_FILE}")"

_log() {
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)
    printf '[resume] %s %s\n' "${_ts}" "$*" >> "${LOG_FILE}"
    echo "$*"
}

_check_tunnel() {
    ssh -o ConnectTimeout=3 -o BatchMode=yes -p 31415 127.0.0.1 true 2>/dev/null
}

_get_state() {
    jq -r ".$1 // \"unknown\"" "${STATE_FILE}" 2>/dev/null || echo "unknown"
}

_check_tmux_session() {
    tmux has-session -t uom-hybrid 2>/dev/null || tmux has-session -t uom 2>/dev/null
}

main() {
    _log "=== UOM Resume ==="

    _active_agent=$(_get_state "active_agent")
    _task_status=$(_get_state "task_status")
    _task_id=$(_get_state "current_task_id")

    _log "State: active_agent=${_active_agent}, task=${_task_id}, status=${_task_status}"

    echo ""
    echo "=========================================="
    echo " UOM Session Resume"
    echo "=========================================="
    echo " Active agent: ${_active_agent}"
    echo " Current task: ${_task_id}"
    echo " Task status:  ${_task_status}"
    echo ""

    if _check_tmux_session 2>/dev/null; then
        echo " Tmux session 'uom-hybrid' exists."
        echo " Attach: tmux attach -t uom-hybrid"
        echo ""
        echo " Or kill and restart:"
        echo "   tmux kill-session -t uom-hybrid && sh bin/uom-hybrid.sh --daemon"
        echo ""
    fi

    if _check_tunnel; then
        echo " Reverse tunnel: UP (127.0.0.1:31415)"
    else
        echo " Reverse tunnel: DOWN"
        echo " Start: sh bin/uom-reverse-ssh.sh"
    fi

    if discover_laptop_ip >/dev/null 2>&1; then
        echo " Laptop: REACHABLE"
        if [ "${_active_agent}" = "phone-solo" ]; then
            echo ""
            echo " >>> Laptop recovered from solo mode. <<<"
            echo " Run: sh -c 'jq \".active_agent=\\\"dual-pending\\\"\" .uom-agent/state.json > \"\${TMPDIR:-/tmp}/uom-s.json\" && mv \"\${TMPDIR:-/tmp}/uom-s.json\" .uom-agent/state.json'"
            echo " Then: tmux kill-session -t uom-hybrid && sh bin/uom-hybrid.sh --daemon"
        fi
    else
        echo " Laptop: UNREACHABLE"
        echo " Mode: solo (phone-only)"
        echo ""
        echo " To start solo mode: cd ~/src/universal-omni-master && sh bin/uom-hybrid.sh"
    fi

    echo ""
    echo " Quick commands:"
    echo "   tmux attach -t uom-hybrid        # Attach to running session"
    echo "   sh bin/uom-hybrid.sh              # Start hybrid orchestrator"
    echo "   sh bin/uom-reverse-ssh.sh        # Start reverse tunnel"
    echo "   sh scripts/uom-reconcile.sh      # 6-step: preflight -> tmux -> boot -> tunnel -> guardian -> zen"
    echo "   sh scripts/uom-generator.sh ...  # Cloud code generator (opencode stdin)"
    echo "   sh scripts/uom-verifier.sh ...   # Syntax/policy verifier"
    echo "   cat .uom-agent/state.json        # Check current state"
    echo "   cat .uom-agent/queue.json        # Check pending tasks"
    echo "=========================================="
}

main "$@"
