#!/bin/sh
# src/ai/patcher.sh — M24: AI-Automated Rectification & Telemetry.
# POSIX only. No eval. No bashisms. Ephemeral API key lifecycle.

OMNI_AI_LOCAL_BIN="${OMNI_AI_LOCAL_BIN:-/media/usb/llm/bin/llama-cli}"
OMNI_AI_LOCAL_MODEL="${OMNI_AI_LOCAL_MODEL:-/media/usb/llm/models/qwen-coder.gguf}"
OMNI_AI_API_KEY="${OMNI_AI_API_KEY:-}"

patcher_capture_context() {
    _failing_script="$1"
    _exit_code="$2"
    _log_file="$3"
    _output_ctx="$4"

    {
        printf '### SYSTEM STATE ERROR REPORT ###\n'
        printf 'Failing Script Target: %s\n' "$_failing_script"
        printf 'Exit Execution Code: %s\n' "$_exit_code"
        printf 'Timestamp of Event: %s\n' "$(date)"
        printf '\n--- Last 50 Lines of Execution Log ---\n'
        tail -n 50 "$_log_file" 2>/dev/null || true
        printf '\n--- Source Script Code Content ---\n'
        cat "$_failing_script" 2>/dev/null || true
    } > "$_output_ctx"
}

_PATCHER_PROMPT='Fix this POSIX shell script. Return only POSIX shell code. No markdown fences. No bashisms. No eval.'

# Extract the last JSON "text" value from a simple Gemini-style response.
# This is not a general JSON parser; it is a narrow backend-specific extractor.
_patcher_extract_text() {
    _raw="$1"
    _out="$2"

    sed -n 's/.*"text"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_raw" |
        tail -1 |
        sed 's/\\n/\
/g; s/\\"/"/g; s/```sh//g; s/```//g' > "$_out"

    [ -s "$_out" ]
}

patcher_query_llm() {
    _context_file="$1"
    _patch_out="$2"

    # 1. Local LLM path
    if [ -x "$OMNI_AI_LOCAL_BIN" ] && [ -f "$OMNI_AI_LOCAL_MODEL" ]; then
        "$OMNI_AI_LOCAL_BIN" \
            -m "$OMNI_AI_LOCAL_MODEL" \
            --ctx-size 8192 --temp 0.1 -n 512 \
            -p "$_PATCHER_PROMPT" \
            -f "$_context_file" > "$_patch_out" 2>/dev/null
        return $?
    fi

    # 2. Cloud API path
    if [ -n "$OMNI_AI_API_KEY" ]; then
        _tmp_payload="${TMPDIR:-/tmp}/omni-payload.$$"
        _tmp_raw="${_patch_out}.raw"

        {
            printf '{'
            printf '"contents":[{"parts":[{"text":"'
            printf '%s' "$_PATCHER_PROMPT" | sed 's/\\/\\\\/g; s/"/\\"/g'
            printf '"},{"text":"'
            sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/g' "$_context_file" | tr -d '\n'
            printf '"}]}]'
            printf '}\n'
        } > "$_tmp_payload"

        curl -s -m 15 -X POST \
            -H "x-goog-api-key: $OMNI_AI_API_KEY" \
            -H "Content-Type: application/json" \
            -d @"$_tmp_payload" \
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent" \
            > "$_tmp_raw" 2>/dev/null || true

        _patch_rc=1
        if _patcher_extract_text "$_tmp_raw" "$_patch_out"; then
            _patch_rc=0
        else
            printf 'patcher: cloud response contained no extractable patch text\n' >&2
            : > "$_patch_out"
        fi

        rm -f "$_tmp_payload" "$_tmp_raw"

        if command -v saas_meter_event >/dev/null 2>&1; then
            saas_meter_event "ai_patch_query" >/dev/null 2>&1 || true
        fi

        unset OMNI_AI_API_KEY
        return "$_patch_rc"
    fi

    printf 'patcher: No local LLM or OMNI_AI_API_KEY found.\n' >&2
    return 1
}

patcher_apply_safe() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        printf 'patcher: REFUSING mutation — OMNI_SYSROOT set\n' >&2
        return 126
    fi

    _target_script="$1"
    _suggested_patch="$2"

    if sh -n "$_suggested_patch" 2>/dev/null; then
        printf 'patcher: Syntax Check Passed. Apply correction to %s? (y/N): ' "$_target_script"
        read -r _choice
        case "$_choice" in
            [yY]|[yY][eE][sS])
                cp "$_target_script" "${_target_script}.bak" 2>/dev/null || true
                mv -f "$_suggested_patch" "$_target_script"
                chmod 755 "$_target_script"
                printf 'patcher: System patch successfully applied\n'
                ;;
            *)
                printf 'patcher: Application aborted by operator\n'
                return 1
                ;;
        esac
    else
        printf 'patcher: CRITICAL ERROR - AI patch failed structural syntax check (sh -n)\n' >&2
        return 126
    fi
}
