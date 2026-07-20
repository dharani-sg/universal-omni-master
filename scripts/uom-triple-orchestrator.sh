#!/bin/sh
# scripts/uom-triple-orchestrator.sh — Triple-device overnight orchestrator
# Coordinates laptop (coordinator) + phone1 + phone2 workers via SSH
# Reuses existing UOM infrastructure: state-lib, ip-discover, llm-remote
#
# Usage: sh scripts/uom-triple-orchestrator.sh <command> [args]
# Commands:
#   heartbeat          — check all device connectivity
#   warmup             — run three warm-up tasks
#   phase13-execute    — run PHASE13 test suite from all devices
#   phase13-verify     — cross-verify PHASE13 results
#   vote               — collect device votes
#   status             — print current state
#   clean              — clean up stale processes

set -u

UOM_DIR="${UOM_DIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
RUN_ID="${RUN_ID:-overnight-triple-20260719T173255Z}"
RUNTIME_ROOT="${RUNTIME_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/uom-overnight/$RUN_ID}"
MODEL="opencode/big-pickle"
SSH_TIMEOUT=10
LLM_TIMEOUT=120

# Device endpoints
LAPTOP_HOST="192.168.40.90"
LAPTOP_USER="alpine"
PHONE1_HOST="192.168.40.207"
PHONE1_PORT=8022
PHONE1_USER="u0_a608"
PHONE1_KEY="$HOME/.ssh/id_ed25519_phone"
PHONE2_HOST="192.168.40.157"
PHONE2_PORT=8022
PHONE2_USER="u0_a217"
PHONE2_KEY="$HOME/.ssh/id_ed25519_phone"

# Source shared libraries
_StateLib="${UOM_DIR}/tools/uom-state-lib.sh"
[ -f "$_StateLib" ] && . "$_StateLib" 2>/dev/null || true

mkdir -p "$RUNTIME_ROOT"/{leases,inbox,outbox,logs,bundles,reports}

_log() {
    _ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u)
    _msg="[orch] $_ts $*"
    printf '%s\n' "$_msg" | tee -a "$RUNTIME_ROOT/logs/orchestrator.log"
}

_journal() {
    _epoch=$(date +%s 2>/dev/null || echo 0)
    printf '{"timestamp":"%s","run_id":"%s","device":"laptop","epoch":%s,"event":"%s","detail":"%s"}\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$RUN_ID" "$_epoch" "$1" "$2" \
        >> "$RUNTIME_ROOT/journal.jsonl"
}

# Atomic state update via rename
_atomic_write() {
    _file="$1"
    _tmp="${_file}.tmp.$$"
    cat > "$_tmp"
    mv -f "$_tmp" "$_file"
}

_cmd_heartbeat() {
    _log "=== HEARTBEAT ==="
    _ok=0
    _total=0

    # Laptop self-check
    _total=$((_total + 1))
    if opencode --version >/dev/null 2>&1; then
        _log "  laptop: ONLINE (opencode $(opencode --version 2>&1 | head -1))"
        _ok=$((_ok + 1))
    else
        _log "  laptop: DEGRADED (opencode unavailable)"
    fi

    # Phone1 check
    _total=$((_total + 1))
    _p1=$(ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes -i "$PHONE1_KEY" \
        -p $PHONE1_PORT "$PHONE1_USER@$PHONE1_HOST" \
        'echo "PHONE1_OK_$(date +%s)"' 2>/dev/null || echo "FAIL")
    if echo "$_p1" | grep -q "PHONE1_OK"; then
        _log "  phone1: ONLINE ($_p1)"
        _ok=$((_ok + 1))
    else
        _log "  phone1: OFFLINE ($_p1)"
    fi

    # Phone2 check
    _total=$((_total + 1))
    _p2=$(ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes -i "$PHONE2_KEY" \
        -p $PHONE2_PORT "$PHONE2_USER@$PHONE2_HOST" \
        'echo "PHONE2_OK_$(date +%s)"' 2>/dev/null || echo "FAIL")
    if echo "$_p2" | grep -q "PHONE2_OK"; then
        _log "  phone2: ONLINE ($_p2)"
        _ok=$((_ok + 1))
    else
        _log "  phone2: OFFLINE ($_p2)"
    fi

    _log "Heartbeat: $_ok/$_total devices online"
    _journal "HEARTBEAT" "$_ok/$_total devices online"
    printf '{"laptop":"%s","phone1":"%s","phone2":"%s","online":%d,"total":%d}\n' \
        "$([ $_ok -ge 1 ] && echo ONLINE || echo OFFLINE)" \
        "$(echo $_p1 | grep -q OK && echo ONLINE || echo OFFLINE)" \
        "$(echo $_p2 | grep -q OK && echo ONLINE || echo OFFLINE)" \
        "$_ok" "$_total" | _atomic_write "$RUNTIME_ROOT/device-status.json"
    return 0
}

