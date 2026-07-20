#!/bin/sh
# UOM Trident v2 — 3-device autonomous agent runtime
# Usage: ./uom-trident-v2.sh [--task "prompt"] [--phase PHASE14] [--check]
# If no task given, runs in DISCOVERY+IDLE mode — devices check in and stay ready

set -u

REPO=~/src/universal-omni-master
KEY=~/.ssh/id_ed25519_phone
LOG=~/.uom-agent/trident-v2.log
REGISTRY=$REPO/.uom-agent/endpoint-registry.json

# ══════════════════════════════════════════════════════════════════════════
# LOGGING
# ══════════════════════════════════════════════════════════════════════════
_tlog() {
    _ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
    printf '[%s] %s\n' "$_ts" "$*" | tee -a "$LOG" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════════════════
# DEVICE DISCOVERY
# ══════════════════════════════════════════════════════════════════════════
discover_devices() {
    AVAILABLE=""
    AVAILABLE_COUNT=0

    # Laptop always available
    AVAILABLE="$AVAILABLE laptop:127.0.0.1:0:alpine"
    AVAILABLE_COUNT=$((AVAILABLE_COUNT + 1))

    # Phone1 via reverse tunnel (or direct LAN)
    P1_HOST=$(cat $REPO/.uom-agent/phone.host 2>/dev/null | cut -d: -f1 2>/dev/null || echo "192.168.40.207")
    P1_PORT=$(cat $REPO/.uom-agent/phone.host 2>/dev/null | cut -d: -f2 2>/dev/null || echo "8022")
    if timeout 5 ssh -i $KEY -o BatchMode=yes -o ConnectTimeout=3 \
         -p $P1_PORT u0_a608@$P1_HOST "echo ok" >/dev/null 2>&1; then
        AVAILABLE="$AVAILABLE phone1:$P1_HOST:$P1_PORT:u0_a608"
        AVAILABLE_COUNT=$((AVAILABLE_COUNT + 1))
    elif timeout 5 ssh -i $KEY -o BatchMode=yes -o ConnectTimeout=3 \
         -p 31415 u0_a608@127.0.0.1 "echo ok" >/dev/null 2>&1; then
        AVAILABLE="$AVAILABLE phone1:127.0.0.1:31415:u0_a608"
        AVAILABLE_COUNT=$((AVAILABLE_COUNT + 1))
    fi

    # Phone2 via reverse tunnel (or direct LAN)
    if timeout 5 ssh -i $KEY -o BatchMode=yes -o ConnectTimeout=3 \
         -p 31416 u0_a217@127.0.0.1 "echo ok" >/dev/null 2>&1; then
        AVAILABLE="$AVAILABLE phone2:127.0.0.1:31416:u0_a217"
        AVAILABLE_COUNT=$((AVAILABLE_COUNT + 1))
    elif timeout 5 ssh -i $KEY -o BatchMode=yes -o ConnectTimeout=3 \
         -p 8022 u0_a217@192.168.40.157 "echo ok" >/dev/null 2>&1; then
        AVAILABLE="$AVAILABLE phone2:192.168.40.157:8022:u0_a217"
        AVAILABLE_COUNT=$((AVAILABLE_COUNT + 1))
    fi

    _tlog "AVAILABLE_DEVICES=$AVAILABLE_COUNT:$AVAILABLE"
}

# ══════════════════════════════════════════════════════════════════════════
# ROLE ASSIGNMENT (deterministic priority: laptop > phone1 > phone2)
# ══════════════════════════════════════════════════════════════════════════
assign_roles() {
    MODE=""
    COORDINATOR=""
    WORKER1=""
    WORKER2=""

    case $AVAILABLE_COUNT in
        3)
            MODE="TRIPLE"
            COORDINATOR="laptop"
            WORKER1="phone1"
            WORKER2="phone2" ;;
        2)
            case "$AVAILABLE" in
                *laptop*phone1*)
                    MODE="DUAL_L_P1"; COORDINATOR="laptop"; WORKER1="phone1" ;;
                *laptop*phone2*)
                    MODE="DUAL_L_P2"; COORDINATOR="laptop"; WORKER1="phone2" ;;
                *phone1*phone2*)
                    MODE="DUAL_PHONE"; COORDINATOR="phone1"; WORKER1="phone2" ;;
            esac ;;
        1)
            MODE="SOLO"; COORDINATOR="laptop" ;;
        *)
            MODE="NONE"; return 1 ;;
    esac
    _tlog "MODE=$MODE COORDINATOR=$COORDINATOR WORKER1=$WORKER1 WORKER2=$WORKER2"
}

