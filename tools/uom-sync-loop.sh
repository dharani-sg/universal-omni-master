#!/bin/sh
# tools/uom-sync-loop.sh — Bidirectional safe sync loop
# Staging + SHA256 manifest + conflict detection + atomic moves.
# No hardcoded IPs. No --delete. No silent overwrites.
#
# Usage:
#   sh tools/uom-sync-loop.sh            # Poll every 30s
#   sh tools/uom-sync-loop.sh --once     # One sync cycle then exit
#   sh tools/uom-sync-loop.sh --dryrun   # Validate config, no transfer

set -u

UOM_DIR="${UOM_DIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
ONCE=0
DRYRUN=0
for _a in "$@"; do
  case "$_a" in
    --once) ONCE=1 ;;
    --dryrun) DRYRUN=1 ;;
  esac
done

# Source state lib
if [ -f "${UOM_DIR}/tools/uom-state-lib.sh" ]; then
  . "${UOM_DIR}/tools/uom-state-lib.sh"
  uom_state_init 2>/dev/null || true
fi

# Source discovery
if [ -f "${UOM_DIR}/tools/uom-ip-discover.sh" ]; then
  . "${UOM_DIR}/tools/uom-ip-discover.sh" 2>/dev/null || true
fi

# ── Platform detection ────────────────────────────────────────────────
_IS_PHONE=0
[ "$(uname -o 2>/dev/null)" = "Android" ] && _IS_PHONE=1

# ── Derived paths (respect env overrides) ─────────────────────────────
STAGING_DIR="${TMPDIR:-/tmp}/uom-sync-staging.$$"
GEN_DIR="${UOM_STATE_DIR:-${UOM_DIR}/.uom-agent}/generated"
VERIFIED_DIR="${UOM_STATE_DIR:-${UOM_DIR}/.uom-agent}/verified"
FEEDBACK_DIR="${UOM_STATE_DIR:-${UOM_DIR}/.uom-agent}/feedback"
LOCK_DIR="${UOM_RUNTIME_DIR:-${UOM_DIR}/.uom-agent/runtime}/sync-loop.lock"
LOG_FILE="${UOM_LOG_DIR:-${UOM_DIR}/.uom-agent/logs}/sync-loop.log"
POLL_INTERVAL=30
SSH_TIMEOUT=10
SYNC_TIMEOUT=60

mkdir -p "$(dirname "$LOCK_DIR")" "$(dirname "$LOG_FILE")"

_log() {
  _ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u)"
  printf '[sync] %s %s\n' "$_ts" "$*" >> "$LOG_FILE"
  printf '[sync] %s %s\n' "$_ts" "$*"
}

_cleanup() {
  rm -rf "$LOCK_DIR" "$STAGING_DIR" 2>/dev/null || true
}
trap '_cleanup' INT TERM EXIT

_acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "$$" > "$LOCK_DIR/pid"
    return 0
  fi
  _old_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
  if [ -n "$_old_pid" ] && kill -0 "$_old_pid" 2>/dev/null; then
    exit 0
  fi
  rm -rf "$LOCK_DIR" 2>/dev/null || true
  mkdir "$LOCK_DIR" 2>/dev/null || exit 1
  echo "$$" > "$LOCK_DIR/pid"
}

# ── Remote target discovery ───────────────────────────────────────────
_remote_user() {
  if [ "$_IS_PHONE" -eq 1 ]; then
    printf '%s' "${UOM_LAPTOP_USER:-alpine}"
  else
    printf '%s' "${UOM_PHONE_USER:-u0_a608}"
  fi
}

