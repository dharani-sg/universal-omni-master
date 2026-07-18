Task M33: SSH Remote LLM Pipeline
Create a simple test script that:
1. Sends a test prompt via SSH to laptop
2. Receives opencode response
3. Validates the response is non-empty
4. Prints PASS or FAIL

Script: tests/test-remote-llm.sh
Requirements: POSIX sh, set -u, uses SSH to 192.168.40.90
