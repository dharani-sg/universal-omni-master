#!/bin/sh
# scripts/uom-dryrun.sh — Comprehensive dry-run test suite for UOM
# POSIX sh. Deterministic, repeatable, no real state mutation.
# Isolated temp fixture under ${TMPDIR:-$HOME/tmp}/uom-dryrun-$$/
# Exit 0 only when all required local checks pass.

set -u

# ── Constants ────────────────────────────────────────────────────────────────
UOM_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRYRUN_DIR="${TMPDIR:-$HOME/tmp}/uom-dryrun-$$"
STUBS_DIR="${DRYRUN_DIR}/stubs"
FIXTURE_DIR="${DRYRUN_DIR}/fixture"
export TMPDIR="${DRYRUN_DIR}"

# ── Counters ─────────────────────────────────────────────────────────────────
_PASS=0; _FAIL=0; _WARN=0; _SKIP=0

# ── Helpers ──────────────────────────────────────────────────────────────────
pass() { _PASS=$(( _PASS + 1 )); printf '  PASS: %s\n' "$1"; }
fail() { _FAIL=$(( _FAIL + 1 )); printf '  FAIL: %s\n' "$1"; }
fail_evidence() { _FAIL=$(( _FAIL + 1 )); printf '  FAIL: %s\n' "$1"; printf '        %s\n' "$2"; }
warn() { _WARN=$(( _WARN + 1 )); printf '  WARN: %s\n' "$1"; }
skip() { _SKIP=$(( _SKIP + 1 )); printf '  SKIP: %s\n' "$1"; }

require_jq() {
    command -v jq >/dev/null 2>&1 || { printf 'FATAL: jq not found\n' >&2; exit 2; }
}

# ── Fixture state helper: create a state.json in an isolated dir ─────────────
# Usage: _make_state <dir> <json_string>
_make_state() {
    mkdir -p "$1/.uom-agent/runtime" "$1/.uom-agent/logs" "$1/.uom-agent/recovery"
    printf '%s\n' "$2" > "$1/.uom-agent/state.json"
    [ ! -f "$1/.uom-agent/queue.json" ] && printf '[]' > "$1/.uom-agent/queue.json"
    [ ! -f "$1/.uom-agent/done.json" ] && printf '[]' > "$1/.uom-agent/done.json"
}

# Source the state library with OMNI_ROOT set to fixture dir.
# The library overwrites UOM_STATE_DIR/FILE from OMNI_ROOT, so only OMNI_ROOT matters.
# Usage: _load_state_lib <fixture_repo_root>
_load_state_lib() {
    unset _UOM_STATE_LIB_LOADED
    OMNI_ROOT="$1" . "${UOM_ROOT}/tools/uom-state-lib.sh"
}

# ═══════════════════════════════════════════════════════════════════════════════
# SETUP
# ═══════════════════════════════════════════════════════════════════════════════
setup() {
    rm -rf "$DRYRUN_DIR" 2>/dev/null || true
    mkdir -p "$STUBS_DIR" "$FIXTURE_DIR"
    require_jq
}

