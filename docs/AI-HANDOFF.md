# Universal Omni-Master — Durable AI Handoff (v0.29.1)

## Repository Identity
- Project root: ~/src/universal-omni-master
- Core language: POSIX #!/bin/sh (BusyBox ash-safe)
- TUI language: Fish 4.x only (--no-config)
- Reference host: Alpine Linux 3.24 (musl, OpenRC)
- Secondary host: Void Linux (glibc, runit)
- Hardware: HP Pavilion 15-n010tx (degraded SATA cable, UDMA_CRC baseline 5360)
- Phone: Xiaomi Mi 8 / CrDroid Android 15 / Termux ARM64
- Active agent: laptop (latest heartbeat 13:27 IST)
- Phone heartbeat: 13:26 IST — dual-agent alive
- Current task: M02-state-sync (failed — retry pending)
- Takeover count: 1 (phone took over during laptop idle)

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
M30: Full Dual-Agent Loop Active — laptop primary, phone verification agent ← NEXT
M31: Network Switching Stress Test — hotspot ↔ LAN ↔ mDNS transitions
M32: Power-Failure Recovery Test — kill laptop, watch phone takeover, restore dual
M33–M42: Horizon tech (Post-Quantum, Predictive AI, eBPF, Edge, TEE, MCP, Federation)
M43–M50: Commercialization (Enterprise licensing, Omni-Cloud, AI Marketplace, FinOps)

**Immediate: Fix M02-state-sync — root cause unknown, likely path/opencode issue on phone**

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
  1. Reverse SSH tunnel (127.0.0.1:18022 — always works)
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
- **SSH:** Listening on port 22 + reverse tunnel 18022 ✓
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
- **Added M43-M50** commercialization phases: Enterprise Bundle, Omni-Cloud Managed, AI Agent Marketplace, Compliance Suite, FinOps Dashboard, MCP Gateway, Edge Federation, Omni-Genesis white-label
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

### 2026-07-17 13:00 — v0.29.0: Bootstrap + Solo Mode + Security Hardening

**Commits:** (v0.29.0 — see git log)
- **PHASE 1 — bin/uom-reverse-ssh.sh** rewritten with autossh, PID, logging, ssh fallback guard
- **PHASE 2 — install/bootstrap.sh** universal curl installer (auto-detects Termux/Alpine)
- **install/bootstrap-termux.sh** — full Termux/ARM64 bootstrap (Go build for opencode)
- **install/bootstrap-laptop.sh** — Alpine Linux bootstrap
- **PHASE 3 — orchestrators/uom-solo-orchestrator.sh** — phone-only fallback mode
- **orchestrators/uom-watchdog.sh** — laptop reachability monitor (60s loop, 3-fail threshold)
- **PHASE 4 — security/uom-harden-ssh.sh** — idempotent SSH hardening (laptop+phone)
- **security/uom-firewall.sh** — nftables ruleset (allow 22, 18022, drop rest)
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
1. Fix M02-state-sync (phone-side opencode PATH or permissions)
2. Verify reverse tunnel (31415) from both devices
3. Run `git pull --rebase` to catch up remote heartbeats
4. Continue M30: full dual-agent loop active (laptop primary, phone verify)
5. See docs/ROADMAP.md for full phase list

<!-- last-sync: 2026-07-17T08:00:00Z -->
