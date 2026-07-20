#!/bin/sh
# tools/uom-task-collect.sh — Collect task results from device outbox
# Usage: uom-task-collect <device> <task_id>

set -u

REPO=~/src/universal-omni-master
KEY=~/.ssh/id_ed25519_phone
DEVICE="${1:-}"
TASK_ID="${2:-}"

if [ -z "$DEVICE" ] || [ -z "$TASK_ID" ]; then
    echo "Usage: uom-task-collect <phone1|phone2|laptop> <task_id>"
    exit 1
fi

BUNDLE_DIR=$REPO/.uom-agent/bundles
mkdir -p "$BUNDLE_DIR"

case $DEVICE in
    laptop)
        RESULT=$REPO/.uom-agent/outbox/${TASK_ID}.json
        if [ -f "$RESULT" ]; then
            echo "=== RESULT ==="
            cat "$RESULT"
        else
            echo "NO_RESULT: $TASK_ID not found in laptop outbox"
        fi
        ;;
    phone1)
        RESULT_DIR=$(ssh -i $KEY -p 31415 u0_a608@127.0.0.1 \
            "cat ~/.uom-agent/outbox/${TASK_ID}.json 2>/dev/null" 2>/dev/null)
        if [ -n "$RESULT_DIR" ]; then
            echo "=== RESULT ==="
            echo "$RESULT_DIR"
            # Also collect bundle
            scp -i $KEY -P 31415 \
                "u0_a608@127.0.0.1:~/.uom-agent/outbox/${TASK_ID}.bundle" \
                "${BUNDLE_DIR}/phone1_${TASK_ID}.bundle" 2>/dev/null &&
                echo "BUNDLE: ${BUNDLE_DIR}/phone1_${TASK_ID}.bundle"
        else
            echo "NO_RESULT: $TASK_ID not found in phone1 outbox"
        fi
        ;;
    phone2)
        RESULT_DIR=$(ssh -i $KEY -p 31416 u0_a217@127.0.0.1 \
            "cat ~/.uom-agent/outbox/${TASK_ID}.json 2>/dev/null" 2>/dev/null)
        if [ -n "$RESULT_DIR" ]; then
            echo "=== RESULT ==="
            echo "$RESULT_DIR"
            scp -i $KEY -P 31416 \
                "u0_a217@127.0.0.1:~/.uom-agent/outbox/${TASK_ID}.bundle" \
                "${BUNDLE_DIR}/phone2_${TASK_ID}.bundle" 2>/dev/null &&
                echo "BUNDLE: ${BUNDLE_DIR}/phone2_${TASK_ID}.bundle"
        else
            echo "NO_RESULT: $TASK_ID not found in phone2 outbox"
        fi
        ;;
    *)
        echo "Unknown device: $DEVICE"
        exit 1
        ;;
esac
