#!/bin/sh
# diag/common.sh — audit scoring helpers (read-only).

# Severity accumulator: 0=ok, 1=warn, 2=critical
OMNI_AUDIT_SEVERITY=0

_audit_raise() {
    # _audit_raise <level>  where level is 1 or 2
    _lvl="$1"
    case "$_lvl" in
        1) [ "$OMNI_AUDIT_SEVERITY" -lt 1 ] && OMNI_AUDIT_SEVERITY=1 ;;
        2) OMNI_AUDIT_SEVERITY=2 ;;
    esac
}

_audit_ok()   { printf '  [ OK ]  %s\n' "$1"; }
_audit_info() { printf '  [INFO]  %s\n' "$1"; }
_audit_warn() { printf '  [WARN]  %s\n' "$1"; _audit_raise 1; }
_audit_crit() { printf '  [CRIT]  %s\n' "$1"; _audit_raise 2; }

_audit_section() {
    printf '\n═══ %s ═══\n' "$1"
}