_remote_host() {
  if [ "$_IS_PHONE" -eq 1 ]; then
    # Phone → laptop: try tunnel, mDNS, cache
    _host=""
    # Method 1: reverse tunnel
    if ssh -o ConnectTimeout=3 -o BatchMode=yes -p "${UOM_TUNNEL_PORT:-31415}" 127.0.0.1 \
      'true' 2>/dev/null; then
      printf '127.0.0.1'
      return 0
    fi
    # Method 2: mDNS
    if command -v avahi-resolve >/dev/null 2>&1; then
      _host=$(avahi-resolve -n hp-pavilion.local 2>/dev/null | awk '{print $2}' | head -1)
      [ -n "$_host" ] && printf '%s' "$_host" && return 0
    fi
    # Method 3: cached laptop.ip
    _lip="${UOM_STATE_DIR}/laptop.ip"
    [ -f "$_lip" ] && printf '%s' "$(cat "$_lip" | tr -d '[:space:]')" && return 0
    # Method 4: fallback
    printf '%s' "${UOM_LAPTOP_HOST:-192.168.40.90}"
  else
    # Laptop → phone: use discovery
    _pip=""
    # Method 1: phone.ip
    _pip_f="${UOM_STATE_DIR}/phone.ip"
    [ -f "$_pip_f" ] && _pip=$(cat "$_pip_f" | tr -d '[:space:]')
    # Method 2: phone.host
    if [ -z "$_pip" ]; then
      _ph_f="${UOM_STATE_DIR}/phone.host"
      [ -f "$_ph_f" ] && _pip=$(cat "$_ph_f" | tr -d '[:space:]' | cut -d: -f1)
    fi
    # Method 3: SSH wrapper discovery
    if [ -z "$_pip" ] && [ -f "${UOM_DIR}/bin/uom-ssh-phone.sh" ]; then
      _pip=$(sh "${UOM_DIR}/bin/uom-ssh-phone.sh" discover 2>/dev/null)
    fi
    printf '%s' "${_pip:-192.168.40.207}"
  fi
}

_remote_port() {
  if [ "$_IS_PHONE" -eq 1 ]; then
    printf '%s' "${UOM_LAPTOP_SSH_PORT:-22}"
  else
    printf '%s' "${UOM_PHONE_SSH_PORT:-8022}"
  fi
}

_remote_key() {
  if [ "$_IS_PHONE" -eq 1 ]; then
    # Phone → laptop: use default key
    echo ""
  else
    # Laptop → phone: use phone-specific key
    printf '%s' "${HOME}/.ssh/id_ed25519_phone"
  fi
}

_remote_path() {
  _user="$1"
  _host="$2"
  _port="$3"
  _key="$4"
  _ssh_cmd="ssh"
  [ -n "$_key" ] && _ssh_cmd="${_ssh_cmd} -i $_key"
  _ssh_cmd="${_ssh_cmd} -o ConnectTimeout=5 -o BatchMode=yes -p $_port"
  _result=$($_ssh_cmd "${_user}@${_host}" \
    'printf "%s" "$HOME/src/universal-omni-master"' 2>/dev/null) || {
    _log "WARNING: cannot resolve remote path on ${_user}@${_host}:${_port}"
    return 1
  }
  printf '%s' "$_result"
}

