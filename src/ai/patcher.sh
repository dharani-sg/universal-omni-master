#!/bin/sh
# src/ai/patcher.sh — M24: AI-Automated Rectification & Telemetry.
# Strict POSIX compliance. Ephemeral API key lifecycle. Zero bashisms.

OMNI_AI_LOCAL_BIN="${OMNI_AI_LOCAL_BIN:-/media/usb/llm/bin/llama-cli}"
OMNI_AI_LOCAL_MODEL="${OMNI_AI_LOCAL_MODEL:-/media/usb/llm/models/qwen-coder.gguf}"

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

patcher_query_llm() {
    _context_file="$1"
    _patch_out="$2"

    # 1. Local LLM Path (Air-gapped)
    if [ -x "$OMNI_AI_LOCAL_BIN" ] && [ -f "$OMNI_AI_LOCAL_MODEL" ]; then
        "$OMNI_AI_LOCAL_BIN" \
            -m "$OMNI_AI_LOCAL_MODEL" \
            --ctx-size 8192 --temp 0.1 -n 512 \
            -p "Fix this POSIX shell script. Return ONLY the code inside \`\`\`sh blocks. No bashisms." \
            -f "$_context_file" > "$_patch_out" 2>/dev/null
        return $?
    fi

    # 2. Cloud API Path (Ephemeral Key)
    if [ -n "${OMNI_AI_API_KEY:-}" ]; then
        _tmp_payload="${TMPDIR:-/tmp}/omni-payload.$$"

        printf '{\n  "contents": [{\n    "parts": [{\n' > "$_tmp_payload"
        printf '      "text": "Fix this POSIX shell script. Return ONLY the code inside ```sh blocks. No bashisms, no eval."\n' >> "$_tmp_payload"
        printf '    }, {\n      "text": "' >> "$_tmp_payload"
        # Minimal JSON escaping for POSIX
        sed 's/"/\\"/g; s/$/\\n/g' "$_context_file" | tr -d '\n' >> "$_tmp_payload"
        printf '"\n    }]\n  }]\n}\n' >> "$_tmp_payload"

        curl -s -m 15 -X POST \
            -H "x-goog-api-key: $OMNI_AI_API_KEY" \
            -H "Content-Type: application/json" \
            -d @"$_tmp_payload" \
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent" > "${_patch_out}.raw" 2>/dev/null

        # Extract text safely and strip markdown blocks
        grep -o '"text": "[^"]*"' "${_patch_out}.raw" | tail -1 | sed 's/"text": "//;s/"$//;s/```sh//g;s/```//g;s/\\n/\n/g' > "$_patch_out"

        rm -f "$_tmp_payload" "${_patch_out}.raw"

        # Meter the AI usage via M23 SaaS engine if available
        if command -v saas_meter_event >/dev/null 2>&1; then
            saas_meter_event "ai_patch_query" >/dev/null 2>&1 || true
        fi

        # Ephemeral lifecycle enforcement
        unset OMNI_AI_API_KEY
        return 0
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
            [yY][eE][sS]|[yY])
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
