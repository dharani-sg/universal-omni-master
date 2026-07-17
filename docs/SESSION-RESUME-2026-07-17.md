# SESSION RESUME — 2026-07-17T14:37:46Z

Repo: `universal-omni-master` | branch: `main` | pre-push HEAD: `4ff111d`
Next commit (this session): dynamic port-guardian sentinel — see tag `v0.30.1` (timestamped).

## What was done this session
- **Root cause:** Termux (Android) changes its sshd port frequently, and the laptop's IP
  changes because it connects via the phone's wireless hotspot OR other WiFi. Static
  `~/.ssh/config` Host blocks drift out of sync within minutes.
- **New:** `tools/uom-port-watch.sh` (read-only discovery primitives) +
  `bin/uom-port-guardian.sh` (background sentinel: `start|stop|status|once|dryrun|rewrite|--loop`).
  Watches phone `host:port` + laptop IP, rewrites ssh config idempotently/atomically,
  publishes `.uom-agent/{phone,laptop}.host` hints, and signals the hybrid orchestrator via
  `.uom-agent/runtime/portguard.drift`.
- **Wired:** `bin/uom-hybrid.sh` (`_ensure_guardian` + `_check_drift`);
  `install/bootstrap-termux.sh` (Termux:Boot now launches the guardian);
  `scripts/uom-dryrun.sh` (`test_port_guardian`, 13 checks).
- **Docs:** README "Dynamic IP + Port Handling" section, CLI table, M30 row; AI-HANDOFF entry.
- **Verified:** dry-run **54 PASS / 0 FAIL**. Live: guardian running (PID 1657, tmux `uom-hybrid-pg`),
  hybrid running (PID 3074, dual mode), phone target `192.168.40.207:8022` discovered through hotspot.
- **Tunnel currently DOWN** — phone is not running `uom-reverse-ssh.sh` this session.

## Environment state
- Laptop: Alpine Linux 3.24, x86_64, `/dev/sda4` (only rootfs mounted).
- Void Linux dual-boot NOT accessible this session → sync via `git pull` on next Void boot.
- Phone: Xiaomi Mi 8, crDroid/Android 15, Termux. Tunnel port `31415`, phone sshd `8022`.
- Laptop `~/.ssh/config` `uom-phone-rev` now auto-managed by the guardian (points at live phone IP).
- Running: `uom-port-guardian.sh --loop 20` (PID 1657), `uom-hybrid.sh` (PID 3074),
  `uom-orch-laptop.sh` (spawned by hybrid).

## How to resume
```sh
cd ~/src/universal-omni-master
sh bin/uom-port-guardian.sh status     # live phone/laptop target + tunnel state
tmux attach -t uom-hybrid              # hybrid orchestrator session
sh scripts/uom-dryrun.sh               # must stay 0 FAIL after any change
# If phone comes online, on the PHONE run:
sh bin/uom-reverse-ssh.sh start        # guardian will keep it pointed at laptop
# Provision proot OpenCode on phone (one-time, needs tunnel up):
sh bin/uom-phone-provision.sh --auto
```

## Future todos (next session)
1. **M31 — Network Switching Stress Test:** toggle laptop between phone hotspot and another
   WiFi repeatedly; confirm the guardian keeps `~/.ssh/config` + tunnel correct with ZERO
   manual intervention and sub-20s convergence. Fix any edge case (e.g., both interfaces up).
2. **Phone-side guardian validation:** boot the phone, confirm Termux:Boot launches the
   guardian and it restarts `uom-reverse-ssh.sh` when the laptop IP changes (role=phone path).
3. **proot OpenCode provisioning:** run `bin/uom-phone-provision.sh --auto` once tunnel is up;
   verify OpenCode CLI works inside proot-distro Debian; wire `_opencode_bin` path into orch-phone.
4. **Void dual-boot sync:** on next Void boot, `git pull` to bring Void copy to this commit;
   optionally add a Void runit service for the port-guardian + hybrid orchestrator.
5. **Harden guardian:** add exponential-backoff on repeated restart failures; add a systemd
   (or OpenRC/runit) unit so it survives laptop reboot without Termux:Boot (laptop side).
6. **End-to-end dual verification:** with tunnel + proot OpenCode both up, run one real task
   across both agents and confirm git state machine handoff is clean.
7. **Docs:** add a `docs/NETWORK-DRIFT.md` runbook (guardian troubleshooting + manual override).

## Gates before any push
- `sh scripts/uom-dryrun.sh` → RESULT: PASS (0 FAIL).
- `git push` requires `UOM_ALLOW_PUSH=1` in `uom-orch-state.sh` (orchestrator path); direct
  CLI push is the operator's explicit choice.
- Prefer timestamped tag per milestone (e.g., `v0.30.1-<date>`).
