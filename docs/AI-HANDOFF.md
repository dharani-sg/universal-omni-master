# Universal Omni-Master — Durable AI Handoff (v0.31.0)

## Repository Identity
- Project root: ~/src/universal-omni-master
- Core language: POSIX #!/bin/sh (BusyBox ash-safe)
- TUI language: Fish 4.x only (--no-config)
- Reference host: Alpine Linux 3.24 (musl, OpenRC) on sda4
- Secondary host: Void Linux (glibc, runit, Btrfs) on sda3
- Hardware: HP Pavilion 15-n010tx (degraded SATA cable, UDMA_CRC baseline 5360)
- Phone: Xiaomi Mi 8 / CrDroid Android 15 / Termux ARM64 (192.168.40.207:8022)
- Active agent: laptop (current session)
- Phone heartbeat: watchdog running, tunnel UP — dual-agent alive
- Current task: L0 Dipper USB Gadget Bringup (NCM T1 tests)
- Model: opencode/big-pickle (pure cloud, no local LLM)
- AI arch: cloud-only — all generation via `opencode` stdin pipe, no ollama/sudo/binaries
- Takeover count: 1 (phone took over during laptop idle, previously resolved)

## Immutable Rules
1. POSIX sh only. Zero bashisms. Zero eval. Zero set --.
2. Mutation guard: exit 126 when OMNI_SYSROOT set.
3. Never push on failing gate. Never rewrite tags.
4. Commit messages with $/{}/backticks use git commit -F file.
5. All file writes verified with sh -n + wc -l + tail -3.
6. Security: secrets never in tracked files. Pre-commit hook blocks leaks.

## Sealed Milestones (M1-M26)
| Milestone | Tag | CLIs Added |
|---|---|---|
| M1-M6 | v0.1.0-v0.6.0 | detect, service, boot, gpu, storage, audit |
| M7-M12 | v0.7.2-v0.12.0 | deploy, healer, snapshot, tui |
| M13-M15 | v0.13.0-v0.15.0 | security, fleet (monolith, SSH, plugins) |
| M16-M20 | v0.16.0-v0.20.0 | state machine, adaptive UI, seed, manifests, livefeed |
| M21 | v0.21.0 | manager |
| M22 | v0.22.0 | (KVM testbed - library only) |
| M23-M23.1 | v0.23.0-v0.23.1 | saas |
| M24 | v0.24.1 | patcher (includes sentinel from M41) |
| M25 | v0.25.0 | compliance |
| M26 | v0.26.0 | openclaw |

Total: 17 CLI tools, 300+ automated assertions.

## Bug History (DO NOT REPEAT)
1. set -- clobbers $@ (M12)
2. BusyBox sed \n mismatch
3. BusyBox dmesg no -w
4. _OMNI_ROOT= strip orphans guard clauses
5. Over-broad awk . pattern
6. Top-level return 1 = exit 1 in monolith
7. Heredoc truncation (17 incidents)
8. Unquoted AGE(s) metacharacters
9. Pipe-subshell background job orphaning
10. grep -c || printf 0 double-capture
11. if "$handler"; then swallows exit code
12. $$ in single-quoted heredocs
13. mkfifo + & process leaks
14. stty size overrides $COLUMNS
15. /dev/null is not a regular file ([ -f ] fails)
16. Mock PATH=$MOCKDIR vs $MOCKDIR/bin
17. Python re.subn \1 backreference in replacement
18. BusyBox ash nested quote landmine (M24)

## Next Phase
M28: Dual-Agent Orchestration (laptop+phone) ✓
M29: Bootstrap Installer + Phone-Solo Mode + Security Hardening ✓
M30: Termux-Native Tools — omni-project-start menu + tmux watchdog + reverse tunnel fix ✓
M31: Network Switching Stress Test — hotspot ↔ LAN ↔ mDNS transitions ← NEXT
M32: Power-Failure Recovery Test — kill laptop, watch phone takeover, restore dual
M33–M42: Horizon tech (Post-Quantum, Predictive AI, eBPF, Edge, TEE, MCP, Federation)
M44–M51: Commercialization (Enterprise licensing, Omni-Cloud, AI Marketplace, FinOps)

