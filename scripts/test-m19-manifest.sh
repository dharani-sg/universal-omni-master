#!/bin/sh
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PASS=0
FAIL=0

_c() {
    if [ "$2" = "$3" ]; then
        printf '  PASS %-50s = %s\n' "$1" "$3"
        PASS=$((PASS + 1))
    else
        printf '  FAIL %-50s want=%s got=%s\n' "$1" "$2" "$3"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== M19 Declarative Manifest Tests ==="

sh -n "$ROOT/src/manifest/parser.sh" && _c "syntax: parser.sh" ok ok || _c "syntax: parser.sh" ok fail
sh -n "$ROOT/src/manifest/diff.sh" && _c "syntax: diff.sh" ok ok || _c "syntax: diff.sh" ok fail
sh -n "$ROOT/bin/omni-manifest" && _c "syntax: omni-manifest" ok ok || _c "syntax: omni-manifest" ok fail

MOCK_DIR="/tmp/omni-manifest-mock-$$"
export OMNI_MOCK_PROC="$MOCK_DIR/proc/sys"
mkdir -p "$OMNI_MOCK_PROC/vm"
echo 60 > "$OMNI_MOCK_PROC/vm/swappiness"

mkdir -p "$MOCK_DIR/bin"
export PATH="$MOCK_DIR/bin:$PATH"

cat > "$MOCK_DIR/bin/sysctl" << 'MOCK'
#!/bin/sh
if [ "$1" = "-n" ]; then
    _p="$OMNI_MOCK_PROC/$(printf '%s' "$2" | tr '.' '/')"
    cat "$_p" 2>/dev/null
elif [ "$1" = "-w" ]; then
    _k=${2%%=*}
    _v=${2#*=}
    _p="$OMNI_MOCK_PROC/$(printf '%s' "$_k" | tr '.' '/')"
    printf '%s' "$_v" > "$_p"
fi
MOCK
chmod +x "$MOCK_DIR/bin/sysctl"

cat > "$MOCK_DIR/bin/apk" << 'MOCK'
#!/bin/sh
if [ "$1" = "info" ]; then
    [ "$3" = "vim" ] && exit 1 # vim missing
    [ "$3" = "git" ] && exit 0 # git present
    exit 1
elif [ "$1" = "add" ]; then
    echo "apk add $2"
fi
MOCK
chmod +x "$MOCK_DIR/bin/apk"

cat > "$MOCK_DIR/bin/omni-service" << 'MOCK'
#!/bin/sh
if [ "$1" = "status" ]; then
    [ "$2" = "sshd" ] && echo "disabled"
    [ "$2" = "dbus" ] && echo "enabled"
elif [ "$1" = "enable" ]; then
    echo "omni-service enable $2"
fi
MOCK
chmod +x "$MOCK_DIR/bin/omni-service"

MANIFEST="$MOCK_DIR/test.manifest"
cat > "$MANIFEST" << 'MFST'
[packages]
vim=present
git=present

[services]
sshd=enabled
dbus=enabled

[sysctl]
vm.swappiness=10
MFST

# 1. Test Parser Output Dotted Format Structure
_parsed=$( . "$ROOT/src/manifest/parser.sh"; manifest_parse "$MANIFEST" | wc -l | tr -d ' ' )
_c "parser output lines count" 5 "$_parsed"

# 2. Test CLI Plan (Dry-run) drift detection
_plan=$("$ROOT/bin/omni-manifest" plan "$MANIFEST")
echo "$_plan" | grep -q "Plan: package_install vim" && _c "plan detects missing package" yes yes || _c "plan detects missing package" yes no
echo "$_plan" | grep -q "Plan: package_install git" && _c "plan ignores present package" yes no || _c "plan ignores present package" yes yes
echo "$_plan" | grep -q "Plan: service_enable sshd" && _c "plan detects disabled service" yes yes || _c "plan detects disabled service" yes no
echo "$_plan" | grep -q "Plan: sysctl_set vm.swappiness 10" && _c "plan detects sysctl drift" yes yes || _c "plan detects sysctl drift" yes no

# 3. Test Apply Guard 126
rc=0
OMNI_SYSROOT=/tmp/fx "$ROOT/bin/omni-manifest" apply "$MANIFEST" >/dev/null 2>&1 || rc=$?
_c "apply respects OMNI_SYSROOT guard 126" 126 "$rc"

# 4. Test Idempotency (Apply -> Mutates Mock -> Plan should be empty for sysctl)
"$ROOT/bin/omni-manifest" apply "$MANIFEST" >/dev/null 2>&1
_new_swappiness=$(cat "$OMNI_MOCK_PROC/vm/swappiness")
_c "apply mutates sysctl using mock" 10 "$_new_swappiness"

_plan2=$("$ROOT/bin/omni-manifest" plan "$MANIFEST")
echo "$_plan2" | grep -q "Plan: sysctl_set vm.swappiness" && _c "post-apply idempotency sysctl" no yes || _c "post-apply idempotency sysctl" no no

rm -rf "$MOCK_DIR"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