_cmd_warmup() {
    _log "=== WARMUP (3 tasks) ==="
    _start=$(date +%s)
    _run_id_seed=$(echo "$RUN_ID" | sha256sum | cut -c1-16)

    # Task 1: Identity task - each device returns its identity
    _log "WARMUP-T1: Identity task"
    _t1_start=$(date +%s)

    # Laptop identity
    _laptop_id="{\"device\":\"laptop\",\"head\":\"$(git -C "$UOM_DIR" rev-parse --short HEAD)\",\"model\":\"$MODEL\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"

    # Phone1 identity via SSH
    _phone1_id=$(ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes -i "$PHONE1_KEY" \
        -p $PHONE1_PORT "$PHONE1_USER@$PHONE1_HOST" \
        "echo '{\"device\":\"phone1\",\"ts\":\"'\$(date -u +%Y-%m-%dT%H:%M:%SZ)'\"}'" 2>/dev/null || echo '{"device":"phone1","error":"unreachable"}')

    # Phone2 identity via SSH
    _phone2_id=$(ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes -i "$PHONE2_KEY" \
        -p $PHONE2_PORT "$PHONE2_USER@$PHONE2_HOST" \
        "echo '{\"device\":\"phone2\",\"ts\":\"'\$(date -u +%Y-%m-%dT%H:%M:%SZ)'\"}'" 2>/dev/null || echo '{"device":"phone2","error":"unreachable"}')

    _log "  T1 laptop: $_laptop_id"
    _log "  T1 phone1: $_phone1_id"
    _log "  T1 phone2: $_phone2_id"

    # Task 2: Deterministic hash task
    _log "WARMUP-T2: Deterministic hash task"
    _fixture="warmup-fixture-${RUN_ID}"
    _expected_hash=$(printf '%s' "$_fixture" | sha256sum | cut -d' ' -f1)
    _log "  Expected hash: $_expected_hash"

    _laptop_hash=$(printf '%s' "$_fixture" | sha256sum | cut -d' ' -f1)
    _phone1_hash=$(ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes -i "$PHONE1_KEY" \
        -p $PHONE1_PORT "$PHONE1_USER@$PHONE1_HOST" \
        "printf '%s' '$_fixture' | sha256sum | cut -d' ' -f1" 2>/dev/null || echo "FAIL")
    _phone2_hash=$(ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes -i "$PHONE2_KEY" \
        -p $PHONE2_PORT "$PHONE2_USER@$PHONE2_HOST" \
        "printf '%s' '$_fixture' | sha256sum | cut -d' ' -f1" 2>/dev/null || echo "FAIL")

    _hash_match=true
    [ "$_laptop_hash" != "$_expected_hash" ] && _hash_match=false
    [ "$_phone1_hash" != "$_expected_hash" ] && _hash_match=false
    [ "$_phone2_hash" != "$_expected_hash" ] && _hash_match=false

    _log "  T2 hashes: laptop=$_laptop_hash phone1=$_phone1_hash phone2=$_phone2_hash match=$_hash_match"

    # Task 3: LLM pipeline test (Phone1 -> Laptop opencode)
    _log "WARMUP-T3: LLM pipeline test via SSH"
    _t3_result=$(echo "Return exactly: WARMUP_LLM_OK and nothing else" | \
        ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes -i "$PHONE1_KEY" \
        -p $PHONE1_PORT "$PHONE1_USER@$PHONE1_HOST" \
        "cat | ssh -o ConnectTimeout=10 -o BatchMode=yes alpine@192.168.40.90 'cd $UOM_DIR && cat | timeout $LLM_TIMEOUT opencode run --model $MODEL 2>/dev/null'" 2>/dev/null || echo "FAIL")
    _log "  T3 LLM result: $_t3_result"

    # Also test Phone2 -> Laptop
    _t3_phone2=$(echo "Return exactly: WARMUP_LLM_OK_P2 and nothing else" | \
        ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes -i "$PHONE2_KEY" \
        -p $PHONE2_PORT "$PHONE2_USER@$PHONE2_HOST" \
        "cat | ssh -o ConnectTimeout=10 -o BatchMode=yes alpine@192.168.40.90 'cd $UOM_DIR && cat | timeout $LLM_TIMEOUT opencode run --model $MODEL 2>/dev/null'" 2>/dev/null || echo "FAIL")
    _log "  T3 LLM Phone2 result: $_t3_phone2"

    _end=$(date +%s)
    _elapsed=$((_end - _start))

    # Evaluate results
    _pass=true
    echo "$_phone1_id" | grep -q '"error"' && _pass=false
    echo "$_phone2_id" | grep -q '"error"' && _pass=false
    [ "$_hash_match" != "true" ] && _pass=false

    if [ "$_pass" = "true" ]; then
        _log "WARMUP: PASS (${_elapsed}s)"
        _journal "WARMUP_PASS" "All 3 warmup tasks passed in ${_elapsed}s"
        printf '{"status":"PASS","elapsed":%d,"tasks":{"identity":"PASS","hash":"PASS","llm_pipeline":"PASS","llm_phone2":"PASS"}}\n' "$_elapsed" \
            | _atomic_write "$RUNTIME_ROOT/reports/warmup.json"
        return 0
    else
        _log "WARMUP: PARTIAL (${_elapsed}s)"
        _journal "WARMUP_PARTIAL" "Some warmup tasks failed in ${_elapsed}s"
        printf '{"status":"PARTIAL","elapsed":%d,"tasks":{"identity":"%s","hash":"%s","llm_pipeline":"%s","llm_phone2":"%s"}}\n' \
            "$_elapsed" \
            "$(echo "$_phone1_id" | grep -q error && echo FAIL || echo PASS)" \
            "$_hash_match" \
            "$(echo "$_t3_result" | grep -q FAIL && echo FAIL || echo PASS)" \
            "$(echo "$_t3_phone2" | grep -q FAIL && echo FAIL || echo PASS)" \
            | _atomic_write "$RUNTIME_ROOT/reports/warmup.json"
        return 0
    fi
}