**Immediate: M31 — Network switching stress test. Before that: update all .md docs for session resume context, sync to Void.**

---

## Chronological Session Log

### 2026-07-10: Milestones M1-M5
**Commits:** 1-11 (13:29 to 22:01 IST)
- M1: Detection core + sandbox + profile freeze + monolith bundler
- M2: Init system abstraction layer (5 backends + fixture testing)
- M3: Bootloader abstraction (GRUB + systemd-boot + EFI simulation)
- M4: GPU policy engine (AMD/NVIDIA/Intel hybrid abstraction)
- M5: Storage telemetry (SMART/NVMe/Btrfs/LUKS)

### 2026-07-11: Milestones M6-M13-A
**Commits:** 12-35 (08:45 to 23:27 IST)
- M6: Unified diagnostics + filesystem detection
- M7: Deploy/bootstrap installer + gate fixes
- M8: omni-healer self-healing watchdog daemon
- M9: Comparative audit vs chatbot-B reference
- M10: Btrfs snapshot lifecycle manager
- M11: Atomic rollback + boot-to-snapshot
- M12: Fish TUI gate v1 + POSIX shell trap fixes
- M13-A: Monolith bundler (inline all libs + 9 CLIs)
- M13-B: SSH remote transport for omni-deploy
- M13-C: Directory-based plugin ecosystem
- **First AI-HANDOFF.md created** (v0.12.0)

### 2026-07-12: Milestones M14-M21
**Commits:** 36-54 (07:07 to 23:13 IST)
- M14: Security hardening (TPM2-LUKS, UKI validation, SBAT)
- M15: Fleet orchestration + multi-node coordination
- M16: Heuristic State Machine for crash-resume
- M17: Adaptive TUI + Progressive Disclosure
- M18: Omni-Seed one-liner bootstrap
- M19: Declarative Manifests (Desired-State Configuration)
- M20: Live Telemetry Feed
- M21: Central Control Manager with module registry
- **Bug 13 (mkfifo) discovered and documented**

### 2026-07-13: Milestones M22-M26
**Commits:** 55-64 (07:44 to 22:07 IST)
- M22: Headless QEMU testbed with mock serial fallback
- M23: SaaS Metering + License Gateway + tier switching
- M24: AI-Patcher + heuristic auto-remediation + monolith fix
- M25: Fleet STIG/CIS Compliance
- M26: OpenClaw Commercial Telemetry Bridge
- **AI-HANDOFF.md v0.26.0** with full M1-M26 history

### 2026-07-14: Milestones M27
**Commits:** 65-71 (07:44 to 09:52 IST)
- M27: Universal desktop + window-manager profile engine
- M27.1: Desktop telemetry dashboard
- M27-B: Integrate omni-desktop into omni-deploy
- M27-C: Post-reboot DISPLAY_OK verification
- M27-C.1: Complete POSIX postboot dispatch integration
- **Tags:** v0.27.1 through v0.27.4

### 2026-07-16: Consolidation
**Commit:** 67c145c (15:36 IST)
- JSON escapers: 4 duplicates → 2 (canonical in core/utils.sh)
- Service-status: 3 duplicates → 1 (healer delegates)
- M41 (OpenCode Sentinel) merged into M24 (AI-Patcher)
- test-detect.sh fixture additions
- All files pass sh -n syntax check

---

### 2026-07-17: UOM Dual-Agent + GRUB Audit (Full Day)

