## Context: M30 — Termux Native Tools ✅ DONE

**Status:** Complete. Tag v0.30.0.

Delivered:
1. `bin/omni-project-start.sh` — Interactive TUI dashboard with 9 sub-commands. Works on Alpine + Termux. Fish TUI, POSIX shell logic.
2. `bin/uom-tmux-watchdog.sh` — Monitors `uom` and `uom-orch` tmux sessions, auto-recreates on crash, restarts orchestrator/tunnel. 30s daemon loop.
3. `install/setup-aliases.sh` — 14 UOM aliases (omni, omni-start, omni-menu, omni-status, omni-detach, omni-aware, omni-test, omni-recover, uom-tmux-watchdog, uom-tunnel, uom-tmux, uom-shell) for both Alpine `.profile` and Termux `.bashrc`.
4. `bin/uom-deploy-phone.sh` — SCP-based deployment of scripts + aliases + boot config to phone.
5. Tunnel fix: removed `ExitOnForwardFailure=yes` and `fuser -k 18022/tcp` (false positives killed tunnel).
6. Termux:Boot updated: starts SSH, tunnel, tmux watchdog, phone orchestrator.

Next: M31 — Network Switching Stress Test
