Task M34: Phone Generator Agent Loop
Create a monitoring script that:
1. Watches .uom-agent/queue.json for pending tasks
2. Picks the highest priority pending task
3. Calls scripts/uom-llm-remote.sh to generate code
4. Writes output to .uom-agent/generated/{task_id}.sh
5. Marks task as in_progress in queue.json
6. Polls every 10 seconds

Script: tools/uom-phone-gen-loop.sh
Requirements: POSIX sh, set -u, jq, single-instance lock
