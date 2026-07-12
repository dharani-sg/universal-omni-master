#!/bin/sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
_c() { [ "$2" = "$3" ] && { printf '  PASS %-52s = %s\n' "$1" "$3"; PASS=$((PASS+1)); } || { printf '  FAIL %-52s want=%s got=%s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); }; }

echo "=== M15 Fleet Orchestration Tests ==="

for f in "$ROOT/src/fleet/common.sh" "$ROOT/src/fleet/parallel.sh" \
         "$ROOT/src/fleet/telemetry.sh" "$ROOT/src/fleet/swarm.sh" \
         "$ROOT/src/fleet/security_audit.sh" "$ROOT/bin/omni-fleet"; do
    sh -n "$f" && _c "syntax: $(basename "$f")" ok ok || _c "syntax: $(basename "$f")" ok fail
done

. "$ROOT/src/fleet/common.sh"
. "$ROOT/src/fleet/parallel.sh"
. "$ROOT/src/fleet/telemetry.sh"
. "$ROOT/src/fleet/swarm.sh"
. "$ROOT/src/fleet/security_audit.sh"

# --- Fixture inventory ----------------------------------------------------
WORK="${TMPDIR:-/tmp}/omni-m15-$$"
mkdir -p "$WORK"
export OMNI_FLEET_INVENTORY="$WORK/inventory.conf"
export OMNI_FLEET_STATE="$WORK/fleet_state.ndjson"
export OMNI_FLEET_MAX_PARALLEL=2

cat > "$OMNI_FLEET_INVENTORY" << 'INV'
# fixture inventory
node1 user@host1 prod web,api
node2 user@host2 prod db
node3 user@host3 staging web
node-down user@host-down prod web
INV

# --- Mock SSH transport (last two args = target, remote_cmd) --------------
MOCKDIR="$WORK/mock"
mkdir -p "$MOCKDIR"
cat > "$MOCKDIR/ssh" << 'MOCKSSH'
#!/bin/sh
while [ $# -gt 2 ]; do shift; done
_target="$1"; _cmd="$2"
case "$_target" in
    *host-down*) exit 1 ;;
esac
sh -c "$_cmd"
MOCKSSH
chmod +x "$MOCKDIR/ssh"
export OMNI_SSH_CMD="$MOCKDIR/ssh"

echo "--- inventory ---"
_n=$(fleet_list_nodes | wc -l)
_c "inventory lists 4 nodes" 4 "$_n"

_np=$(fleet_list_nodes prod | wc -l)
_c "inventory filters by group (prod=3)" 3 "$_np"

echo "--- target validation ---"
_c "valid target accepted" 0 "$(fleet_valid_target 'root@10.0.0.1'; echo $?)"
_c "invalid target rejected" 1 "$(fleet_valid_target 'nothost'; echo $?)"

echo "--- json escaping ---"
_esc=$(_fleet_json_escape 'quote " and backslash \ and
newline')
case "$_esc" in
    *'\"'*) _c "json escape handles quotes" yes yes ;;
    *) _c "json escape handles quotes" yes no ;;
esac

echo "--- parallel exec (mocked, one node down) ---"
: > "$OMNI_FLEET_STATE"
fleet_parallel_exec 'echo hello' prod
_lines=$(wc -l < "$OMNI_FLEET_STATE")
_c "parallel exec emits 3 NDJSON lines (prod group)" 3 "$_lines"

_ok_count=$(grep -c '"status":"ok"' "$OMNI_FLEET_STATE")
_c "2 of 3 prod nodes succeed" 2 "$_ok_count"

_fail_count=$(grep -c '"status":"failed"' "$OMNI_FLEET_STATE")
_c "1 of 3 prod nodes fails (node-down)" 1 "$_fail_count"

echo "--- telemetry summary ---"
_summary=$(fleet_telemetry_summary 24)
case "$_summary" in
    *node1*) _c "telemetry summary includes node1" yes yes ;;
    *) _c "telemetry summary includes node1" yes no ;;
