#!/bin/sh
# scripts/uom-llm-remote.sh — Remote LLM invocation via SSH to laptop
# Uses opencode run (non-TUI) for clean text output.
# Base64-encodes prompt for reliable transport through SSH pipes.
#
# Usage: printf 'prompt' | sh scripts/uom-llm-remote.sh [model]
#
# Environment:
#   UOM_LAPTOP_HOST  — laptop IP (default: 192.168.40.90)
#   UOM_LAPTOP_USER  — laptop SSH user (default: alpine)
#   UOM_LAPTOP_DIR   — laptop project dir

set -u

UOM_DIR="${UOM_DIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
LAPTOP_USER="${UOM_LAPTOP_USER:-alpine}"
LAPTOP_DIR="${UOM_LAPTOP_DIR:-/home/alpine/src/universal-omni-master}"

# Use model rotation to get current model
_ROTATE="${UOM_DIR}/tools/uom-model-rotate.sh"
if [ -x "$_ROTATE" ]; then
    MODEL="${1:-$(sh "$_ROTATE" current 2>/dev/null || echo "opencode/deepseek-v4-flash-free")}"
else
    MODEL="${1:-opencode/deepseek-v4-flash-free}"
fi
SSH_TIMEOUT=10
LLM_TIMEOUT=120

# ── Dynamic laptop IP discovery ────────────────────────────────────────
_DISCOVER_LIB="${UOM_DIR}/tools/uom-ip-discover.sh"
if [ -f "$_DISCOVER_LIB" ]; then
    . "$_DISCOVER_LIB" 2>/dev/null || true
fi

LAPTOP_HOST="${UOM_LAPTOP_HOST:-}"
if [ -z "$LAPTOP_HOST" ]; then
    if command -v discover_laptop_ip >/dev/null 2>&1; then
        LAPTOP_HOST="$(discover_laptop_ip 2>/dev/null || echo "")"
    fi
    if [ -z "$LAPTOP_HOST" ] && [ -f "${UOM_DIR}/.uom-agent/laptop.ip" ]; then
        LAPTOP_HOST="$(cat "${UOM_DIR}/.uom-agent/laptop.ip" 2>/dev/null || echo "")"
    fi
    LAPTOP_HOST="${LAPTOP_HOST:-127.0.0.1}"
fi

_log() {
    _ts=$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date)
    printf '[llm-remote] %s %s\n' "$_ts" "$*" >&2
}

_prompt_b64=$(cat | base64 -w0 2>/dev/null || cat | base64 2>/dev/null)

if [ -z "$_prompt_b64" ]; then
    _log "ERROR: empty prompt"
    exit 1
fi

if ! ping -c 1 -W 2 "$LAPTOP_HOST" >/dev/null 2>&1; then
    _log "ERROR: laptop $LAPTOP_HOST unreachable"
    exit 1
fi

_log "Invoking opencode run on ${LAPTOP_USER}@${LAPTOP_HOST} (model=${MODEL})"

_remote_cmd="cd '${LAPTOP_DIR}' && printf '%s' '${_prompt_b64}' | base64 -d | timeout '${LLM_TIMEOUT}' opencode run --model '${MODEL}' 2>/dev/null"

_ssh_cmd="ssh -o ConnectTimeout=${SSH_TIMEOUT} -o BatchMode=yes"
if [ -f "${HOME}/.ssh/config" ] && grep -q 'uom-laptop' "${HOME}/.ssh/config" 2>/dev/null; then
    _ssh_cmd="ssh -o ConnectTimeout=${SSH_TIMEOUT} -o BatchMode=yes"
    _ssh_host="uom-laptop-lan"
else
    _ssh_cmd="ssh -o ConnectTimeout=${SSH_TIMEOUT} -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
    _ssh_host="${LAPTOP_USER}@${LAPTOP_HOST}"
fi

_output=$(${_ssh_cmd} "${_ssh_host}" "$_remote_cmd" 2>/dev/null)

_rc=$?

if [ "$_rc" -ne 0 ]; then
    _log "ERROR: SSH/opencode returned rc=$_rc"
    exit 1
fi

if [ -z "$_output" ]; then
    _log "ERROR: empty response from remote opencode"
    exit 1
fi

_log "Received $(printf '%s' "$_output" | wc -l) lines"
printf '%s' "$_output"
exit 0
