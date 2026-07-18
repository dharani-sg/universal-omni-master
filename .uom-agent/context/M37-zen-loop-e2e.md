Task M37: End-to-End Zen Loop Test
Create a test orchestrator that:
1. Ensures phone generator is running
2. Ensures laptop verifier is running
3. Waits for at least one task to be verified
4. Checks that feedback was written for any failures
5. Prints a summary of the full pipeline state

Script: tests/test-zen-loop-e2e.sh
Requirements: POSIX sh, set -u, SSH access to both devices