#### 09:05 — GRUB Mode-600 Fix + SSH Enable + Dual-Boot
**Commit:** 0936baf
- **Root cause:** `GRUB_DISABLE_OS_PROBER=true` prevented Void Linux detection
- **Fix:** Set `GRUB_DISABLE_OS_PROBER=false`, ran `grub-mkconfig -o /boot/grub/grub.cfg`
- **Result:** Void Linux 7.2.0-rc3_1 now appears in GRUB menu
- **Main grub.cfg:** 8 entries (3 Alpine, 3 Void, submenu, UEFI Firmware)
- **Fallback grub.cfg:** 5 entries (Alpine only)
- **EFI stubs:** Alpine, Void, Artix, GRUB2NORD, alpine-fallback
- **omni-boot grub.sh hardening:** `_grub_cfg_readable()` and `_grub_cfg_cat()` with doas fallback for mode 600
- **Tests:** 47/47 pass (31 detect + 16 service-layer)
- **SSH:** sshd enabled on OpenRC default runlevel, started

#### 10:36 — GRUB Verify v5 + Sync-All Fix
**Commit:** a19e301 (v0.27.6)
- **grub-verify v5:** Copies mode-600 grub.cfg via `doas cp` before auditing
  - Added: duplicate `--id` check, entry parity, theme normalization
  - Removed: obsolete "kswarm NOT patched" warning → TUI dispatch check
- **grub-sync-all:** 3 doas-wrapped reads fixed (wc -l, grep -c, grep theme)
- **omni-master TUI:** `[s]` → grub-sync-all, `[u]` → `doas grub-mkconfig`
- **Theme normalization:** `($root)` prefix normalized via sed
- **Stale generators:** `41_void_custom` + `42_advanced_submenu` not executable (safe)
- **Final audit (100% clean):**
  - Main: 211 lines, fallback: 80 lines, both syntax valid
  - 2 menuentries each, tela theme consistent
  - 15/15 kernel/initrd files, 9/9 terminal_box PNGs present
  - No duplicate --id values, default alpine-top resolves
  - EFI chain: alpine-fallback/grubx64.efi + BOOT/BOOTX64.EFI present

#### 10:53 — Dual-Agent Phase 1: SSH Tunnel + Avahi + Phone Bootstrap
**Commits:** (uncommitted until 11:11)
- **Phone→laptop key** installed in laptop authorized_keys ✓
- **Reverse tunnel** verified: `ssh -F ~/.ssh/config uom-phone-rev` works ✓
- **uom-reverse-ssh.sh** patched (`/tmp/` → `$HOME/.uom-termux-user`)
- **Phone IP detected:** 192.168.40.207 (direct LAN)
- **Phase 2 laptop setup scripts read:**
  - `/etc/network/if-up.d/uom-announce` — installed (23 lines, executable)
  - `/etc/local.d/uom-announce.start` + `uom-resume.start` — created
  - `rc-update add local default` ✓
- **avahi-daemon:** enabled, started, mdns4_minimal in nsswitch ✓
- **SSH config:** 4 aliases (uom-phone-rev, uom-phone-hotspot, uom-phone-lan, uom-phone-mdns)

#### 11:11 — Heartbeat: Laptop IP Announce
**Commit:** 5e3b48c
- `.uom-agent/laptop.ip` written (192.168.40.90)
- `.uom-agent/phone.ip` written (192.168.40.207)
- Dual-agent state files created

#### 11:57 — Dynamic IP Discovery System
**Commit:** 1b12380
- **Problem:** All scripts had hardcoded IPs. Network switching required manual updates.
- **New file: `uom-ip-discover.sh`** — shared POSIX library with 6-method cascade:
  1. Reverse SSH tunnel (127.0.0.1:31415 — always works)
  2. mDNS (mi8.local / hp-pavilion.local)
  3. Last-known IP from `.uom-agent/*.ip`
  4. SSH config aliases
  5. Subnet scan (nmap port 8022/22)
  6. Gateway range scan (.100-.110)
