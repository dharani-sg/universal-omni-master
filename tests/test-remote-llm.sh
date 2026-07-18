#!/bin/sh
# tests/test-remote-llm.sh — End-to-end LLM pipeline test
# Runs locally if opencode CLI available, otherwise uses SSH to laptop.
# Validates response is non-empty. Prints PASS or FAIL.
# Usage: sh tests/test-remote-llm.sh

set -u

UOM_DIR="${UOM_DIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
TEST_OUT="${UOM_DIR}/.uom-agent/test-llm-output.txt"
LOG_FILE="${UOM_DIR}/.uom-agent/logs/test-remote-llm.log"

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$TEST_OUT")"

_log() {
    _ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u)"
    printf '[test-llm] %s %s\n' "$_ts" "$*" | tee -a "$LOG_FILE"
}

_test_prompt="Write a single-line POSIX shell function that prints 'hello from remote LLM'"
_llm_model="${LLM_MODEL:-opencode/deepseek-v4-flash-free}"
_llm_timeout=120
_start_ts=$(date +%s 2>/dev/null || echo 0)

_log "Testing LLM pipeline with model=${_llm_model}..."

# Method 1: local opencode (laptop)
_exit_code=1
if command -v opencode >/dev/null 2>&1; then
    _log "Method: local opencode"
    printf '%s\n' "$_test_prompt" | timeout "$_llm_timeout" opencode run --model "$_llm_model" > "$TEST_OUT" 2>>"$LOG_FILE"
    _exit_code=$?
fi

# Method 2: remote via uom-llm-remote.sh (phone → laptop SSH)
if [ "$_exit_code" -ne 0 ] && [ -f "${UOM_DIR}/scripts/uom-llm-remote.sh" ]; then
    _log "Method: remote SSH (uom-llm-remote.sh)"
    printf '%s\n' "$_test_prompt" | timeout "$_llm_timeout" sh "${UOM_DIR}/scripts/uom-llm-remote.sh" "$_llm_model" > "$TEST_OUT" 2>>"$LOG_FILE"
    _exit_code=$?
fi

_end_ts=$(date +%s 2>/dev/null || echo 0)
_elapsed=$((_end_ts - _start_ts))

if [ "$_exit_code" -ne 0 ]; then
    _log "FAIL: all methods failed (exit ${_exit_code}) after ${_elapsed}s"
    printf 'FAIL (exit %d, %ds)\n' "$_exit_code" "$_elapsed"
    exit 1
fi

if [ ! -s "$TEST_OUT" ]; then
    _log "FAIL: output empty after ${_elapsed}s"
    printf 'FAIL (empty output, %ds)\n' "$_elapsed"
    exit 1
fi

_lines=$(wc -l < "$TEST_OUT")
_log "PASS: generated ${_lines} lines in ${_elapsed}s"
printf 'PASS (%d lines, %ds)\n' "$_lines" "$_elapsed"
exit 0
