#!/bin/sh
# tools/uom-groq-verify.sh — Groq API verifier (free tier: 14,400 req/day)
# Usage: echo "code here" | sh tools/uom-groq-verify.sh
# Requires: GROQ_API_KEY env var (get free at https://console.groq.com/keys)
# POSIX sh. No bashisms.

set -u

GROQ_API_KEY="${GROQ_API_KEY:-}"
GROQ_MODEL="${GROQ_MODEL:-llama-3.1-8b-instant}"
GROQ_LOG="${UOM_LOG_DIR:-.uom-agent/logs}/groq-verify.log"

if [ -z "$GROQ_API_KEY" ]; then
    printf 'ERROR: GROQ_API_KEY not set. Get free key: https://console.groq.com/keys\n' >&2
    exit 1
fi

# Read stdin (code to verify)
_code=$(cat)

if [ -z "$_code" ]; then
    printf 'ERROR: No input on stdin\n' >&2
    exit 1
fi

# Build JSON payload (escape quotes and newlines)
_escaped=$(printf '%s' "$_code" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')

_payload=$(printf '{"model":"%s","messages":[{"role":"system","content":"You are a POSIX shell code verifier. Reply ONLY with PASS or FAIL followed by a 1-line reason. Max 20 words."},{"role":"user","content":"Verify this POSIX sh code for syntax errors, bashisms, and correctness:\\n%s"}],"temperature":0,"max_tokens":50}' "$GROQ_MODEL" "$_escaped")

# Call Groq API
_response=$(curl -s -m 15 \
    -H "Authorization: Bearer $GROQ_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$_payload" \
    "https://api.groq.com/openai/v1/chat/completions" 2>/dev/null)

# Extract response text
_result=$(printf '%s' "$_response" | grep -o '"content":"[^"]*"' | head -1 | sed 's/"content":"//;s/"$//')

# Log the call
printf '%s groq_verify %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${_result:-ERROR}" >> "$GROQ_LOG" 2>/dev/null

# Output result
if [ -n "$_result" ]; then
    printf '%s\n' "$_result"
else
    printf 'FAIL: Groq API returned empty response\n'
    exit 1
fi