- **Rewritten: `uom-net-detect.sh`** — pattern-based hotspot/lan/external/offline detection
- **Rewritten: `uom-orch-laptop.sh`** — uses `discover_phone_ip()`, dynamic SSH target
- **Rewritten: `uom-orch-phone.sh`** — uses `discover_laptop_ip()`, re-discovery on reconnect
- **Rewritten: `phone-bootstrap.sh`** — dynamic `_discover_laptop_ip()` (mDNS → scan → state)
- **Updated: `UOM-DUAL-AGENT-ORCHESTRATOR.md`** Phase 6 — 4 network scenarios
- **Updated: `AI-HANDOFF.md`** → v0.28.0

#### 12:09 — Duplicate File Cleanup
- `tools/` synced with current `UOM-DUAL-AGENT/` versions
- `setup/www/` tool scripts synced and tarball regenerated
- OLD versions purged, uom-ip-discover.sh added to both

#### 12:10 — Comprehensive Dry-Run Audit
- **GRUB:** All 6 themes verified (catppuccin-mocha, nord, stylish, tela, vimix, whitesur)
  - Each has theme.txt, background, icons (72-76), fonts, and complete asset sets
  - Current active: tela (confirmed in /etc/default/grub)
  - Switch command: edit GRUB_THEME in /etc/default/grub → `doas grub-mkconfig -o /boot/grub/grub.cfg`
- **Kernel:** Running 7.2.0-rc3_1, latest vmlinuz-7.2.0-rc3_1 (match) ✓
- **SSH:** Listening on port 22 + reverse tunnel 31415 ✓
- **All 5 orchestrator scripts pass `sh -n`** ✓
- **Hardcoded IP audit:** 0 in orchestrators, patterns only in detection scripts ✓
- **User cannot run doas from this shell** (no TTY) — all root operations need terminal

---

## GRUB Theme Quick Reference
| Theme | Files | Background | Icons | Font | Status |
|---|---|---|---|---|---|
| catppuccin-mocha | 8 | background.png | 73 | font.pf2 | ✓ |
| nord | 26 | background.jpg | 72 | dejavu_sans_12.pf2 | ✓ |
| stylish | 14 | background.jpg | 76 | terminus-12.pf2 | ✓ |
| **tela** (current) | 23 | background.jpg | 76 | terminus-12.pf2 | ✓ ACTIVE |
| vimix | 14 | background.jpg | 76 | terminus-12.pf2 | ✓ |
| whitesur | 23 | background.jpg | 76 | terminus-12.pf2 | ✓ |

### 2026-07-17 13:45 — v0.29.1: README Overhaul + M43-M50 Commercialization
**Commits:** (v0.29.1 — README rewrite)
- **READMe.md** complete overhaul: $2.6T AI market context (Gartner), Agentic Economy positioning, Hyperautomation 2.0, AI FinOps, Zero-Trust Bootstrap
- **Added M44-M51** commercialization phases: Enterprise Bundle, Omni-Cloud Managed, AI Agent Marketplace, Compliance Suite, FinOps Dashboard, MCP Gateway, Edge Federation, Omni-Genesis white-label
- **Randomized IPs/secrets** in docs (10.88.12.50/215, port 31415, fake API key examples)
- **Dual-agent arch diagram** updated with randomized IPs
- All doc sync timestamps updated to 2026-07-17T08:00:00Z
- Void sync: sda3 mounted, rsync completed

**Current state:**
- HEAD: ~v0.29.1 (README overhaul committed)
- Active agent: laptop (heartbeat 13:27), phone heartbeat 13:26
- Task M02-state-sync: failed — root cause unknown, likely phone-side opencode PATH issue
- Takeover count: 1 (phone solo mode triggered during laptop idle)
- All MD files synced, Void distro synced, git pushed

### 2026-07-17 13:40 — v0.29.2: Hybrid Orchestrator + Resume Command

