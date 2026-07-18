Task M36: Verifier Feedback Loop
Create a feedback aggregation script that:
1. Reads all .uom-agent/verified/*.result files
2. Extracts PASS/FAIL/WARN status and reasons
3. Writes a summary to .uom-agent/feedback/summary.json
4. For failed tasks, writes detailed feedback to .uom-agent/feedback/{task_id}.json

Script: tools/uom-feedback-aggregator.sh
Requirements: POSIX sh, set -u, jq