esac

echo "--- rolling window prune ---"
: > "$OMNI_FLEET_STATE"
_old_epoch=$(( $(date +%s) - 100000 ))
printf '{"node":"old","event":"exec","status":"ok","message":"stale","ts":"x","epoch":%s}\n' "$_old_epoch" >> "$OMNI_FLEET_STATE"
fleet_emit "fresh" "exec" "ok" "recent"
_before=$(wc -l < "$OMNI_FLEET_STATE")
fleet_prune_state 24
_after=$(wc -l < "$OMNI_FLEET_STATE")
_c "prune removes stale entry" yes "$([ "$_before" -eq 2 ] && [ "$_after" -eq 1 ] && echo yes || echo no)"

echo "--- swarm policy parsing ---"
POLICY="$WORK/policy.conf"
cat > "$POLICY" << 'POL'
# comment
daily_snapshot=enabled
healer_watch=dbus,seatd
unknown_key=value
POL
_c "policy get daily_snapshot" enabled "$(swarm_policy_get "$POLICY" daily_snapshot)"
_c "policy get healer_watch" dbus,seatd "$(swarm_policy_get "$POLICY" healer_watch)"

echo "--- swarm apply mutation guard ---"
rc=0; OMNI_SYSROOT=/tmp/fx swarm_apply "$POLICY" prod >/dev/null 2>&1 || rc=$?
_c "swarm_apply OMNI_SYSROOT guard 126" 126 "$rc"

echo "--- swarm apply (unguarded, mocked) ---"
: > "$OMNI_FLEET_STATE"
swarm_apply "$POLICY" prod >/dev/null 2>&1
_applied=$(grep -c '"status":"applied"' "$OMNI_FLEET_STATE")
_c "swarm applies known policies" 2 "$_applied"
_skipped=$(grep -c 'unknown key: unknown_key' "$OMNI_FLEET_STATE")
_c "swarm skips unknown policy key" 1 "$_skipped"

echo "--- event propagation ---"
rc=0; OMNI_SYSROOT=/tmp/fx swarm_propagate_event '{"event":"storage_critical"}' storage_critical prod 'echo snap' >/dev/null 2>&1 || rc=$?
_c "propagate_event guard 126" 126 "$rc"

: > "$OMNI_FLEET_STATE"
rc=0; swarm_propagate_event '{"event":"storage_critical"}' storage_critical prod 'echo snap' >/dev/null 2>&1 || rc=$?
_c "propagate_event triggers on match rc=0" 0 "$rc"

rc=0; swarm_propagate_event '{"event":"benign"}' storage_critical prod 'echo snap' >/dev/null 2>&1 || rc=$?
_c "propagate_event skips on no-match rc=1" 1 "$rc"

echo "--- security audit aggregation ---"
: > "$OMNI_FLEET_STATE"
fleet_security_audit prod >/dev/null 2>&1
_report=$(fleet_security_report 24)
case "$_report" in
    *missing_tool*|*node1*) _c "security report generated" yes yes ;;
    *) _c "security report generated" yes no ;;
esac

echo "--- CLI dispatch ---"
rc=0; "$ROOT/bin/omni-fleet" help >/dev/null 2>&1 || rc=$?
_c "cli help exits 0" 0 "$rc"

rc=0; "$ROOT/bin/omni-fleet" bogus >/dev/null 2>&1 || rc=$?
_c "cli unknown exits 2" 2 "$rc"

rc=0; "$ROOT/bin/omni-fleet" inventory >/dev/null 2>&1 || rc=$?
_c "cli inventory exits 0" 0 "$rc"

rc=0; OMNI_SYSROOT=/tmp/fx "$ROOT/bin/omni-fleet" swarm apply "$POLICY" >/dev/null 2>&1 || rc=$?
_c "cli swarm apply guard 126" 126 "$rc"

rm -rf "$WORK"
echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
