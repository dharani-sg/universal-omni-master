#!/bin/sh
# diag/common.sh — severity engine and output layer.

OMNI_AUDIT_FORMAT="${OMNI_AUDIT_FORMAT:-human}"  # human|json
OMNI_AUDIT_TMP="${OMNI_AUDIT_TMP:-/tmp/omni-audit-$$}"
OMNI_AUDIT_SEV="$OMNI_AUDIT_TMP/severity"
OMNI_AUDIT_FINDINGS="$OMNI_AUDIT_TMP/findings"

mkdir -p "$OMNI_AUDIT_TMP" || exit 4
echo 0 > "$OMNI_AUDIT_SEV"
: > "$OMNI_AUDIT_FINDINGS"

audit_cleanup() {
    rm -rf "$OMNI_AUDIT_TMP"
}

audit_level_num() {
    case "$1" in
        ok|info) echo 0 ;;
        warn|unknown) echo 1 ;;
        fail) echo 2 ;;
        critical) echo 3 ;;
        internal) echo 4 ;;
        *) echo 4 ;;
    esac
}

audit_raise() {
    _new="$(audit_level_num "$1")"
    _old="$(cat "$OMNI_AUDIT_SEV" 2>/dev/null || echo 0)"
    [ "$_new" -gt "$_old" ] && echo "$_new" > "$OMNI_AUDIT_SEV"
}

audit_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

audit_emit() {
    _sev="$1"
    _component="$2"
    _message="$3"

    audit_raise "$_sev"

    if [ "$OMNI_AUDIT_FORMAT" = "json" ]; then
        printf '%s|%s|%s\n' "$_sev" "$_component" "$_message" >> "$OMNI_AUDIT_FINDINGS"
        return 0
    fi

    case "$_sev" in
        ok)       _tag="[ OK ]" ;;
        info)     _tag="[INFO]" ;;
        warn)     _tag="[WARN]" ;;
        unknown)  _tag="[UNKN]" ;;
        fail)     _tag="[FAIL]" ;;
        critical) _tag="[CRIT]" ;;
        internal) _tag="[INT ]" ;;
        *)        _tag="[????]" ;;
    esac

    printf '  %-6s %-12s %s\n' "$_tag" "$_component" "$_message"
}

audit_section() {
    [ "$OMNI_AUDIT_FORMAT" = "json" ] && return 0
    printf '\n════════ %s ════════\n' "$1"
}

audit_exit_code() {
    cat "$OMNI_AUDIT_SEV" 2>/dev/null || echo 4
}

audit_json_finish() {
    _exit="$(audit_exit_code)"
    printf '{\n'
    printf '  "exit_code": %s,\n' "$_exit"
    printf '  "findings": [\n'

    _first=1
    while IFS='|' read -r sev comp msg; do
        [ -n "$sev" ] || continue
        [ "$_first" -eq 0 ] && printf ',\n'
        _first=0
        printf '    {"severity":"%s","component":"%s","message":"%s"}' \
            "$(audit_escape "$sev")" \
            "$(audit_escape "$comp")" \
            "$(audit_escape "$msg")"
    done < "$OMNI_AUDIT_FINDINGS"

    printf '\n  ]\n}\n'
}
