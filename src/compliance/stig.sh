#!/bin/sh
# src/compliance/stig.sh — M25: Fleet STIG/CIS Compliance Engine.
# Pure POSIX. Idempotent. Zero bashisms.
# OMNI_SSHD_CONFIG: override sshd_config path (used by tests).

OMNI_COMPLIANCE_LOG="${OMNI_COMPLIANCE_LOG:-/var/log/omni-compliance.ndjson}"
OMNI_SSHD_CONFIG="${OMNI_SSHD_CONFIG:-/etc/ssh/sshd_config}"

# compliance_check_sshd <rule> <expected>
# Returns 0 if the rule is already set to expected value; 1 otherwise.
compliance_check_sshd() {
    _rule="$1"
    _expected="$2"

    [ -f "$OMNI_SSHD_CONFIG" ] || return 1

    # Extract the last active (uncommented) value for the rule.
    _actual=$(grep -i "^[[:space:]]*${_rule}[[:space:]]" \
        "$OMNI_SSHD_CONFIG" | awk '{print $2}' | tail -1)

    [ "$_actual" = "$_expected" ]
}

# compliance_enforce_sshd <rule> <expected>
# Idempotently enforces the rule. Logs remediation to NDJSON.
# Returns 126 if OMNI_SYSROOT is set.
compliance_enforce_sshd() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        printf 'compliance: REFUSING mutation — OMNI_SYSROOT set\n' >&2
        return 126
    fi

    _rule="$1"
    _expected="$2"

    # Already compliant — do nothing.
    if compliance_check_sshd "$_rule" "$_expected"; then
        return 0
    fi

    [ -f "$OMNI_SSHD_CONFIG" ] || return 1

    _tmp="${OMNI_SSHD_CONFIG}.tmp.$$"

    # Remove any existing rule line (case-insensitive), then append.
    grep -vi "^[[:space:]]*${_rule}[[:space:]]" \
        "$OMNI_SSHD_CONFIG" > "$_tmp" 2>/dev/null || true
    printf '%s %s\n' "$_rule" "$_expected" >> "$_tmp"
    mv "$_tmp" "$OMNI_SSHD_CONFIG"

    # Log the remediation to NDJSON.
    _ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    mkdir -p "$(dirname "$OMNI_COMPLIANCE_LOG")" 2>/dev/null || true
    printf '{"ts":"%s","action":"enforce_sshd","rule":"%s","value":"%s"}\n' \
        "$_ts" "$_rule" "$_expected" >> "$OMNI_COMPLIANCE_LOG" 2>/dev/null || true

    return 0
}

# compliance_audit_profile <profile>
# Returns 0 if fully compliant; 1 if drift detected; 2 if unknown profile.
compliance_audit_profile() {
    _profile="$1"
    _drift=0

    case "$_profile" in
        cis_level_1|stig_high)
            compliance_check_sshd "PermitRootLogin"        "no" || _drift=1
            compliance_check_sshd "PasswordAuthentication" "no" || _drift=1
            compliance_check_sshd "MaxAuthTries"           "3"  || _drift=1
            ;;
        *)
            printf 'compliance: unknown profile: %s\n' "$_profile" >&2
            return 2
            ;;
    esac

    return "$_drift"
}