**Commits:** (v0.29.2)
- **bin/uom-hybrid.sh** — Hybrid orchestrator: auto-starts reverse tunnel, detects laptop reachability, switches dual↔solo seamlessly. Runs in tmux session.
- **bin/uom-resume.sh** — Resume command: detects current state, checks tunnel, reports reachability, suggests next action. Run `sh bin/uom-resume.sh` on return.
- **AI-HANDOFF.md** — v0.29.2 session entry with resume instructions

### 2026-07-17 17:00-18:30 — v0.30.0: omni-project-start Menu + tmux Watchdog + Tunnel Fix

**Commit:** `5d72c0e` (feat: omni-project-start menu + tmux watchdog + tunnel fix)
**Tags:** v0.30.0

**New scripts:**
- **`bin/omni-project-start.sh`** (712 lines) — Interactive TUI dashboard with box-drawing menu. 9 sub-commands: detach, phone, laptop, hybrid, aware, tmux, opencode, test, recover. Shows real-time status dashboard (uptime, RAM, load, tunnel, tmux sessions, orchestrator PID, git status). Works on Alpine Linux AND Termux (auto-detects platform). Fish TUI for UI rendering, POSIX shell for business logic.
- **`bin/uom-tmux-watchdog.sh`** (303 lines) — Monitors `uom` and `uom-orch` tmux sessions. Auto-recreates crashed sessions. Restarts dead orchestrator/tunnel processes. Runs every 30s in `--daemon` mode, 60s in non-daemon. Clean PID management.
- **`install/setup-aliases.sh`** — Installs 14 UOM aliases into shell profile. Supports Alpine (`.profile`) and Termux (`.bashrc`). Idempotent (skips existing aliases).

**Tunnel fix (critical):**
- **Root cause:** OpenSSH 10.x on Alpine reports false positive "remote port forwarding failed" for `-R 31415:127.0.0.1:8022` when `GatewayPorts=no` on server. The forward actually WORKS despite the warning message, but `ExitOnForwardFailure=yes` was killing `autossh` on the false error.
- **Fix 1:** Removed `ExitOnForwardFailure=yes` from `bin/uom-reverse-ssh.sh` — autossh `GATETIME=0` now retries naturally until laptop frees the stale port (≤90s via ServerAliveInterval/CountMax).
- **Fix 2:** Removed `fuser -k 31415/tcp` from laptop-side tunnel cleanup — the fuser was killing the tunnel's own `sshd-session`, breaking the connection.
- **Result:** Tunnel is now stable. Port 31415 stays listening. `ssh uom-phone-rev "echo TUNNEL_OK"` passes consistently.

**Phone deployment:**
- **`bin/uom-deploy-phone.sh`** — Deploys all scripts to phone via SCP (SSH over LAN) + tunnel SCP (for when phone initiates). Smart kill patterns that don't kill own SSH session.
- Deployed scripts: `omni-project-start.sh`, `uom-tmux-watchdog.sh`, `uom-reverse-ssh.sh`, `uom-status.sh` (all sizes confirmed).
- Termux:Boot updated: starts SSH daemon, reverse tunnel, tmux watchdog, phone orchestrator on boot.
- Phone `.bashrc` aliases installed: all 14 UOM aliases.

**Current state (end of session):**
- HEAD: `4be3aec` (start: M30-termux-native [laptop])
- Tunnel: UP and stable
- Phone: watchdog running (PID confirmed), `uom` tmux session has 5 windows (orchestrator, opencode, monitor, laptop, status)
- Laptop: code pushed to GitHub (`5d72c0e`)
- Void: synced via `git reset --hard origin/main` from Alpine side — now at `4be3aec` (matching Alpine)

### 2026-07-17 13:00 — v0.29.0: Bootstrap + Solo Mode + Security Hardening

