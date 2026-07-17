## Context: M30 — Auto-Healing Reverse Tunnel

Implement auto-healing for the reverse SSH tunnel with Termux:Boot auto-launch.

Required:
1. Ensure `~/.termux/boot/start-uom.sh` properly starts reverse tunnel on phone boot
2. Add exponential backoff to tunnel reconnection (1s, 2s, 4s, 8s, max 60s)
3. Log tunnel status to `~/.uom-termux-user/tunnel.log` with timestamps
4. Verify tunnel integrity every 60s, restart if down
5. Add watchdog that restarts tunnel if process dies unexpectedly

Files to modify:
- `bin/uom-reverse-ssh.sh` — add backoff + watchdog
- `UOM-DUAL-AGENT/setup/phone-bootstrap.sh` — verify Termux:Boot script
- `orchestrators/uom-watchdog.sh` — add tunnel health check

Reference: `UOM-DUAL-AGENT/UOM-DUAL-AGENT-ORCHESTRATOR.md` Phase 6