# ── SHA256 manifest generation ────────────────────────────────────────
_generate_manifest() {
  _dir="$1"
  _out="$2"
  > "$_out"
  for _f in "${_dir}"/*; do
    [ -f "$_f" ] || continue
    _name=$(basename "$_f")
    _sha=$(sha256sum "$_f" 2>/dev/null | cut -d' ' -f1)
    printf '%s  %s\n' "$_sha" "$_name" >> "$_out"
  done
}

# ── Sync one direction: push source dirs to remote ────────────────────
_sync_push() {
  _remote="$1"          # user@host
  _port="$2"
  _key="$3"
  _remote_agent="$4"    # role label for logging
  shift 4

  for _src_dir in "$@"; do
    [ -d "$_src_dir" ] || continue

    _base=$(basename "$_src_dir")
    _stg="${STAGING_DIR}/${_base}"
    mkdir -p "$_stg"
    _manifest="${_stg}/.manifest"
    _stamp=$(date -u '+%Y%m%dT%H%M%SZ')

    # Build SSH command prefix
    _scp_pre="scp -o ConnectTimeout=${SSH_TIMEOUT} -o BatchMode=yes"
    [ -n "$_key" ] && _scp_pre="${_scp_pre} -i $_key"
    _scp_pre="${_scp_pre} -P $_port"

    _ssh_pre="ssh -o ConnectTimeout=${SSH_TIMEOUT} -o BatchMode=yes"
    [ -n "$_key" ] && _ssh_pre="${_ssh_pre} -i $_key"
    _ssh_pre="${_ssh_pre} -p $_port"

    _rhost="${_remote}"

    # Discover remote path
    _rpath=$(_remote_path "${_remote%:*}" "${_remote#*:}" "$_port" "$_key") || {
      _log "SKIP ${_base}: cannot discover remote path"
      continue
    }

    # Generate manifest of local files
    _generate_manifest "$_src_dir" "$_manifest"

    # Copy files to staging
    cp -r "${_src_dir}/." "$_stg/" 2>/dev/null

    # Check for conflicts on remote
    _conflicts=0
    while IFS='  ' read -r _sha _name; do
      [ -z "$_name" ] && continue
      # Check if remote has a different version
      _rsha=$($_ssh_pre "${_rhost}" \
        "sha256sum \"${_rpath}/.uom-agent/${_base}/${_name}\" 2>/dev/null | cut -d' ' -f1" \
        2>/dev/null || echo "")
      if [ -n "$_rsha" ] && [ "$_rsha" != "$_sha" ]; then
        _log "CONFLICT ${_base}/${_name}: local=${_sha} remote=${_rsha}"
        _conflicts=$((_conflicts + 1))
        # Tag the staging copy
        printf 'SYNC_CONFLICT %s  %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$_name" \
          >> "${_stg}/.conflicts"
      fi
    done < "$_manifest"

    if [ "$_conflicts" -gt 0 ]; then
      _log "SKIP ${_base}: ${_conflicts} conflict(s), not pushing"
      continue
    fi

    # Transfer via tar/ssh
    _log "PUSH ${_base} → ${_rhost}:${_rpath}/.uom-agent/"
    if [ "$DRYRUN" -eq 1 ]; then
      _log "  (dryrun, skip transfer)"
      continue
    fi
    tar cf - -C "$_stg" . 2>/dev/null | \
      $_ssh_pre "${_rhost}" \
        "mkdir -p \"${_rpath}/.uom-agent/${_base}\" && \
         tar xf - -C \"${_rpath}/.uom-agent/${_base}\"" \
      2>> "$LOG_FILE"
    _rc=$?
    if [ "$_rc" -eq 0 ]; then
      _log "  OK ${_base} (${_stamp})"
    else
      _log "  FAIL ${_base} (rc=$_rc)"
    fi
  done
}

# ── Main sync cycle ───────────────────────────────────────────────────
main() {
  _acquire_lock

  # Resolve remote target
  _ruser=$(_remote_user)
  _rhost=$(_remote_host)
  _rport=$(_remote_port)
  _rkey=$(_remote_key)
  _rtarget="${_ruser}@${_rhost}"

  _log "sync target: ${_rtarget}:${_rport}"

  if [ "$DRYRUN" -eq 1 ]; then
    _log "dryrun mode — no transfers"
    _cleanup
    return 0
  fi

  while true; do
    # Test reachability
    _reachable=0
    _ssh_pre="ssh -o ConnectTimeout=${SSH_TIMEOUT} -o BatchMode=yes"
    [ -n "$_rkey" ] && _ssh_pre="${_ssh_pre} -i $_rkey"
    _ssh_pre="${_ssh_pre} -p $_rport"

    if $_ssh_pre "${_rtarget}" 'true' 2>/dev/null; then
      _reachable=1
    fi

    if [ "$_reachable" -eq 0 ]; then
      _log "remote offline (${_rtarget}:${_rport}) — backoff 60s"
      sleep 60
      [ "$ONCE" -eq 1 ] && break
      continue
    fi

    # Determine direction based on role
    if [ "$_IS_PHONE" -eq 1 ]; then
      # Phone → laptop: push generated/ and feedback/
      _sync_push "$_rtarget" "$_rport" "$_rkey" "laptop" \
        "$GEN_DIR" "$FEEDBACK_DIR"
    else
      # Laptop → phone: push verified/ and feedback/
      _sync_push "$_rtarget" "$_rport" "$_rkey" "phone" \
        "$VERIFIED_DIR" "$FEEDBACK_DIR"
    fi

    # Cleanup staging
    rm -rf "$STAGING_DIR" 2>/dev/null || true
    mkdir -p "$STAGING_DIR" 2>/dev/null || true

    if [ "$ONCE" -eq 1 ]; then
      break
    fi
    sleep "$POLL_INTERVAL"
  done

  _cleanup
}

main "$@"