**Commits:** (v0.29.0 — see git log)
- **PHASE 1 — bin/uom-reverse-ssh.sh** rewritten with autossh, PID, logging, ssh fallback guard
- **PHASE 2 — install/bootstrap.sh** universal curl installer (auto-detects Termux/Alpine)
- **install/bootstrap-termux.sh** — full Termux/ARM64 bootstrap (Go build for opencode)
- **install/bootstrap-laptop.sh** — Alpine Linux bootstrap
- **PHASE 3 — orchestrators/uom-solo-orchestrator.sh** — phone-only fallback mode
- **orchestrators/uom-watchdog.sh** — laptop reachability monitor (60s loop, 3-fail threshold)
- **PHASE 4 — security/uom-harden-ssh.sh** — idempotent SSH hardening (laptop+phone)
- **security/uom-firewall.sh** — nftables ruleset (allow 22, 31415, drop rest)
- **security/install-hooks.sh** — pre-commit secret scanner
- **security/SECRETS.md** — secrets storage pattern
- **install/secrets.env.template** — committed template (keys blank)
- **.gitignore** — secrets patterns added
- **PHASE 5 — README.md** full rewrite with bootstrap curl, arch diagram, agent modes
- **docs/AI-HANDOFF.md** — v0.29.0 update with this entry
- **docs/ROADMAP.md** — phases 1-8 with status, milestone table
- **docs/PHONE-SETUP.md** — phone bootstrap, Termux:Boot, watchdog reference

**Current state:**
- HEAD: ~v0.29.0 (bootstrap+solo+security work committed)
- Reverse tunnel script: in repo at `bin/uom-reverse-ssh.sh`
- Bootstrap ready: single curl link auto-detects platform
- Security: SSH hardened, firewall ruleset, pre-commit guard installed
- Known issue: phone tunnel not up until phone runs bootstrap or reverse-ssh manually

---

### 2026-07-17 13:45 — M30 Bug Fixes + Dry-Run Hardening

**Session:** opencode (big-pickle) — dual-instance merge + implementation
**Dry-run:** 40 PASS, 0 FAIL (was 37 PASS, 2 FAIL, 4 WARN)

**Fixes applied:**
1. **uom-state-lib.sh:19** — `BASH_SOURCE[0]` → `$0` (POSIX compliance)
2. **uom-state-lib.sh:303-310** — compare-and-update recheck: removed incorrect mode comparison after filter changes it; now only verifies epoch increment
3. **bootstrap-termux.sh:18** — `SSHD_PORT=31415` → `8022` (correct phone sshd port); added `TUNNEL_PORT=31415` for reverse tunnel SSH config
4. **uom-orch-state.sh:82** — `git push` gated behind `UOM_ALLOW_PUSH=1`
5. **6 bin/ scripts** — bare `/tmp` writes replaced with `${STATE_FILE}.tmp.$$`, `mktemp`, or `${TMPDIR:-/tmp}` patterns
6. **uom-dryrun.sh:381** — `_init_dual()` now unsets `_UOM_STATE_LIB_LOADED` before re-sourcing (fixed state-machine test reading wrong fixture)

**New docs:**
- `docs/M30-MANUAL-RUNBOOK.md` — state machine operations, manual interventions, recovery procedures
- `docs/M30-SOURCE-VERIFICATION.md` — environment, port, POSIX, state library, and test suite verification

---

### 2026-07-17 19:00 — Dynamic Port/Host Guardian Sentinel (M30 follow-up)

**Session:** opencode (big-pickle) — dual-instance merge + implementation
**Dry-run:** 54 PASS, 0 FAIL (was 41 PASS, 0 FAIL)

**Problem addressed:**
- Android Termux constantly changes its **sshd port**; the laptop's **IP** changes
  because it hops between the phone's wireless hotspot and other WiFi sources.
- Static `Host` blocks in `~/.ssh/config` drift out of sync within minutes.

**New scripts:**
- **`tools/uom-port-watch.sh`** — read-only host/port discovery primitives
  (`uom_pw_my_ip`, `uom_pw_gateway`, `uom_pw_on_phone_hotspot`, `uom_pw_probe_ssh`,
  `uom_pw_discover_phone`, `uom_pw_discover_laptop`, `uom_pw_tunnel_up`,
  hint read/write). Zero bashisms, zero network mutation.
