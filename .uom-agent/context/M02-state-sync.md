## Context: M02 — State Sync Verification

Verify that the dual-agent state synchronization works correctly between laptop and phone.

Current setup:
- Both devices share state via .uom-agent/state.json in GitHub
- Laptop pushes via HTTPS with gh auth
- Phone pushes via HTTPS with stored PAT token
- Both use uom-orch-state.sh for state management

Task: Create a verification script that:
1. Tests write from laptop, read from phone
2. Tests write from phone, read from laptop
3. Verifies heartbeat freshness detection
4. Tests queue add/mark-done cycle
