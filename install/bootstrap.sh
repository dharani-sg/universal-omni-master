#!/bin/sh
# install/bootstrap.sh — Universal bootstrap: auto-detects platform
# Safe download-validate-execute pattern. Forwards all arguments.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh -o /tmp/uom-install.sh && sh /tmp/uom-install.sh --apply --verify
#   sh install/bootstrap.sh --check
#   sh install/bootstrap.sh --apply --verify --profile phone-relay

set -eu

# ── Configuration ────────────────────────────────────────────────────────
REPO_RAW="https://raw.githubusercontent.com/dharani-sg/universal-omni-master"
BRANCH="${UOM_REF:-main}"
BASE="${REPO_RAW}/${BRANCH}/install"
MAX_CHILD_SIZE=512000  # 500 KB max for child script

# ── Cleanup trap ─────────────────────────────────────────────────────────
_CHILD_TMP=""
cleanup() { [ -n "$_CHILD_TMP" ] && [ -f "$_CHILD_TMP" ] && rm -f "$_CHILD_TMP"; }
trap cleanup EXIT INT TERM HUP

# ── Helpers ──────────────────────────────────────────────────────────────
die()  { printf '[FATAL] %s\n' "$*" >&2; exit 1; }
warn() { printf '[!] %s\n' "$*" >&2; }

# ── Detect platform ──────────────────────────────────────────────────────
CHILD_SCRIPT=""
if [ -d "/data/data/com.termux" ] || { [ -n "${PREFIX:-}" ] && echo "$PREFIX" | grep -q termux 2>/dev/null; }; then
  printf '[UOM] Detected: Termux/Android\n'
  CHILD_SCRIPT="bootstrap-termux.sh"
elif [ -f "/etc/alpine-release" ]; then
  printf '[UOM] Detected: Alpine Linux\n'
  CHILD_SCRIPT="bootstrap-laptop.sh"
else
  printf '[UOM] Unknown platform. Supported: Termux (Android), Alpine Linux\n'
  printf 'Manual: https://github.com/dharani-sg/universal-omni-master\n'
  exit 1
fi

# ── Download to temporary file ───────────────────────────────────────────
_CHILD_URL="${BASE}/${CHILD_SCRIPT}"
_CHILD_TMP="$(mktemp "${TMPDIR:-/tmp}/uom-child-XXXXXX.sh")"

printf '[UOM] Downloading %s ...\n' "$CHILD_SCRIPT"
if command -v curl >/dev/null 2>&1; then
  curl -fSL \
    --connect-timeout 15 \
    --max-time 60 \
    --retry 3 \
    --retry-delay 2 \
    -o "$_CHILD_TMP" \
    "$_CHILD_URL" || die "Download failed: $_CHILD_URL"
elif command -v wget >/dev/null 2>&1; then
  wget -q --timeout=30 -O "$_CHILD_TMP" "$_CHILD_URL" \
    || die "Download failed: $_CHILD_URL"
else
  die "Neither curl nor wget available. Install one and retry."
fi

# ── Validate downloaded content ──────────────────────────────────────────
[ -s "$_CHILD_TMP" ] || die "Downloaded file is empty"

# Check file size
_CHILD_SIZE=$(wc -c < "$_CHILD_TMP" 2>/dev/null || echo 0)
[ "$_CHILD_SIZE" -lt "$MAX_CHILD_SIZE" ] \
  || die "Downloaded file too large: ${_CHILD_SIZE} bytes (max ${MAX_CHILD_SIZE})"

# Check shebang
_HEAD1=$(head -1 "$_CHILD_TMP" 2>/dev/null || true)
case "$_HEAD1" in
  '#!'*) ;;
  *) die "Downloaded file has no shebang. May not be a shell script." ;;
esac

# Reject HTML error pages
if grep -qiE '<!DOCTYPE|<html|<head|<body' "$_CHILD_TMP" 2>/dev/null; then
  die "Downloaded file appears to be HTML, not a shell script."
fi

# Syntax check
sh -n "$_CHILD_TMP" || die "Downloaded script has syntax errors"

printf '[UOM] Downloaded and validated: %s (%s bytes)\n' "$CHILD_SCRIPT" "$_CHILD_SIZE"

# ── Execute child with forwarded arguments ───────────────────────────────
# shellcheck disable=SC2086
exec sh "$_CHILD_TMP" "$@"
