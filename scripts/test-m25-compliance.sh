#!/bin/sh
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PASS=0; FAIL=0

_c() {
    if [ "$2" = "$3" ]; then
        printf '  PASS %-52s = %s\n' "$1" "$3"; PASS=$((PASS+1))
    else
        printf '  FAIL %-52s want=%s got=%s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1))
    fi
}

echo "=== M25 Fleet Compliance Tests ==="

sh -n "$ROOT/src/compliance/stig.sh" && _c "syntax: stig.sh" ok ok \
    || _c "syntax: stig.sh" ok fail
sh -n "$ROOT/bin/omni-compliance" && _c "syntax: omni-compliance" ok ok \
    || _c "syntax: omni-compliance" ok fail

. "$ROOT/src/compliance/stig.sh"

WORK="${TMPDIR:-/tmp}/omni-m25-$$"
mkdir -p "$WORK/etc/ssh"
export OMNI_COMPLIANCE_LOG="$WORK/compliance.ndjson"
export OMNI_SSHD_CONFIG="$WORK/etc/ssh/sshd_config"

# Seed a non-compliant sshd_config.
cat > "$OMNI_SSHD_CONFIG" << 'SSHD'
# Default config
PermitRootLogin yes
PasswordAuthentication yes
MaxAuthTries 6
SSHD

# 1. Initial audit should detect drift.
rc=0; compliance_audit_profile "cis_level_1" >/dev/null 2>&1 || rc=$?
_c "initial audit detects drift" 1 "$rc"

# 2. Enforce all three rules.
compliance_enforce_sshd "PermitRootLogin"        "no" >/dev/null 2>&1
compliance_enforce_sshd "PasswordAuthentication" "no" >/dev/null 2>&1
compliance_enforce_sshd "MaxAuthTries"           "3"  >/dev/null 2>&1

# 3. Post-enforcement audit should pass.
rc=0; compliance_audit_profile "cis_level_1" >/dev/null 2>&1 || rc=$?
_c "post-enforcement audit passes" 0 "$rc"

# 4. Idempotency: re-running enforce must not duplicate the line.
compliance_enforce_sshd "PermitRootLogin" "no" >/dev/null 2>&1
_root_count=$(grep -i "PermitRootLogin" "$OMNI_SSHD_CONFIG" | wc -l | tr -d ' ')
_c "enforce is idempotent (no duplicate lines)" 1 "$_root_count"

# 5. OMNI_SYSROOT guard.
rc=0; OMNI_SYSROOT=/tmp/fx compliance_enforce_sshd "PermitRootLogin" "yes" \
    >/dev/null 2>&1 || rc=$?
_c "enforce guarded by OMNI_SYSROOT" 126 "$rc"

# 6. Telemetry is written to NDJSON.
_c "telemetry logged to NDJSON" yes \
    "$([ -f "$OMNI_COMPLIANCE_LOG" ] && echo yes || echo no)"
_c "NDJSON contains enforce_sshd event" yes \
    "$(grep -q 'enforce_sshd' "$OMNI_COMPLIANCE_LOG" 2>/dev/null && echo yes || echo no)"

# 7. Unknown profile returns 2.
rc=0; compliance_audit_profile "bogus_profile" >/dev/null 2>&1 || rc=$?
_c "unknown profile returns 2" 2 "$rc"

# 8. CLI help exits 0.
rc=0; "$ROOT/bin/omni-compliance" help >/dev/null 2>&1 || rc=$?
_c "cli help exits 0" 0 "$rc"

# 9. CLI unknown command exits 2.
rc=0; "$ROOT/bin/omni-compliance" bogus >/dev/null 2>&1 || rc=$?
_c "cli unknown command exits 2" 2 "$rc"

rm -rf "$WORK"

printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
