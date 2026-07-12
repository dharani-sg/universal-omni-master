#!/bin/sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
_c() { [ "$2" = "$3" ] && { printf '  PASS %-45s = %s\n' "$1" "$3"; PASS=$((PASS+1)); } || { printf '  FAIL %-45s want=%s got=%s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); }; }

echo "=== M13-B Remote Transport Tests (offline mock) ==="
. "$ROOT/src/core/logging.sh" 2>/dev/null || true
. "$ROOT/src/deploy/remote.sh"
_OMNI_ROOT="$ROOT"; export _OMNI_ROOT

sh -n "$ROOT/src/deploy/remote.sh" && _c "remote.sh syntax" ok ok || _c "remote.sh syntax" ok fail

# invalid targets rejected
rc=0; deploy_remote "nothost" detect >/dev/null 2>&1 || rc=$?; _c "reject bad target" 2 "$rc"
rc=0; deploy_remote "" detect >/dev/null 2>&1 || rc=$?; _c "reject empty target" 2 "$rc"

# mutation guard
rc=0; OMNI_SYSROOT=/tmp/fx deploy_remote "u@h" detect >/dev/null 2>&1 || rc=$?; _c "OMNI_SYSROOT guard 126" 126 "$rc"

# valid target accepted
_c "valid target shape" 0 "$(_remote_valid_target 'root@10.0.0.5'; echo $?)"

# checksum produces output
_tmp=$(mktemp); echo test > "$_tmp"
[ -n "$(_remote_checksum "$_tmp")" ] && _c "checksum non-empty" yes yes || _c "checksum non-empty" yes no
rm -f "$_tmp"

# mock transport: scp=cp-like, ssh=local sh — full round trip with monolith help
MOCK="${TMPDIR:-/tmp}/omni-mock-$$"; mkdir -p "$MOCK"
cat > "$MOCK/scp" << 'SCP'
#!/bin/sh
# args: <src> <user@host:dest>  -> strip host, copy locally
_src="$1"; _dst="${2#*:}"; cp "$_src" "$_dst"
SCP
cat > "$MOCK/ssh" << 'SSH'
#!/bin/sh
# args: <user@host> <command>  -> run command locally
shift; sh -c "$*"
SSH
chmod +x "$MOCK/scp" "$MOCK/ssh"

rc=0
OMNI_SCP_CMD="$MOCK/scp" OMNI_SSH_CMD="$MOCK/ssh" \
    deploy_remote "root@localhost" help >/dev/null 2>&1 || rc=$?
_c "mock round-trip help rc=0" 0 "$rc"
rm -rf "$MOCK"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