- **`bin/uom-port-guardian.sh`** — background **sentinel/guardian** service
  (`start|stop|status|once|dryrun|role|rewrite|--loop`). Every ~20s it:
  1. discovers the phone's live `host:port` (stored hint → known IPs → subnet scan),
  2. rewrites `~/.ssh/config` `uom-phone-rev`/`uom-phone-lan` (idempotent, atomic),
  3. publishes `.uom-agent/phone.host` + `.uom-agent/laptop.host` hints,
  4. touches `.uom-agent/runtime/portguard.drift` to signal the hybrid orchestrator,
  5. role-aware drift handling: phone restarts `uom-reverse-ssh.sh`; laptop keeps
     config + hints correct (phone owns the tunnel).

**Wiring:**
- `bin/uom-hybrid.sh` — added `_ensure_guardian` (auto-starts guardian) + `_check_drift`
  (reacts to the `portguard.drift` sentinel by re-running `_start_tunnel`).
- `install/bootstrap-termux.sh` — Termux:Boot now also launches
  `sh bin/uom-port-guardian.sh start` so the sentinel runs on phone boot.
- `scripts/uom-dryrun.sh` — added `test_port_guardian` (13 checks: syntax,
  primitives, role detection, idempotent ssh-config rewrite, boot wiring, hybrid wiring).
- `README.md` — replaced "Dynamic IP Handling" with "Dynamic IP + Port Handling
  (port-guardian sentinel)"; added guardian to CLI table + M30 deliverables row.

**Verified live:**
- Laptop on phone hotspot (`192.168.40.90`, gw `192.168.40.207`) — guardian detects
  `HOTSPOT` context, discovers phone at `192.168.40.207:8022`, rewrites ssh config,
  publishes hints. Guardian running (tmux `uom-hybrid-pg`, PID 1657). Hybrid running
  (PID 3074) in dual mode, tunnel DOWN (phone not running reverse-ssh this session).
- Dry-run: 54 PASS / 0 FAIL.

**Note on dual-boot (Void):** Only the Alpine rootfs (`/dev/sda4`) is mounted in this
environment; the Void Linux install is not currently accessible. The Void copy must be
synced on next Void boot via `git pull` (this commit is pushed to `origin/main`).

---

### 2026-07-18: Deep Phone Audit + Package Upgrade + QEMU Resolution

**Session:** opencode (big-pickle) via laptop SSH — 10-phase systematic audit
**Scope:** Full Termux host + Debian proot + QEMU VM audit and repair

#### Key Results
1. **Foreign PGP keys concern: UNFOUNDED** — system was already clean. No Arch/Alpine/Debian
   keys in Termux apt trust path. `pacman` is a legitimate Termux package (Termux-pacman fork).
2. **dpkg/apt state: CLEAN** on both Termux host and Debian proot — no broken packages, no
   stale locks, no interrupted installs.
3. **QEMU: FIXED** — previous "silent/no output" caused by missing `earlycon=pl011,mmio,0x09000000`
   kernel parameter, wrong serial device configs, and insufficient timeouts.
4. **Package upgrade: 114 packages updated** — openssh 10.3p1→10.4p1 killed sshd (manual restart
   required), all other packages upgraded cleanly.
5. **opencode: WORKING** on both Termux host (v1.2.13) and Debian proot (v1.18.3).
6. **Quarantine:** 9-byte corrupt opencode pkg + 111MB old opencode tarballs (114MB total freed).

#### Previous Session Failure Analysis
- Phone watchdog failures (M30-termux-native, M30-reverse-tunnel-auto): queue.json corruption
  (`jq: parse error`), opencode not yet installed, no working LLM pipeline on phone
- opencode install attempts: 5 different methods tried (curl installer, zip extraction, pacman -U,
  npm install opencode@latest [404], npm install opencode-ai [correct])
