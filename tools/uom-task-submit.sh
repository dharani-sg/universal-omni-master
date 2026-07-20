#!/bin/sh
# tools/uom-task-submit.sh — Submit a task to a device inbox
# Usage: uom-task-submit <device> "prompt"
# Devices: phone1, phone2, laptop

set -u

REPO=~/src/universal-omni-master
KEY=~/.ssh/id_ed25519_phone
DEVICE="${1:-}"
PROMPT="${2:-}"

if [ -z "$DEVICE" ] || [ -z "$PROMPT" ]; then
    echo "Usage: uom-task-submit <phone1|phone2|laptop> \"prompt\""
    exit 1
fi

TASK_ID="task-$(date +%s)"
BASE_COMMIT=$(cd $REPO && git rev-parse HEAD 2>/dev/null || echo "unknown")
DEADLINE=$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)

TASK_JSON=$(jq -n \
    --arg tid "$TASK_ID" \
    --arg prompt "$PROMPT" \
    --arg branch "task/${TASK_ID}/work" \
    --arg base "$BASE_COMMIT" \
    --arg deadline "$DEADLINE" \
    '{task_id:$tid,prompt:$prompt,branch:"task/\($tid)/work",base_commit:$base,
      deadline:$deadline,no_push:true,free_model_only:true}')

case $DEVICE in
    laptop)
        mkdir -p $REPO/.uom-agent/inbox
        echo "$TASK_JSON" > $REPO/.uom-agent/inbox/task.json
        echo "TASK_SUBMITTED: $TASK_ID -> laptop"
        ;;
    phone1)
        echo "$TASK_JSON" | ssh -i $KEY -p 31415 u0_a608@127.0.0.1 \
            "mkdir -p ~/.uom-agent/inbox; cat > ~/.uom-agent/inbox/task.json" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "TASK_SUBMITTED: $TASK_ID -> phone1 (tunnel)"
        else
            echo "$TASK_JSON" | ssh -i $KEY -p 8022 u0_a608@192.168.40.207 \
                "ssh -p 2222 uom@127.0.0.1 'mkdir -p ~/.uom-agent/inbox; cat > ~/.uom-agent/inbox/task.json'" 2>/dev/null
            echo "TASK_SUBMITTED: $TASK_ID -> phone1 (LAN/VM)"
        fi
        ;;
    phone2)
        echo "$TASK_JSON" | ssh -i $KEY -p 31416 u0_a217@127.0.0.1 \
            "mkdir -p ~/.uom-agent/inbox; cat > ~/.uom-agent/inbox/task.json" 2>/dev/null
        echo "TASK_SUBMITTED: $TASK_ID -> phone2 (tunnel)"
        ;;
    *)
        echo "Unknown device: $DEVICE (use phone1, phone2, laptop)"
        exit 1
        ;;
esac

echo "TASK_ID=$TASK_ID"