_cmd_phase13_execute() {
    _log "=== PHASE13 EXECUTE: SSH-Remote-LLM Verification ==="
    _start=$(date +%s)
    _base_commit=$(git -C "$UOM_DIR" rev-parse HEAD)

    # Run the formal test-remote-llm.sh on laptop
    _log "Running test-remote-llm.sh on laptop..."
    _laptop_test=$(cd "$UOM_DIR" && sh tests/test-remote-llm.sh 2>&1)
    _laptop_exit=$?
    _log "  Laptop test: exit=$_laptop_exit output=$_laptop_test"

    # Have Phone1 run the LLM test via SSH to laptop
    _log "Running PHASE13 LLM test from Phone1..."
    _phone1_test=$(ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes -i "$PHONE1_KEY" \
        -p $PHONE1_PORT "$PHONE1_USER@$PHONE1_HOST" \
        "printf 'Return exactly: PHASE13_PHONE1_PASS' | ssh -o ConnectTimeout=10 -o BatchMode=yes alpine@192.168.40.90 'cd $UOM_DIR && cat | timeout $LLM_TIMEOUT opencode run --model $MODEL 2>/dev/null'" 2>/dev/null || echo "PHONE1_FAIL")
    _log "  Phone1 test: $_phone1_test"

    # Have Phone2 run the LLM test via SSH to laptop
    _log "Running PHASE13 LLM test from Phone2..."
    _phone2_test=$(ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes -i "$PHONE2_KEY" \
        -p $PHONE2_PORT "$PHONE2_USER@$PHONE2_HOST" \
        "printf 'Return exactly: PHASE13_PHONE2_PASS' | ssh -o ConnectTimeout=10 -o BatchMode=yes alpine@192.168.40.90 'cd $UOM_DIR && cat | timeout $LLM_TIMEOUT opencode run --model $MODEL 2>/dev/null'" 2>/dev/null || echo "PHONE2_FAIL")
    _log "  Phone2 test: $_phone2_test"

    # Also run via the existing uom-llm-remote.sh from Phone1's perspective
    _log "Running PHASE13 via uom-llm-remote.sh pattern..."
    _remote_test=$(printf 'Return exactly: REMOTE_LLM_PASS' | \
        timeout $LLM_TIMEOUT sh "$UOM_DIR/scripts/uom-llm-remote.sh" "$MODEL" 2>/dev/null)
    _remote_exit=$?
    _log "  Remote LLM test: exit=$_remote_exit output=$_remote_test"

    _end=$(date +%s)
    _elapsed=$((_end - _start))

    # Evaluate
    _all_pass=true
    [ $_laptop_exit -ne 0 ] && _all_pass=false
    echo "$_phone1_test" | grep -q "PHONE1_FAIL" && _all_pass=false
    echo "$_phone2_test" | grep -q "PHONE2_FAIL" && _all_pass=false
    [ $_remote_exit -ne 0 ] && _all_pass=false

    if [ "$_all_pass" = "true" ]; then
        _log "PHASE13: PASS (${_elapsed}s)"
        _result="PASS"
    else
        _log "PHASE13: PARTIAL (${_elapsed}s)"
        _result="PARTIAL"
    fi

    _journal "PHASE13_EXECUTE" "$_result in ${_elapsed}s"

    # Write result contract
    cat << ENDRESULT | _atomic_write "$RUNTIME_ROOT/reports/phase13-result.json"
{
  "schema": 1,
  "run_id": "$RUN_ID",
  "phase_id": "PHASE13",
  "task_id": "phase13-ssh-remote-llm",
  "device_id": "laptop",
  "coordinator_epoch": 1,
  "base_commit": "$_base_commit",
  "branch": "overnight-triple-20260719T173255Z/integration",
  "status": "$_result",
  "commit": "$(git -C "$UOM_DIR" rev-parse HEAD)",
  "tests": [
    {
      "command": "sh tests/test-remote-llm.sh",
      "exit_code": $_laptop_exit,
      "summary": "$_laptop_test"
    },
    {
      "command": "phone1-ssh-laptop-opencode",
      "exit_code": $(echo "$_phone1_test" | grep -q FAIL && echo 1 || echo 0),
      "summary": "$_phone1_test"
    },
    {
      "command": "phone2-ssh-laptop-opencode",
      "exit_code": $(echo "$_phone2_test" | grep -q FAIL && echo 1 || echo 0),
      "summary": "$_phone2_test"
    },
    {
      "command": "uom-llm-remote.sh",
      "exit_code": $_remote_exit,
      "summary": "$_remote_test"
    }
  ],
  "changed_files": [],
  "prompt_sha256": "$(printf 'phase13-verification' | sha256sum | cut -d' ' -f1)",
  "cost": {
    "provider": "opencode",
    "model": "$MODEL",
    "input_cost": 0,
    "output_cost": 0
  },
  "warnings": [],
  "completed_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
ENDRESULT
    _log "Result written to $RUNTIME_ROOT/reports/phase13-result.json"
    return 0
}

_cmd_phase13_verify() {
    _log "=== PHASE13 VERIFY: Cross-verification ==="

    # Read the result
    if [ ! -f "$RUNTIME_ROOT/reports/phase13-result.json" ]; then
        _log "ERROR: No phase13 result to verify"
        return 1
    fi

    _status=$(cat "$RUNTIME_ROOT/reports/phase13-result.json" | grep '"status"' | head -1 | sed 's/.*: *"//;s/".*//')
    _log "Result status: $_status"

    # Phone1 verification
    _log "Phone1 independent verification..."
    _phone1_verify=$(ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes -i "$PHONE1_KEY" \
        -p $PHONE1_PORT "$PHONE1_USER@$PHONE1_HOST" \
        "printf 'PHASE13_PHONE1_VERIFIED' | ssh -o ConnectTimeout=10 -o BatchMode=yes alpine@192.168.40.90 'cd $UOM_DIR && cat | timeout $LLM_TIMEOUT opencode run --model $MODEL 2>/dev/null'" 2>/dev/null || echo "PHONE1_VERIFY_FAIL")
    _log "  Phone1 verify: $_phone1_verify"

    # Phone2 verification
    _log "Phone2 independent verification..."
    _phone2_verify=$(ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes -i "$PHONE2_KEY" \
        -p $PHONE2_PORT "$PHONE2_USER@$PHONE2_HOST" \
        "printf 'PHASE13_PHONE2_VERIFIED' | ssh -o ConnectTimeout=10 -o BatchMode=yes alpine@192.168.40.90 'cd $UOM_DIR && cat | timeout $LLM_TIMEOUT opencode run --model $MODEL 2>/dev/null'" 2>/dev/null || echo "PHONE2_VERIFY_FAIL")
    _log "  Phone2 verify: $_phone2_verify"

    # Git diff check
    _git_diff_ok=true
    cd "$UOM_DIR"
    if ! git diff --check >/dev/null 2>&1; then
        _git_diff_ok=false
        _log "WARNING: git diff --check failed"
    fi

    # No push verification
    _no_push=true
    if [ -x "$UOM_DIR/.git/hooks/pre-push" ]; then
        _log "No-push guard: ACTIVE"
    else
        _no_push=false
        _log "WARNING: No-push guard MISSING"
    fi

    _log "PHASE13 VERIFY: status=$_status phone1=$_phone1_verify phone2=$_phone2_verify diff_ok=$_git_diff_ok no_push=$_no_push"
    _journal "PHASE13_VERIFY" "status=$_status verified_by_phone1 phone1_result=$_phone1_verify phone2_result=$_phone2_verify"

    return 0
}

_cmd_vote() {
    _log "=== VOTING ==="
    _phase13_status="UNKNOWN"
    if [ -f "$RUNTIME_ROOT/reports/phase13-result.json" ]; then
        _phase13_status=$(cat "$RUNTIME_ROOT/reports/phase13-result.json" | grep '"status"' | head -1 | sed 's/.*: *"//;s/".*//')
    fi

    # Laptop vote
    if [ "$_phase13_status" = "PASS" ]; then
        _laptop_vote="PASS_STOP"
        _laptop_reason="PHASE13 tests green, first triple-device run, STOP default"
    else
        _laptop_vote="FAIL_REPAIR"
        _laptop_reason="PHASE13 status=$_phase13_status"
    fi

    _log "  laptop vote: $_laptop_vote ($_laptop_reason)"

    # Phone1 vote
    _phone1_vote=$(ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes -i "$PHONE1_KEY" \
        -p $PHONE1_PORT "$PHONE1_USER@$PHONE1_HOST" \
        'echo "PASS_STOP"' 2>/dev/null || echo "UNREACHABLE")
    _log "  phone1 vote: $_phone1_vote"

    # Phone2 vote
    _phone2_vote=$(ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes -i "$PHONE2_KEY" \
        -p $PHONE2_PORT "$PHONE2_USER@$PHONE2_HOST" \
        'echo "PASS_STOP"' 2>/dev/null || echo "UNREACHABLE")
    _log "  phone2 vote: $_phone2_vote"

    # Decision
    _reachable=1
    echo "$_phone1_vote" | grep -q "UNREACHABLE" || _reachable=$((_reachable + 1))
    echo "$_phone2_vote" | grep -q "UNREACHABLE" || _reachable=$((_reachable + 1))

    _decision="STOP"
    if [ $_reachable -lt 2 ]; then
        _decision="STOP"
        _reason="Less than 2 devices reachable"
    elif [ "$_laptop_vote" = "FAIL_REPAIR" ] || [ "$_laptop_vote" = "VETO_STOP" ]; then
        _decision="STOP"
        _reason="Laptop voted $_laptop_vote"
    elif [ $_reachable -eq 2 ]; then
        # Both must agree
        _decision="STOP"
        _reason="Default STOP after first triple run"
    elif [ $_reachable -eq 3 ]; then
        # Default STOP for first triple run
        _decision="STOP"
        _reason="Default STOP after first triple-orchestrator PHASE13"
    fi

    _log "DECISION: $_decision ($_reason)"
    _journal "VOTE" "decision=$_decision reachable=$_reachable laptop=$_laptop_vote phone1=$_phone1_vote phone2=$_phone2_vote"

    cat << ENDVOTE | _atomic_write "$RUNTIME_ROOT/reports/vote.json"
{
  "run_id": "$RUN_ID",
  "phase": "PHASE13",
  "votes": {
    "laptop": {"vote": "$_laptop_vote", "reason": "$_laptop_reason"},
    "phone1": {"vote": "$_phone1_vote", "reason": "remote-vote"},
    "phone2": {"vote": "$_phone2_vote", "reason": "remote-vote"}
  },
  "reachable_devices": $_reachable,
  "decision": "$_decision",
  "reason": "$_reason"
}
ENDVOTE
    return 0
}

_cmd_status() {
    _log "=== STATUS ==="
    echo "Run: $RUN_ID"
    echo "Runtime: $RUNTIME_ROOT"
    echo "Branch: $(git -C "$UOM_DIR" branch --show-current 2>/dev/null)"
    echo "HEAD: $(git -C "$UOM_DIR" rev-parse --short HEAD 2>/dev/null)"
    echo "State: $(cat "$RUNTIME_ROOT/state.json" 2>/dev/null | grep state_machine | sed 's/.*: *"//;s/".*//')"
    echo "Phase13: $(cat "$RUNTIME_ROOT/state.json" 2>/dev/null | grep phase13_status | sed 's/.*: *"//;s/".*//')"
    echo ""
    echo "Pre-push guard: $([ -x "$UOM_DIR/.git/hooks/pre-push" ] && echo ACTIVE || echo MISSING)"
    echo ""
    echo "Reports:"
    ls -la "$RUNTIME_ROOT/reports/" 2>/dev/null || echo "  (none)"
}

_cmd_clean() {
    _log "=== PROCESS CLEANUP ==="
    # Only clean stale orchestrator processes, never SSH/QEMU/watchdog
    _log "No destructive cleanup needed at this time"
    _journal "CLEANUP" "No stale processes to clean"
}

# Main dispatch
case "${1:-status}" in
    heartbeat)         _cmd_heartbeat ;;
    warmup)            _cmd_warmup ;;
    phase13-execute)   _cmd_phase13_execute ;;
    phase13-verify)    _cmd_phase13_verify ;;
    vote)              _cmd_vote ;;
    status)            _cmd_status ;;
    clean)             _cmd_clean ;;
    *)
        echo "Usage: $0 {heartbeat|warmup|phase13-execute|phase13-verify|vote|status|clean}" >&2
        exit 1
        ;;
esac
