# SESSION RESUME — 2026-07-17 (Full Day)

Repo: `universal-omni-master` | branch: `main` | pre-push HEAD: `680cd3d`
Next commit (this session): cloud-only redirect + Zen Loop reconciler — see tag `v0.31.0-2026-07-17`.

## What was done this session

### Part 1: Dynamic Port-Guardian (first half)
- **Root cause:** Termux (Android) changes its sshd port frequently, laptop IP changes on hotspot/WiFi.
  Static `~/.ssh/config` Host blocks drift out of sync within minutes.
- **New:** `tools/uom-port-watch.sh` (read-only discovery) + `bin/uom-port-guardian.sh`
  (background sentinel: start|stop|status|once|dryrun|rewrite|--loop).
  Watches phone `host:port` + laptop IP, rewrites ssh config idempotently/atomically,
  publishes `.uom-agent/{phone,laptop}.host` hints, signals hybrid orchestrator via
  `.uom-agent/runtime/portguard.drift`.
- **Wired:** `bin/uom-hybrid.sh` (ensure_guardian + check_drift);
  `install/bootstrap-termux.sh` (Termux:Boot launches guardian);
  `scripts/uom-dryrun.sh` (test_port_guardian, 13 checks).
- **Verified:** dry-run 54 PASS / 0 FAIL. Live: guardian (PID 1657, tmux uom-hybrid-pg),
  hybrid (PID 3074, dual mode), phone 192.168.40.207:8022.

### Part 2: Cloud-Only Redirect + Zen Loop (second half)
- **Critical redirect:** removed ALL Ollama/local-LLM references. No sudo, no binaries,
  no API keys. `uom-generator.sh` and `uom-reconcile.sh` use pure cloud model
  `opencode --model opencode/deepseek-v4-flash-free` with stdin pipe.
- **New:** `scripts/uom-reconcile.sh` — 6-step orchestrator:
  1. pre-flight (curl, jq, internet, sh -n)
  2. tmux session auto-create
  3. bootstrap cloud env
  4. tunnel check
  5. guardian start
  6. zen loop (generate → verify → reconcile)
- **New:** `scripts/uom-generator.sh` — cloud-only code generator via opencode stdin
  with 3-retry exponential backoff + stub fallback.
- **Rewritten:** `scripts/uom-proot-setup.sh` — cloud env verifier (curl/jq/internet
  with graceful retry, zero ollama).
- **Unchanged:** `scripts/uom-verifier.sh` — syntax/policy verifier, no LLM calls.
- **All 4 scripts:** POSIX sh, pass `sh -n`, executable, zero ollama/sudo references.
- **Network:** tunnel traffic forced to 127.0.0.1 to avoid hotspot routing loops.

## Environment state
- Laptop: Alpine Linux 3.24, x86_64, /dev/sda4.
- Void Linux dual-boot NOT synced this session — git pull on next Void boot.
- Phone: Xiaomi Mi 8, crDroid/Android 15, Termux. Port 8022, tunnel port 31415.
- Laptop ~/.ssh/config uom-phone-rev auto-managed by guardian.
- Running: port-guardian (PID 1657), hybrid (PID 3074).
- Tunnel currently DOWN — phone not running uom-reverse-ssh.sh this session.
- Model: `opencode/deepseek-v4-flash-free` (pure cloud, no local LLM).

## How to resume
```sh
cd ~/src/universal-omni-master
sh bin/uom-port-guardian.sh status     # live phone/laptop target + tunnel state
sh scripts/uom-reconcile.sh            # full 6-step: preflight → tmux → boot → tunnel → guardian → zen
tmux attach -t uom-hybrid              # hybrid orchestrator session
sh scripts/uom-dryrun.sh               # must stay 0 FAIL after any change
```
To run just the Zen loop generator + verifier:
```sh
scripts/uom-generator.sh "write a POSIX sh function that..."  # generates code
scripts/uom-verifier.sh /path/to/file.sh                       # validates
```
To start the full reconcile pipeline:
```sh
scripts/uom-reconcile.sh                                       # 6-step orchestrator
```

## Future todos (next session)
1. **M31 — Network Switching Stress Test:** toggle laptop between phone hotspot and
   another WiFi; confirm guardian + tunnel survive with sub-20s convergence.
2. **Phone-side guardian:** boot phone, confirm Termux:Boot launches guardian + reverse-ssh.
3. **Phone reconcile:** port reconcile.sh to phone side for solo-mode Zen loop.
4. **Void dual-boot sync:** git pull on next Void boot; add runit service for port-guardian.
5. **Harden guardian:** exponential backoff on restart failures; OpenRC/runit unit.
6. **End-to-end dual verification:** run one real task across both agents with clean handoff.
7. **Docs:** docs/NETWORK-DRIFT.md runbook; docs/ZEN-LOOP.md for reconciler details.

## Gates before any push
- `sh scripts/uom-dryrun.sh` → RESULT: PASS (0 FAIL).
- `git push` requires `UOM_ALLOW_PUSH=1` in uom-orch-state.sh (orchestrator path);
  direct CLI push is the operator's explicit choice.
- Prefer timestamped tag per milestone (e.g., `v0.31.0-<date>`).
