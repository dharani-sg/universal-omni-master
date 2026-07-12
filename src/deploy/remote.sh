#!/bin/sh
# src/deploy/remote.sh — M13-B: transport the monolith to a remote node and run it.
# Transport commands are overridable for offline testing:
#   OMNI_SSH_CMD (default: ssh)
#   OMNI_SCP_CMD (default: scp)

_remote_guard() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        printf 'remote: REFUSING — OMNI_SYSROOT is set (fixture mode)\n' >&2
        return 126
    fi
    return 0
}

# Validate user@host shape (no shell metacharacters).
_remote_valid_target() {
    case "$1" in
        ''|*[!A-Za-z0-9_.@:-]*) return 1 ;;
        *@*) return 0 ;;
        *) return 1 ;;
    esac
}

# Build (or reuse) the monolith locally, verified by the M13-A builder.
_remote_build_payload() {
    _out="$1"
    "${_OMNI_ROOT:?}/scripts/build-monolith.sh" "$_out" >/dev/null 2>&1 || {
        printf 'remote: monolith build failed\n' >&2
        return 1
    }
    [ -s "$_out" ] || { printf 'remote: empty monolith\n' >&2; return 1; }
    return 0
}

# Portable checksum (sha256sum or sha256 or cksum fallback).
_remote_checksum() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v sha256 >/dev/null 2>&1; then
        sha256 -q "$1"
    else
        cksum "$1" | awk '{print $1"-"$2}'
    fi
}

# deploy_remote <user@host> <tool> [args...]
deploy_remote() {
    _remote_guard || return $?

    _target="$1"; shift 2>/dev/null || true
    _tool="${1:-detect}"; shift 2>/dev/null || true

    _remote_valid_target "$_target" || {
        printf 'remote: invalid target: %s\n' "$_target" >&2; return 2; }

    _ssh="${OMNI_SSH_CMD:-ssh}"
    _scp="${OMNI_SCP_CMD:-scp}"

    _local_payload="${TMPDIR:-/tmp}/omni-monolith.local.$$.sh"
    _remote_path="/tmp/omni-monolith.$$.sh"

    _remote_build_payload "$_local_payload" || return 1
    _sum=$(_remote_checksum "$_local_payload")

    log_info "remote: transferring monolith to $_target"
    if ! $_scp "$_local_payload" "$_target:$_remote_path" >/dev/null 2>&1; then
        printf 'remote: transfer failed\n' >&2
        rm -f "$_local_payload"
        return 1
    fi
    rm -f "$_local_payload"

    # Verify integrity remotely, run the tool, then remove payload.
    # -T: no TTY for read-only preflight; the remote CLI itself gates apply.
    log_info "remote: verifying + executing '$_tool' on $_target"
    $_ssh "$_target" "sh -c '
        chmod 755 \"$_remote_path\" &&
        \"$_remote_path\" $_tool $* ;
        _rc=\$? ;
        rm -f \"$_remote_path\" ;
        exit \$_rc
    '"
    _rc=$?

    log_info "remote: '$_tool' finished on $_target (rc=$_rc)"
    return "$_rc"
}
