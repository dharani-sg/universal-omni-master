#!/bin/sh
# diag/network.sh — network readiness audit.

audit_network() {
    audit_section "NETWORK"

    if [ -n "${OMNI_SYSROOT:-}" ]; then
        f="$OMNI_SYSROOT/omni_fixture_network/ip"
        [ -r "$f" ] && audit_emit ok network "fixture IP=$(cat "$f")" || audit_emit unknown network "fixture network unknown"
        return 0
    fi

    ip4="$(ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127/ {print $2; exit}')"
    [ -n "$ip4" ] \
        && audit_emit ok network "IPv4=$ip4" \
        || audit_emit warn network "no non-loopback IPv4 address"

    if command -v getent >/dev/null 2>&1; then
        getent hosts voidlinux.org >/dev/null 2>&1 \
            && audit_emit ok network "DNS resolution OK" \
            || audit_emit warn network "DNS resolution failed"
    fi
}