- QEMU previous verdict "needs PTY" was incorrect — real fix was earlycon parameter
- Tunnel port 18022 failures: old port reference, should be 31415

#### New Files
- `docs/SESSION-RESUME-2026-07-18.md` — Complete session resume with merged history
- Phone: `~/uom-repair/scripts/phone-opencode.sh` — opencode launcher
- Phone: `~/uom-repair/scripts/run-qemu-best.sh` — working QEMU command
- Phone: `~/uom-repair/README-phone-native.md` — quick reference

#### Bug #19 (New)
19. QEMU aarch64 serial silent without `earlycon=pl011,mmio,0x09000000` in kernel cmdline on
    Android/Termux host (PL011 UART requires earlycon for pre-ttyAMA0 output)

---

## Recovery Prompt
Read this file, then run:
  git status --short
  git log --oneline --decorate -10
  git tag --sort=-version:refname | head -20
  cat .uom-agent/state.json
  cat .uom-agent/queue.json
Report: branch, commit, tags, dirty files, latest milestone, active agent, current task, failing gates.
Never push unless all gates pass.

## Next Session Instructions
1. If returning from outside: `sh bin/uom-resume.sh` — detects state, suggests next action
2. OR use the new menu: `sh bin/omni-project-start.sh` — interactive dashboard with all commands
3. Attach to running orchestrator: `tmux attach -t uom` (if session exists)
4. If tunnel down: check `bin/uom-phone-boot.sh` on phone (Termux:Boot restarts on reboot)
5. **Port/host drift?** `sh bin/uom-port-guardian.sh status` — shows live phone/laptop
   target + tunnel; `sh bin/uom-port-guardian.sh start` if not running. The guardian
   auto-rewrites `~/.ssh/config` and signals the hybrid orchestrator on drift.
6. **Zen Loop reconciler:** `sh scripts/uom-reconcile.sh` — 6-step pipeline:
   preflight → tmux → cloud boot → tunnel → guardian → zen loop (generate → verify → reconcile).
   Run after any git pull to bring the environment up to date.
7. **Cloud-only generator:** `sh scripts/uom-generator.sh "your prompt here"` — uses
   `opencode --model opencode/deepseek-v4-flash-free` via stdin pipe. No sudo, no ollama.
8. Start M31: Network Switching Stress Test — hotspot ↔ LAN ↔ mDNS transitions (guardian
   should keep tunnel + ssh config correct automatically; verify 0 manual intervention)
9. See docs/ROADMAP.md for full phase list

## Resume Quick Reference
```sh
# Quick start (preferred):
sh bin/omni-project-start.sh    # Interactive menu with all options

# Or manual:
sh bin/uom-resume.sh            # Check state
tmux attach -t uom              # Attach to running orchestrator
cat .uom-agent/state.json       # Check current agent mode
git log --oneline -5            # Check latest work

# Full reconciler (6-step):
sh scripts/uom-reconcile.sh     # preflight -> tmux -> boot -> tunnel -> guardian -> zen

# Cloud code generation:
sh scripts/uom-generator.sh "..."   # opencode stdin pipe (pure cloud, no ollama)
sh scripts/uom-verifier.sh FILE     # syntax/policy verification

# Start tmux watchdog:
sh bin/uom-tmux-watchdog.sh --daemon  # Auto-recover sessions

# Deploy to phone:
sh bin/uom-deploy-phone.sh            # SCP scripts + aliases + boot config

# If phone was solo:
jq '.active_agent="laptop"' .uom-agent/state.json > "${TMPDIR:-/tmp}/uom-s.json" && mv "${TMPDIR:-/tmp}/uom-s.json" .uom-agent/state.json
git add -A && git commit -m "handback: laptop resumed control" && git push
```

<!-- last-handoff: 2026-07-24T12:00:00+05:30 - L0 Dipper USB Gadget phase -->