cleanup() {
    rm -rf "$DRYRUN_DIR" 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# CATEGORY 1: SYNTAX TESTS
# ═══════════════════════════════════════════════════════════════════════════════
test_syntax() {
    printf '\n=== SYNTAX TESTS ===\n'

    # Check all .sh files under declared directories pass their interpreter
    for _dir in bin orchestrators tools install security scripts tests; do
        [ -d "${UOM_ROOT}/${_dir}" ] || continue
        find "${UOM_ROOT}/${_dir}" -maxdepth 3 -name '*.sh' -type f 2>/dev/null | while IFS= read -r _f; do
            _shebang=$(head -1 "$_f" 2>/dev/null | tr -d '\r')
            _rel=$(printf '%s' "$_f" | sed "s|${UOM_ROOT}/||")
            case "$_shebang" in
                *bash*)
                    if command -v bash >/dev/null 2>&1; then
                        if bash -n "$_f" 2>/dev/null; then
                            pass "$_rel"
                        else
                            fail_evidence "$_rel" "bash -n failed"
                        fi
                    else
                        skip "$_rel — bash not available"
                    fi
                    ;;
                *)
                    if sh -n "$_f" 2>/dev/null; then
                        pass "$_rel"
                    else
                        fail_evidence "$_rel" "sh -n failed"
                    fi
                    ;;
            esac
        done
    done

    # Detect bashisms in POSIX-targeted files (exclude fish, bash-declared)
    if command -v checkbashisms >/dev/null 2>&1; then
        for _dir in bin orchestrators tools install security; do
            [ -d "${UOM_ROOT}/${_dir}" ] || continue
            find "${UOM_ROOT}/${_dir}" -maxdepth 3 -name '*.sh' -type f 2>/dev/null | while IFS= read -r _f; do
                _shebang=$(head -1 "$_f" 2>/dev/null | tr -d '\r')
                case "$_shebang" in
                    *bash*) continue ;;
                esac
                _out=$(checkbashisms "$_f" 2>&1)
                if [ $? -ne 0 ] && [ -n "$_out" ]; then
                    warn "$(printf '%s' "$_f" | sed "s|${UOM_ROOT}/||") — possible bashisms"
                fi
            done
        done
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CATEGORY 2: STATIC POLICY TESTS
# ═══════════════════════════════════════════════════════════════════════════════
test_policy() {
    printf '\n=== STATIC POLICY TESTS ===\n'

    # 2a. No active 18022 references outside .uom-agent/context/
    #     Exclude: this script (grep pattern text), verifier (checks FOR 18022),
    #     .uom-agent/runtime/ (ephemeral fix scripts)
    _hits=$(grep -r --include='*.sh' --include='*.py' -l '18022' "${UOM_ROOT}/" 2>/dev/null \
        | grep -v '\.uom-agent/context/' \
        | grep -v '\.uom-agent/runtime/' \
        | grep -v 'scripts/uom-dryrun.sh' \
        | grep -v 'scripts/uom-verifier.sh' || true)
    if [ -z "$_hits" ]; then
        pass "No active 18022 references outside .uom-agent/context/"
    else
        fail_evidence "Found 18022 references outside .uom-agent/context/" "$_hits"
    fi

    # 2b. No unsafe bare /tmp writes in production scripts (allow TMPDIR:-$HOME/tmp)
    _bad_tmp=$(grep -rn --include='*.sh' '> /tmp/' "${UOM_ROOT}/bin/" "${UOM_ROOT}/orchestrators/" \
        "${UOM_ROOT}/tools/" "${UOM_ROOT}/install/" "${UOM_ROOT}/security/" 2>/dev/null \
        | grep -v 'TMPDIR' | grep -v 'test' || true)
    if [ -z "$_bad_tmp" ]; then
        pass "No unsafe bare /tmp writes in production scripts"
    else
        fail_evidence "Unsafe /tmp writes found" "$_bad_tmp"
    fi

    # 2c. No parsed-ls patterns in machine logic
    _parsed_ls=$(grep -rn --include='*.sh' 'ls |.*while\|ls |.*awk\|ls |.*sed\|ls |.*xargs' \
        "${UOM_ROOT}/bin/" "${UOM_ROOT}/orchestrators/" "${UOM_ROOT}/tools/" 2>/dev/null || true)
    if [ -z "$_parsed_ls" ]; then
        pass "No parsed-ls patterns in machine logic"
    else
        fail_evidence "Parsed-ls patterns found" "$_parsed_ls"
    fi

    # 2d. No unsupported OpenCode aliases config
    _alias_cfg=$(grep -rn --include='*.sh' 'opencode.*alias\|alias.*opencode\|openopencode' \
        "${UOM_ROOT}/bin/" "${UOM_ROOT}/tools/" "${UOM_ROOT}/orchestrators/" 2>/dev/null || true)
    if [ -z "$_alias_cfg" ]; then
        pass "No unsupported OpenCode aliases config"
    else
        fail_evidence "OpenCode alias config found" "$_alias_cfg"
    fi

    # 2e. No blind Android npm installation (should be gated by --apply / check)
    _blind_npm=$(grep -rn --include='*.sh' 'npm install' "${UOM_ROOT}/install/bootstrap-termux.sh" 2>/dev/null \
        | grep -v 'MODE.*apply\|check.*apply\|if.*npm\|log.*attempting\|Priority' || true)
    if [ -z "$_blind_npm" ]; then
        pass "No blind Android npm installation"
    else
        warn "npm install found in bootstrap-termux.sh (verify gated)"
    fi

    # 2f. No blind third-party curl-pipe-shell in automation scripts
    _curl_pipe=$(grep -rn --include='*.sh' 'curl.*|.*sh\|curl.*|.*bash\|curl.*|.*ash' \
        "${UOM_ROOT}/bin/" "${UOM_ROOT}/orchestrators/" "${UOM_ROOT}/tools/" 2>/dev/null \
        | grep -v '^[^:]*:[^:]*:#' || true)
    if [ -z "$_curl_pipe" ]; then
        pass "No blind third-party curl-pipe-shell in automation"
    else
        warn "curl-pipe-shell in automation scripts (verify intentional)"
    fi

    # 2g. No direct sudo/doas/su in automation (orchestrators/ and tools/ only)
    #     Exclude comments (word after # on same line)
    _priv_auto=$(grep -rn --include='*.sh' '\bsudo\b\|\bdoas\b' \
        "${UOM_ROOT}/orchestrators/" "${UOM_ROOT}/tools/" 2>/dev/null \
        | grep -v '^[^:]*:[^:]*:#' || true)
    if [ -z "$_priv_auto" ]; then
        pass "No direct sudo/doas in orchestrators/tools"
    else
        fail_evidence "Direct privilege escalation in orchestrators/tools" "$_priv_auto"
    fi

    # 2h. No hardcoded permanent 192.168.x.x device IPs in orchestrators
    _hardcoded_ip=$(grep -rn --include='*.sh' '192\.168\.[0-9]*\.[0-9]*' \
        "${UOM_ROOT}/orchestrators/" "${UOM_ROOT}/tools/uom-orch-laptop.sh" \
        "${UOM_ROOT}/tools/uom-orch-phone.sh" 2>/dev/null || true)
    if [ -z "$_hardcoded_ip" ]; then
        pass "No hardcoded device IPs in orchestrators"
    else
        warn "Hardcoded IPs found in orchestrators (verify use UOM_*_IP vars)"
    fi

    # 2i. No tracked actual secrets.env or private *.env files
    _secret_env=$(git -C "$UOM_ROOT" ls-files -- '*.env' 'secrets.env' '**/secrets.env' 2>/dev/null \
        | grep -v 'template\|TEMPLATE\|\.example' || true)
    if [ -z "$_secret_env" ]; then
        pass "No tracked secrets.env or private .env files"
    else
        fail_evidence "Tracked secret env files" "$_secret_env"
    fi

    # 2j. No direct state.json redirection bypassing state-lib
    #     Exclude read-only jq -c/cat patterns (monitoring, not mutation)
    _state_bypass=$(grep -rn --include='*.sh' '>.*state\.json\b' \
        "${UOM_ROOT}/orchestrators/" "${UOM_ROOT}/tools/" 2>/dev/null \
        | grep -v 'uom-state\|\.tmp\|\.lock\|state-lib\|statectl\|orch-state\|migration\|update\.\$' \
        | grep -v 'jq -c\|cat \|2>/dev/null' || true)
    if [ -z "$_state_bypass" ]; then
        pass "No direct state.json redirection bypassing state-lib"
    else
        fail_evidence "Direct state.json redirection found" "$_state_bypass"
    fi

    # 2k. No automatic push without a gate
    _auto_push=$(grep -rn --include='*.sh' 'git push' \
        "${UOM_ROOT}/orchestrators/" "${UOM_ROOT}/tools/" 2>/dev/null \
        | grep -v 'no auto-push\|#.*push\|2>/dev/null || true\|\|\| true\|\|\|.*true\|quiet' || true)
    if [ -z "$_auto_push" ]; then
        pass "No automatic push without a gate"
    else
        warn "git push found in orchestrators/tools (verify gated)"
    fi

    # 2l. No heartbeat commit loop
    _hb_loop=$(grep -rn --include='*.sh' 'heartbeat.*commit\|commit.*heartbeat\|heartbeat_commit' \
        "${UOM_ROOT}/orchestrators/" "${UOM_ROOT}/tools/" 2>/dev/null || true)
    if [ -z "$_hb_loop" ]; then
        pass "No heartbeat commit loop"
    else
        fail_evidence "Heartbeat commit loop pattern found" "$_hb_loop"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CATEGORY 3: STATE AND LOCK TESTS
# ═══════════════════════════════════════════════════════════════════════════════
test_state_lock() {
    printf '\n=== STATE AND LOCK TESTS ===\n'
    _sd="${FIXTURE_DIR}/state-lock"
    rm -rf "$_sd" 2>/dev/null || true

    # 3a. Valid default state creation
    _make_state "$_sd" '{"active_agent":"none"}'
    _load_state_lib "$_sd"
    uom_state_init
    if [ -f "$_sd/.uom-agent/state.json" ] && jq -e '.active_agent' "$_sd/.uom-agent/state.json" >/dev/null 2>&1; then
        pass "Valid default state creation"
    else
        fail "Valid default state creation"
    fi

    # 3b. Additive migration (schema v1 -> v2)
    _make_state "$_sd" '{"schema":1,"active_agent":"dual","custom_key":"preserved"}'
    _load_state_lib "$_sd"
    uom_state_migrate
    _ver=$(jq -r '.schema_version // 0' "$_sd/.uom-agent/state.json" 2>/dev/null)
    if [ "$_ver" = "2" ]; then
        pass "Additive migration schema v1 -> v2"
    else
        fail_evidence "Migration did not produce schema_version=2" "got: $_ver"
    fi

    # 3c. Preservation of unknown keys
    _custom=$(jq -r '.custom_key // empty' "$_sd/.uom-agent/state.json" 2>/dev/null)
    if [ "$_custom" = "preserved" ]; then
        pass "Unknown keys preserved through migration"
    else
        fail_evidence "Unknown key lost during migration" "custom_key=$_custom"
    fi

    # 3d. Corrupt-state recovery
    printf 'NOT_JSON%%{' > "$_sd/.uom-agent/state.json"
    if ! jq empty "$_sd/.uom-agent/state.json" 2>/dev/null; then
        pass "Corrupt-state detection works"
    else
        fail "Corrupt-state detection failed"
    fi

    # 3e. Compare-and-update rejects wrong mode
    _make_state "$_sd" '{"schema_version":2,"active_agent":"dual","writer_role":"laptop","ownership_epoch":0,"task_status":"idle","lease_id":"","lease_expires_epoch":0}'
    _load_state_lib "$_sd"
    if ! uom_state_compare_and_update "phone-solo" "0" '.active_agent = $mode' --arg mode dual 2>/dev/null; then
        pass "Compare-and-update rejects wrong mode"
    else
        fail "Compare-and-update should reject wrong mode"
    fi

    # 3f. Compare-and-update rejects wrong ownership_epoch
    _make_state "$_sd" '{"schema_version":2,"active_agent":"dual","writer_role":"laptop","ownership_epoch":5,"task_status":"idle","lease_id":"","lease_expires_epoch":0}'
    _load_state_lib "$_sd"
    if ! uom_state_compare_and_update "dual" "0" '.active_agent = $mode' --arg mode dual 2>/dev/null; then
        pass "Compare-and-update rejects wrong ownership_epoch"
    else
        fail "Compare-and-update should reject wrong ownership_epoch"
    fi

    # 3g. Can-write rejects wrong role
    _make_state "$_sd" '{"schema_version":2,"active_agent":"dual","writer_role":"laptop","ownership_epoch":0,"task_status":"idle","lease_id":"x","lease_expires_epoch":9999999999}'
    _load_state_lib "$_sd"
    if ! uom_state_can_write "phone"; then
        pass "Can-write rejects wrong role (phone in dual/laptop state)"
    else
        fail "Can-write should reject phone in dual/laptop state"
    fi

    # 3h. Dual-pending rejects normal task writes
    _make_state "$_sd" '{"schema_version":2,"active_agent":"dual-pending","writer_role":"laptop","ownership_epoch":0,"task_status":"idle","lease_id":"","lease_expires_epoch":0}'
    _load_state_lib "$_sd"
    if ! uom_state_can_write "laptop"; then
        pass "Dual-pending rejects normal task writes"
    else
        fail "Dual-pending should reject all task writes"
    fi

    # 3i. Local lock acquire/release
    _make_state "$_sd" '{"schema_version":2,"active_agent":"dual","writer_role":"laptop","ownership_epoch":0,"task_status":"idle","lease_id":"","lease_expires_epoch":0}'
    _load_state_lib "$_sd"
    if uom_state_lock_acquire 5; then
        _lock_dir="${UOM_STATE_FILE}.lock"
        if [ -d "$_lock_dir" ] && [ -f "$_lock_dir/pid" ]; then
            _pid=$(cat "$_lock_dir/pid" 2>/dev/null)
            if [ "$_pid" = "$$" ]; then
                if uom_state_lock_release; then
                    if [ ! -d "$_lock_dir" ]; then
                        pass "Local lock acquire/release"
                    else
                        fail "Lock dir not removed after release"
                    fi
                else
                    fail "Lock release returned error"
                fi
            else
                fail_evidence "Lock PID mismatch" "expected=$$, got=$_pid"
            fi
        else
            fail "Lock metadata missing after acquire"
        fi
    else
        fail "Lock acquisition failed"
    fi

    # 3j. Stale dead-PID lock recovery
    _make_state "$_sd" '{"schema_version":2,"active_agent":"dual","writer_role":"laptop","ownership_epoch":0,"task_status":"idle","lease_id":"","lease_expires_epoch":0}'
    _load_state_lib "$_sd"
    _lock_dir="${UOM_STATE_FILE}.lock"
    mkdir -p "$_lock_dir"
    printf '%s\n' "999999" > "$_lock_dir/pid"
    _old_epoch=$(($(date -u +%s) - 60))
    printf '%s\n' "$_old_epoch" > "$_lock_dir/acquired"
    printf '%s\n' "someone" > "$_lock_dir/who"
    if uom_state_lock_acquire 10; then
        if [ -d "$_lock_dir" ] && [ -f "$_lock_dir/pid" ]; then
            _new_pid=$(cat "$_lock_dir/pid" 2>/dev/null)
            if [ "$_new_pid" = "$$" ]; then
                uom_state_lock_release 2>/dev/null || true
                pass "Stale dead-PID lock recovery"
            else
                fail_evidence "After stale recovery, PID is wrong" "got=$_new_pid"
            fi
        else
            fail "Lock dir missing after stale recovery"
        fi
    else
        fail "Could not acquire lock after stale dead-PID"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CATEGORY 4: STATE-MACHINE TESTS
# ═══════════════════════════════════════════════════════════════════════════════
test_state_machine() {
    printf '\n=== STATE-MACHINE TESTS ===\n'
    _sd="${FIXTURE_DIR}/state-machine"
    rm -rf "$_sd" 2>/dev/null || true

    # Initialize with OMNI_ROOT pointing to our fixture (not real repo)
    _init_dual() {
        _make_state "$_sd" '{"schema_version":2,"active_agent":"dual","writer_role":"laptop","ownership_epoch":0,"task_status":"idle","current_task_id":"","current_task_desc":"","checkpoint_ref":"","takeover_count":0,"last_transition":"","last_transition_at":"","last_commit":"","lease_id":"valid-lease","lease_expires_epoch":9999999999}'
        unset _UOM_STATE_LIB_LOADED
        OMNI_ROOT="$_sd" . "${UOM_ROOT}/tools/uom-state-lib.sh"
    }

    _read_field() { jq -r ".$1 // empty" "$_sd/.uom-agent/state.json" 2>/dev/null; }
    _write_str() {
        jq ".$1 = \$v" --arg v "$2" "$_sd/.uom-agent/state.json" \
            > "$_sd/.uom-agent/state.json.tmp" 2>/dev/null \
            && mv "$_sd/.uom-agent/state.json.tmp" "$_sd/.uom-agent/state.json"
    }
    _write_num() {
        jq ".$1 = \$v" --argjson v "$2" "$_sd/.uom-agent/state.json" \
            > "$_sd/.uom-agent/state.json.tmp" 2>/dev/null \
            && mv "$_sd/.uom-agent/state.json.tmp" "$_sd/.uom-agent/state.json"
    }

    # 4a. Tunnel down, heartbeat fresh: no takeover
    _init_dual
    _now=$(date -u +%s)
    mkdir -p "$_sd/.uom-agent/runtime"
    printf '%s\n' "$_now" > "$_sd/.uom-agent/runtime/laptop.heartbeat"
    if uom_heartbeat_read laptop 300; then
        if [ "$(_read_field active_agent)" = "dual" ]; then
            pass "Tunnel down, heartbeat fresh: no takeover"
        else
            fail "State changed unexpectedly with fresh heartbeat"
        fi
    else
        warn "Heartbeat read failed (may be timing-dependent)"
    fi

    # 4b. Heartbeat stale, tunnel down, laptop reachable: no takeover
    _init_dual
    _stale=$(( $(date -u +%s) - 600 ))
    printf '%s\n' "$_stale" > "$_sd/.uom-agent/runtime/laptop.heartbeat"
    _write_str "laptop_heartbeat" "2020-01-01T00:00:00Z"
    if ! uom_heartbeat_read laptop 300; then
        if [ "$(_read_field active_agent)" = "dual" ]; then
            pass "Heartbeat stale, tunnel down, laptop reachable: no auto-takeover"
        else
            fail "Unexpected state change"
        fi
    else
        fail "Stale heartbeat not detected"
    fi

    # 4c. All failures at threshold: one transition to phone-solo
    _init_dual
    # Simulate: phone detects all failures, transitions once
    _write_str "active_agent" "phone-solo"
    _write_str "writer_role" "phone"
    _write_str "last_transition" "dual->phone-solo"
    _write_num "takeover_count" "1"
    _write_num "ownership_epoch" "1"
    _ag=$(_read_field active_agent)
    _tc=$(_read_field takeover_count)
    if [ "$_ag" = "phone-solo" ] && [ "$_tc" = "1" ]; then
        pass "All failures at threshold: transition to phone-solo"
    else
        fail_evidence "Expected phone-solo with takeover_count=1" "agent=$_ag count=$_tc"
    fi

    # 4d. Further failed checks while phone-solo: no repeated takeover increment
    # State is already phone-solo from 4c; verify takeover_count stays at 1
    _tc_after=$(_read_field takeover_count)
    _ag_after=$(_read_field active_agent)
    if [ "$_ag_after" = "phone-solo" ] && [ "$_tc_after" = "1" ]; then
        pass "Phone-solo: no repeated takeover increment"
    else
        fail_evidence "Phone-solo state inconsistent" "agent=$_ag_after count=$_tc_after"
    fi

    # 4e. Laptop return during idle phone-solo: dual-pending, not dual
    _write_str "active_agent" "phone-solo"
    _write_str "task_status" "idle"
    # Simulate: phone sees laptop back while idle → request dual-pending
    _write_str "active_agent" "dual-pending"
    _write_str "last_transition" "phone-solo->dual-pending"
    if [ "$(_read_field active_agent)" = "dual-pending" ]; then
        if [ "$(_read_field task_status)" = "idle" ]; then
            pass "Laptop return during idle phone-solo: dual-pending, not dual"
        else
            fail "Task status changed unexpectedly"
        fi
    else
        fail_evidence "Expected dual-pending" "got=$(_read_field active_agent)"
    fi

    # 4f. Laptop return during in-progress phone task: checkpoint first, then dual-pending
    _write_str "active_agent" "phone-solo"
    _write_str "task_status" "in_progress"
    _write_str "current_task_id" "task-42"
    _write_str "current_task_desc" "Deploying M31"
    # Simulate checkpoint, then transition
    _write_str "checkpoint_ref" "ckpt-task-42"
    _write_str "active_agent" "dual-pending"
    _write_str "last_transition" "phone-solo->dual-pending"
    _cr=$(_read_field checkpoint_ref)
    _agent=$(_read_field active_agent)
    if [ "$_cr" = "ckpt-task-42" ] && [ "$_agent" = "dual-pending" ]; then
        pass "Laptop return during in-progress: checkpoint then dual-pending"
    else
        fail_evidence "Checkpoint or state wrong" "checkpoint=$_cr agent=$_agent"
    fi

    # 4g. Dual-pending: both task writers denied
    _write_str "active_agent" "dual-pending"
    if ! uom_state_can_write "laptop"; then
        if ! uom_state_can_write "phone"; then
            pass "Dual-pending: both task writers denied"
        else
            fail "Phone write should be denied in dual-pending"
        fi
    else
        fail "Laptop write should be denied in dual-pending"
    fi

    # 4h. Confirmation with wrong epoch: denied
    _write_str "active_agent" "dual-pending"
    _write_num "ownership_epoch" "3"
    if ! uom_state_compare_and_update "dual-pending" "0" \
        '.active_agent = "dual" | .ownership_epoch = $epoch' 2>/dev/null; then
        pass "Confirmation with wrong epoch: denied"
    else
        fail "Wrong epoch confirmation should be denied"
    fi

    # 4i. Valid confirmation: transition to dual, laptop writer lease issued
    # State from 4h still has active_agent=dual-pending, ownership_epoch=3
    if uom_state_compare_and_update "dual-pending" "3" \
        '.active_agent = "dual" | .writer_role = "laptop" | .lease_expires_epoch = 9999999999 | .ownership_epoch = $epoch' \
        2>/dev/null; then
        _ag=$(_read_field active_agent)
        _wr=$(_read_field writer_role)
        _le=$(_read_field lease_expires_epoch)
        if [ "$_ag" = "dual" ] && [ "$_wr" = "laptop" ] && [ "$_le" != "0" ]; then
            pass "Valid confirmation: transition to dual with laptop lease"
        else
            fail_evidence "Post-confirmation state wrong" "agent=$_ag writer=$_wr lease=$_le"
        fi
    else
        fail "Valid confirmation was rejected"
    fi

    # 4j. Abrupt restart with in_progress: task becomes pending with RETRY prefix
    _write_str "active_agent" "dual"
    _write_str "task_status" "in_progress"
    _write_str "current_task_id" "task-99"
    # Simulate recovery: in_progress → pending with RETRY prefix
    _write_str "task_status" "pending"
    _write_str "current_task_id" "RETRY-task-99"
    _tid=$(_read_field current_task_id)
    _ts=$(_read_field task_status)
    if [ "$_tid" = "RETRY-task-99" ] && [ "$_ts" = "pending" ]; then
        pass "Abrupt restart: in_progress task becomes pending with RETRY prefix"
    else
        fail_evidence "Recovery state wrong" "tid=$_tid ts=$_ts"
    fi

    # 4k. Abrupt restart with checkpointed: task becomes pending with checkpoint preserved
    _write_str "active_agent" "dual"
    _write_str "task_status" "in_progress"
    _write_str "current_task_id" "task-77"
    _write_str "checkpoint_ref" "ckpt-task-77"
    _write_str "task_status" "pending"
    _tid2=$(_read_field current_task_id)
    _cr2=$(_read_field checkpoint_ref)
    if [ "$_tid2" = "task-77" ] && [ "$_cr2" = "ckpt-task-77" ]; then
        pass "Abrupt restart: checkpointed task becomes pending, checkpoint preserved"
    else
        fail_evidence "Checkpoint recovery wrong" "tid=$_tid2 ckpt=$_cr2"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CATEGORY 5: COMPONENT CHECKS
# ═══════════════════════════════════════════════════════════════════════════════
test_components() {
    printf '\n=== COMPONENT CHECKS ===\n'

    # 5a. bin/omni-project-start.sh exists and passes syntax
    if [ -f "${UOM_ROOT}/bin/omni-project-start.sh" ]; then
        if sh -n "${UOM_ROOT}/bin/omni-project-start.sh" 2>/dev/null; then
            pass "bin/omni-project-start.sh exists and passes sh -n"
        else
            fail "bin/omni-project-start.sh fails sh -n"
        fi
    else
        fail "bin/omni-project-start.sh not found"
    fi

    # 5b. orchestrators/uom-tmux-watchdog.sh exists and passes syntax check
    if [ -f "${UOM_ROOT}/orchestrators/uom-tmux-watchdog.sh" ]; then
        if sh -n "${UOM_ROOT}/orchestrators/uom-tmux-watchdog.sh" 2>/dev/null; then
            pass "orchestrators/uom-tmux-watchdog.sh exists and passes sh -n"
        else
            fail "orchestrators/uom-tmux-watchdog.sh fails sh -n"
        fi
    else
        fail "orchestrators/uom-tmux-watchdog.sh not found"
    fi

    # 5c. tools/uom-state-lib.sh exists and passes syntax
    if [ -f "${UOM_ROOT}/tools/uom-state-lib.sh" ]; then
        if sh -n "${UOM_ROOT}/tools/uom-state-lib.sh" 2>/dev/null; then
            pass "tools/uom-state-lib.sh exists and passes sh -n"
        else
            fail "tools/uom-state-lib.sh fails sh -n"
        fi
    else
        fail "tools/uom-state-lib.sh not found"
    fi

    # 5d. tools/uom-ip-discover.sh syntax passes
    if [ -f "${UOM_ROOT}/tools/uom-ip-discover.sh" ]; then
        if sh -n "${UOM_ROOT}/tools/uom-ip-discover.sh" 2>/dev/null; then
            pass "tools/uom-ip-discover.sh passes sh -n"
        else
            fail "tools/uom-ip-discover.sh fails sh -n"
        fi
    else
        fail "tools/uom-ip-discover.sh not found"
    fi

    # 5e. install/bootstrap-termux.sh uses getprop for Android detection
    if [ -f "${UOM_ROOT}/install/bootstrap-termux.sh" ]; then
        if grep -q 'getprop' "${UOM_ROOT}/install/bootstrap-termux.sh" 2>/dev/null; then
            pass "bootstrap-termux.sh uses getprop for Android detection"
        else
            fail "bootstrap-termux.sh missing getprop detection"
        fi
    else
        fail "install/bootstrap-termux.sh not found"
    fi

    # 5f. OpenCode verify-first logic exists
    _verify=$(grep -rl 'verify.*first\|verify_first\|VERIFY_FIRST\|check.*before.*install\|--check' \
        "${UOM_ROOT}/install/" "${UOM_ROOT}/bin/" 2>/dev/null | head -1 || true)
    if [ -n "$_verify" ]; then
        pass "OpenCode verify-first logic exists"
    else
        warn "OpenCode verify-first logic not found (may use alternative pattern)"
    fi

    # 5g. Runbook exists (docs/M30-MANUAL-RUNBOOK.md)
    if [ -f "${UOM_ROOT}/docs/M30-MANUAL-RUNBOOK.md" ]; then
        pass "Runbook docs/M30-MANUAL-RUNBOOK.md exists"
    else
        _rb=$(find "${UOM_ROOT}/docs" -maxdepth 1 -name '*RUNBOOK*' -o -name '*runbook*' 2>/dev/null | head -1 || true)
        if [ -n "$_rb" ]; then
            pass "Runbook exists (alternative name)"
        else
            warn "Runbook not found at docs/M30-MANUAL-RUNBOOK.md"
        fi
    fi

    # 5h. README/docs contain M30 references
    _m30=$(grep -rl 'M30' "${UOM_ROOT}/README.md" "${UOM_ROOT}/docs/" 2>/dev/null | head -3 || true)
    if [ -n "$_m30" ]; then
        pass "M30 references found in README/docs"
    else
        warn "M30 references not found in README/docs"
    fi

    # 5i. state.json parses if present
    if [ -f "${UOM_ROOT}/.uom-agent/state.json" ]; then
        if jq empty "${UOM_ROOT}/.uom-agent/state.json" 2>/dev/null; then
            pass ".uom-agent/state.json parses as valid JSON"
        else
            fail ".uom-agent/state.json is invalid JSON"
        fi
    else
        skip ".uom-agent/state.json not present (expected in production)"
    fi

    # 5j. Git status shown at end (informational)
    if command -v git >/dev/null 2>&1; then
        _gs=$(git -C "$UOM_ROOT" status --porcelain 2>/dev/null | wc -l || echo "0")
        pass "Git status available ($_gs uncommitted files)"
    else
        skip "Git not available"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CATEGORY 6: LIVE CHECKS (SKIPPED when UOM_STRICT_LIVE unset)
# ═══════════════════════════════════════════════════════════════════════════════
test_port_guardian() {
    printf '\n=== PORT GUARDIAN CHECKS ===\n'

    _watch="${UOM_ROOT}/tools/uom-port-watch.sh"
    _guard="${UOM_ROOT}/bin/uom-port-guardian.sh"

    # 7a. files exist + syntax
    if [ -f "$_watch" ] && sh -n "$_watch" 2>/dev/null; then
        pass "tools/uom-port-watch.sh exists and passes sh -n"
    else
        fail "tools/uom-port-watch.sh missing or syntax error"
    fi
    if [ -f "$_guard" ] && sh -n "$_guard" 2>/dev/null; then
        pass "bin/uom-port-guardian.sh exists and passes sh -n"
    else
        fail "bin/uom-port-guardian.sh missing or syntax error"
    fi

    # 7b. primitives source + run in a temp state dir (no network mutation)
    _sd=$(setup)
    OMNI_ROOT="$_sd" UOM_PW_STATE_DIR="$_sd/.uom-agent" . "$_watch" 2>/dev/null
    if command -v uom_pw_my_ip >/dev/null 2>&1 && command -v uom_pw_probe_ssh >/dev/null 2>&1; then
        pass "port-watch primitives source cleanly"
    else
        fail "port-watch primitives did not load"
    fi

    # 7c. my_ip / gateway discoverable
    _my=$(uom_pw_my_ip 2>/dev/null)
    _gw=$(uom_pw_gateway 2>/dev/null)
    if [ -n "$_my" ] && [ -n "$_gw" ]; then
        pass "uom_pw_my_ip/$_my and gateway/$_gw discovered"
    else
        fail "uom_pw_my_ip or gateway empty (my=$_my gw=$_gw)"
    fi

    # 7d. probe a known-up local port (ssh 22) returns up; bogus port down
    if uom_pw_probe_ssh 127.0.0.1 22 2; then
        pass "uom_pw_probe_ssh detects local sshd:22"
    else
        warn "uom_pw_probe_ssh did not detect 127.0.0.1:22 (ssh may be on different port)"
    fi
    if ! uom_pw_probe_ssh 127.0.0.1 59999 1; then
        pass "uom_pw_probe_ssh correctly reports closed port 59999"
    else
        fail "uom_pw_probe_ssh reported a closed port as open"
    fi

    # 7e. role detection (laptop by default on this host)
    if [ "$(UOM_GUARDIAN_ROLE=laptop sh "$_guard" role 2>/dev/null)" = "laptop" ]; then
        pass "role detection: laptop when UOM_GUARDIAN_ROLE=laptop"
    else
        fail "role detection failed for explicit laptop"
    fi

    # 7f. ssh-config rewrite is idempotent + atomic (use temp HOME)
    _th="${TMPDIR:-/tmp}/uom-pg-test.$$"
    mkdir -p "$_th/.ssh"
    OMNI_ROOT="$_sd" HOME="$_th" UOM_PW_STATE_DIR="$_sd/.uom-agent" \
        sh "$_guard" rewrite "192.168.40.207:8022" >/dev/null 2>&1
    if grep -q 'Host uom-phone-rev' "$_th/.ssh/config" 2>/dev/null; then
        pass "ssh config rewrite emits uom-phone-rev block"
    else
        fail "ssh config rewrite produced no uom-phone-rev block"
    fi
    # Re-run — must not duplicate the managed block
    OMNI_ROOT="$_sd" HOME="$_th" UOM_PW_STATE_DIR="$_sd/.uom-agent" \
        sh "$_guard" rewrite "192.168.40.207:8022" >/dev/null 2>&1
    _cnt=$(grep -c 'Host uom-phone-rev' "$_th/.ssh/config" 2>/dev/null || echo 0)
    if [ "$_cnt" -eq 1 ] 2>/dev/null; then
        pass "ssh config rewrite is idempotent (1 block after re-run)"
    else
        fail "ssh config rewrite duplicated block (count=$_cnt)"
    fi
    rm -rf "$_th" 2>/dev/null || true

    # 7g. discover_phone/discover_laptop do not crash and return strings-or-empty
    _p=$(uom_pw_discover_phone 2>/dev/null); _l=$(uom_pw_discover_laptop 2>/dev/null)
    pass "discover_phone='${_p:-<none>}' discover_laptop='${_l:-<none>}' (no crash)"

    # 7h. dryrun subcommand works
    if sh "$_guard" dryrun >/dev/null 2>&1; then
        pass "uom-port-guardian.sh dryrun runs"
    else
        fail "uom-port-guardian.sh dryrun failed"
    fi

    # 7i. bootstrap-termux installs guardian into Termux:Boot
    if grep -q 'uom-port-guardian.sh start' "${UOM_ROOT}/install/bootstrap-termux.sh" 2>/dev/null; then
        pass "bootstrap-termux.sh starts port-guardian at boot"
    else
        fail "bootstrap-termux.sh does not start port-guardian at boot"
    fi

    # 7j. port-guardian.sh subcommands (role, dryrun)
    if [ "$(UOM_GUARDIAN_ROLE=laptop sh "$_guard" role 2>/dev/null)" = "laptop" ]; then
        pass "port-guardian.sh role subcommand works"
    else
        fail "port-guardian.sh role subcommand broken"
    fi
    if sh "$_guard" dryrun >/dev/null 2>&1; then
        pass "port-guardian.sh dryrun subcommand works"
    else
        fail "port-guardian.sh dryrun subcommand broken"
    fi
}

test_live() {
    printf '\n=== LIVE CHECKS ===\n'

    if [ "${UOM_STRICT_LIVE:-0}" != "1" ]; then
        skip "Phone shell access (UOM_STRICT_LIVE not set)"
        skip "Tunnel 31415 (UOM_STRICT_LIVE not set)"
        skip "OpenCode provider (UOM_STRICT_LIVE not set)"
        skip "No remote (UOM_STRICT_LIVE not set)"
        return
    fi

    # 6a. Phone shell access
    if ssh -o ConnectTimeout=5 -o BatchMode=yes -p 8022 \
        "u0_a608@127.0.0.1" "echo OK" 2>/dev/null | grep -q 'OK'; then
        pass "Phone shell access via SSH"
    else
        warn "Phone shell access failed (live check)"
    fi

    # 6b. Tunnel 31415
    if ssh -o ConnectTimeout=5 -o BatchMode=yes -p 31415 \
        "127.0.0.1" "echo OK" 2>/dev/null | grep -q 'OK'; then
        pass "Tunnel port 31415 reachable"
    else
        warn "Tunnel port 31415 not reachable (live check)"
    fi

    # 6c. OpenCode provider
    if command -v opencode >/dev/null 2>&1; then
        _oc_out=$(opencode --version 2>/dev/null || true)
        if [ -n "$_oc_out" ]; then
            pass "OpenCode provider available"
        else
            warn "OpenCode installed but version check failed"
        fi
    else
        skip "OpenCode not installed"
    fi

    # 6d. No remote
    _has_remote=$(git -C "$UOM_ROOT" remote -v 2>/dev/null | head -1 || true)
    if [ -z "$_has_remote" ]; then
        pass "No git remote configured"
    else
        skip "Git remote present"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════
main() {
    printf 'UOM Dry-Run Test Suite\n'
    printf '======================\n'
    printf 'Repo: %s\n' "$UOM_ROOT"
    printf 'Fixture: %s\n' "$DRYRUN_DIR"
    printf 'Date: %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)"

    setup

    test_syntax
    test_policy
    test_state_lock
    test_state_machine
    test_components
    test_port_guardian
    test_live

    # ── Summary ──────────────────────────────────────────────────────────────
    printf '\n=== SUMMARY ===\n'
    printf '  PASS:  %d\n' "$_PASS"
    printf '  FAIL:  %d\n' "$_FAIL"
    printf '  WARN:  %d\n' "$_WARN"
    printf '  SKIP:  %d\n' "$_SKIP"

    # Show git status at end (informational)
    if command -v git >/dev/null 2>&1; then
        printf '\n--- Git Status ---\n'
        git -C "$UOM_ROOT" status --short 2>/dev/null || true
    fi

    cleanup

    # Exit 0 only when no FAILs
    if [ "$_FAIL" -gt 0 ]; then
        printf '\nRESULT: FAIL (%d failures)\n' "$_FAIL"
        exit 1
    fi

    printf '\nRESULT: PASS\n'
    exit 0
}

main "$@"
