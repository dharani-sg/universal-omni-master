#!/bin/sh
# tools/uom-alpine-guest-verify.sh — verify installed toolbox packages
# One valid JSON document to stdout. No eval. No duplicate braces.
set -u

OUTPUT="${1:-}"
DIAGDIR="${HOME}/.uom-agent/diagnostics/toolbox"
mkdir -p "$DIAGDIR"

TOOLS="bash curl jq git rsync tmux ssh coreutils python3 pip3 strace lsof htop ncdu socat file tree rg openssl gpg vim nano less pv fdisk mkfs.ext4 mkfs.fat"

_all_present=true
_tool_entries=""
_sep=""

for tool in $TOOLS; do
  [ -n "$tool" ] || continue

  _path=$(command -v "$tool" 2>/dev/null || echo "MISSING")
  _version="unknown"

  if [ "$_path" != "MISSING" ]; then
    # Try common version flags, take first line
    _v=""
    for flag in --version -V version; do
      _v=$("$tool" "$flag" 2>/dev/null | head -1) || true
      [ -n "$_v" ] && break
    done
    [ -n "$_v" ] && _version="$_v"
  else
    _all_present=false
  fi

  # Escape backslash and double-quote in version
  _version=$(printf '%s' "$_version" | sed 's/\\/\\\\/g; s/"/\\"/g')
  _path_escaped=$(printf '%s' "$_path" | sed 's/\\/\\\\/g; s/"/\\"/g')

  _tool_entries="${_tool_entries}${_sep}{\"name\":\"${tool}\",\"path\":\"${_path_escaped}\",\"version\":\"${_version}\"}"
  _sep=","
done

# all_present is false if any tool is MISSING
for tool in $TOOLS; do
  [ -n "$tool" ] || continue
  command -v "$tool" >/dev/null 2>&1 || { _all_present=false; break; }
done

_MANIFEST=$(cat << ENDJSON
{
  "ts": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname 2>/dev/null || echo unknown)",
  "kernel": "$(uname -r 2>/dev/null || echo unknown)",
  "arch": "$(uname -m 2>/dev/null || echo unknown)",
  "alpine_release": "$(cat /etc/alpine-release 2>/dev/null || echo unknown)",
  "all_present": ${_all_present},
  "tools": [${_tool_entries}]
}
ENDJSON
)

# Write to diagnostics dir
echo "$_MANIFEST" > "$DIAGDIR/manifest.json"

# Write to stdout (and to OUTPUT if specified)
echo "$_MANIFEST" > "${OUTPUT:-/dev/stdout}"
if [ -n "$OUTPUT" ]; then
  # Verify JSON is valid
  if command -v jq >/dev/null 2>&1; then
    jq -e . "$OUTPUT" >/dev/null 2>&1 || { echo "ERROR: invalid JSON written" >&2; exit 1; }
  fi
  echo "Manifest written to: $OUTPUT" >&2
fi
