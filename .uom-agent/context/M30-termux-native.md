## Context: M30 — Termux Native Polish

Implement Termux-native features for the UOM dual-agent phone orchestrator.

Required:
1. Haptic feedback via `termux-vibrate` on task start/fail
2. Push notifications via `termux-notification` for deployment status
3. Portrait-optimized (9:16) TUI reflow for phone SSH sessions
4. Termux:Boot auto-launch of orchestrator + reverse tunnel
5. Graceful degradation when not in Termux environment

Files to modify:
- `tools/uom-orch-phone.sh` — add notification hooks
- `bin/uom-reverse-ssh.sh` — verify Termux:Boot integration
- `orchestrators/uom-solo-orchestrator.sh` — add haptic/notification

Reference: `UOM-DUAL-AGENT/UOM-DUAL-AGENT-ORCHESTRATOR.md` Phase 1.10