# ══════════════════════════════════════════════════════════════════════════
# TASK ASSIGNMENT
# ══════════════════════════════════════════════════════════════════════════
assign_task() {
    _device=$1 _task_id=$2 _prompt=$3 _branch=$4
    _base_commit=$(cd $REPO && git rev-parse HEAD 2>/dev/null || echo "unknown")
    _deadline=$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)

    _task_json=$(jq -n \
        --arg tid "$_task_id" \
        --arg prompt "$_prompt" \
        --arg branch "$_branch" \
        --arg base "$_base_commit" \
        --arg deadline "$_deadline" \
        '{task_id:$tid,prompt:$prompt,branch:$branch,base_commit:$base,
          deadline:$deadline,no_push:true,free_model_only:true}')

    case $_device in
        laptop)
            mkdir -p $REPO/.uom-agent/inbox
            echo "$_task_json" > $REPO/.uom-agent/inbox/task.json ;;
        phone1)
            ssh -i $KEY -p 31415 u0_a608@127.0.0.1 \
                "mkdir -p ~/.uom-agent/inbox; cat > ~/.uom-agent/inbox/task.json" \
                <<< "$_task_json" 2>/dev/null ||
            ssh -i $KEY -p 8022 u0_a608@192.168.40.207 \
                "ssh -p 2222 uom@127.0.0.1 'mkdir -p ~/.uom-agent/inbox; cat > ~/.uom-agent/inbox/task.json'" \
                <<< "$_task_json" 2>/dev/null ;;
        phone2)
            ssh -i $KEY -p 31416 u0_a217@127.0.0.1 \
                "mkdir -p ~/.uom-agent/inbox; cat > ~/.uom-agent/inbox/task.json" \
                <<< "$_task_json" 2>/dev/null ;;
    esac
    _tlog "TASK_ASSIGNED: $_task_id -> $_device"
}

# ══════════════════════════════════════════════════════════════════════════
# RESULT COLLECTION
# ══════════════════════════════════════════════════════════════════════════
collect_result() {
    _device=$1 _task_id=$2
    _bundle_dest=$REPO/.uom-agent/bundles/${_device}_${_task_id}.bundle

    mkdir -p $REPO/.uom-agent/bundles
    case $_device in
        phone1)
            scp -i $KEY -P 31415 \
                "u0_a608@127.0.0.1:~/.uom-agent/outbox/${_task_id}.bundle" \
                "${_bundle_dest}.tmp" 2>/dev/null &&
            mv "${_bundle_dest}.tmp" "$_bundle_dest" &&
            git -C "$REPO" bundle verify "$_bundle_dest" &&
            _tlog "BUNDLE_COLLECTED: $_bundle_dest" || _tlog "BUNDLE_FAILED: $_device/$_task_id" ;;
        phone2)
            scp -i $KEY -P 31416 \
                "u0_a217@127.0.0.1:~/.uom-agent/outbox/${_task_id}.bundle" \
                "${_bundle_dest}.tmp" 2>/dev/null &&
            mv "${_bundle_dest}.tmp" "$_bundle_dest" &&
            git -C "$REPO" bundle verify "$_bundle_dest" &&
            _tlog "BUNDLE_COLLECTED: $_bundle_dest" || _tlog "BUNDLE_FAILED: $_device/$_task_id" ;;
    esac
}

# ══════════════════════════════════════════════════════════════════════════
# VOTING GATE (stub — single reviewer for now)
# ══════════════════════════════════════════════════════════════════════════
vote_on_result() {
    _task_id=$1
    _tlog "VOTE_PASS (auto — single reviewer for now)"
    return 0
}

# ══════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════
_tlog "UOM Trident v2 started $(date -Iseconds)"
discover_devices
assign_roles

if [ "${1:-}" = "--check" ]; then
    echo "STATUS: MODE=$MODE devices=$AVAILABLE_COUNT coordinator=$COORDINATOR"
    echo "AVAILABLE: $AVAILABLE"
    exit 0
fi

if [ "${2:-}" != "" ] && [ "${1:-}" = "--task" ]; then
    TASK_PROMPT="$2"
    TASK_ID="task-$(date +%s)"
    if [ -n "$WORKER1" ]; then
        assign_task "$WORKER1" "$TASK_ID" "$TASK_PROMPT" "task/${TASK_ID}/work"
        echo "Task assigned to $WORKER1. Collect with: --collect $TASK_ID"
    else
        _tlog "NO_WORKER_AVAILABLE"
        echo "No workers available"
        exit 1
    fi
fi

if [ "${1:-}" = "--collect" ] && [ "${2:-}" != "" ]; then
    collect_result "$WORKER1" "$2"
    exit 0
fi

_tlog "Trident v2 idle — MODE=$MODE"
