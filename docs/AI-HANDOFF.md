# Universal Omni-Master — Durable AI Handoff (v0.28.0)

## Repository Identity
- Project root: ~/src/universal-omni-master
- Core language: POSIX #!/bin/sh (BusyBox ash-safe)
- TUI language: Fish 4.x only (--no-config)
- Reference host: Alpine Linux 3.24 (musl, OpenRC)
- Secondary host: Void Linux (glibc, runit)
- Hardware: HP Pavilion 15-n010tx (degraded SATA cable, UDMA_CRC baseline 5360)

## Immutable Rules
1. POSIX sh only. Zero bashisms. Zero eval. Zero set --.
2. Mutation guard: exit 126 when OMNI_SYSROOT set.
3. Never push on failing gate. Never rewrite tags.
4. Commit messages with $/{}/backticks use git commit -F file.
5. All file writes verified with sh -n + wc -l + tail -3.

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

## Next Phase
M27: Termux Native Polish (haptic feedback, push notifications, portrait optimization)
M28+: Zero-trust networking, predictive healing, fleet AI orchestration

## Session Log: UOM Dual-Agent Dynamic IP System (2026-07-17)
### Problem
All orchestrator scripts had hardcoded IPs (`192.168.40.90`, `192.168.43.1`, `192.168.40.207`). Network switching (hotspot → external WiFi → hotspot) required manual IP updates.

### Solution: Dynamic IP Discovery System
Created 3 new files + rewrote 3 existing files:

**New files:**
- `tools/uom-ip-discover.sh` — Shared POSIX library with 6-method discovery cascade:
  1. Reverse SSH tunnel (`127.0.0.1:18022` — always works if tunnel is up)
  2. mDNS resolution (`mi8.local` / `hp-pavilion.local`)
  3. Last-known IP from `.uom-agent/*.ip` state files
  4. SSH config aliases
  5. Subnet scan (nmap for port 8022/22)
  6. Gateway range scan (phone hotspot `.100-.110`)
- `tools/uom-net-detect.sh` — Network mode detection (hotspot/lan/external/offline) with dynamic phone/laptop IP discovery

**Rewritten files:**
- `tools/uom-orch-laptop.sh` — Uses `uom-ip-discover.sh`, dynamic `_phone_ssh_cmd()` function
- `tools/uom-orch-phone.sh` — Uses `uom-ip-discover.sh`, dynamic `_laptop_ssh_cmd()`, `_laptop_reachable()`
- `setup/phone-bootstrap.sh` — Dynamic `_discover_laptop_ip()` (mDNS → gateway scan → state file → subnet scan)
- `UOM-DUAL-AGENT-ORCHESTRATOR.md` — Phase 6 rewritten with discovery architecture + 4 network scenarios

### Key Architecture Decisions
- Reverse SSH tunnel is PRIMARY communication path (works regardless of IP changes)
- `uom-reverse-ssh.sh` re-discovers laptop on every reconnect cycle
- Phone hotspot gateway detection uses pattern matching (not hardcoded IPs)
- All remaining `192.168.43.1` references are pattern matches or fallback defaults (acceptable)
- Laptop SSH config retains static aliases (`uom-phone-hotspot`, `uom-phone-lan`) as secondary options

### OpenCode on Phone
- npm install failed (android/arm64 excluded from package)
- `opencode.ai/install` script also failed (no ARM64 binary)
- Go not available in Termux packages (`pkg search golang` empty)
- **Status:** BLOCKED — needs Go source build or alternative AI agent
- **Fallback documented:** `pkg install golang && go install github.com/opencode-ai/opencode@latest`

### Verification
- All 6 scripts pass `sh -n` syntax check ✓
- Hardcoded IP audit: orchestrators = 0 hardcoded IPs, detection scripts = pattern matches only ✓
- SSH tunnel connectivity verified: `ssh -F ~/.ssh/config uom-phone-rev echo ok` ✓

## Consolidation Log (2026-07-16)
- M41 (OpenCode Sentinel) merged into M24 (AI-Patcher) — sentinel is now a feature, not standalone
- JSON escapers: 4 duplicates → 2 (canonical in core/utils.sh + postboot variant)
- Service-status: 3 duplicates → 1 (canonical via init modules, healer delegates)
- All files pass sh -n syntax check

## Session Log: Dual-Boot GRUB + SSH Fix (2026-07-17)
### GRUB Dual-Boot Detection
- **Root cause:** `GRUB_DISABLE_OS_PROBER=true` in /etc/default/grub prevented Void Linux detection
- **Fix:** Set `GRUB_DISABLE_OS_PROBER=false`, ran `grub-mkconfig -o /boot/grub/grub.cfg`
- **Result:** Void Linux 7.2.0-rc3_1 now appears in GRUB menu (id: void-top)
- **Main grub.cfg entries:** 8 total (3 Alpine, 3 Void, submenu, UEFI Firmware)
- **Fallback grub.cfg:** 5 entries (Alpine only, pre-os-prober — needs root to regenerate)
- **EFI stubs:** Alpine, Void, Artix, GRUB2NORD, alpine-fallback all present in /boot/efi/EFI/

### omni-boot grub.sh Hardening
- **Issue:** grub.cfg mode 600 (root-only) caused `[error] grub.cfg not found` in omni-boot
- **Fix:** Added `_grub_cfg_readable()` and `_grub_cfg_cat()` — detects doas/sudo, reads via privilege helper
- **Pattern:** Same as grub-theme.fish (Fish) — direct read first, doas fallback for mode 600
- **Tests:** 47/47 pass (31 detect + 16 service-layer)

### SSH Service
- **Status:** sshd enabled on OpenRC default runlevel, service started
- **Host keys:** RSA, ECDSA, ED25519 all present in /etc/ssh/

### GRUB Theme Config
- **Fixed:** omni_conf.fish GRUB_THEME_DIR corrected from whitesur → tela (matching active theme)
- **Fallback grub.cfg:** Theme=tela (consistent with main)
- **Available themes:** catppuccin-mocha, nord, stylish, tela, vimix, whitesur

### Dual-Distro Dry Run Results
- **Alpine (native):** distro=alpine, init=openrc, libc=musl, pkg=apk, priv=doas, boot=grub, UEFI=yes, SB=disabled
- **Void (sysroot):** distro=void, init=runit, libc=glibc, pkg=xbps, priv=doas, boot=grub, seat=seatd+elogind
- **Hardware:** Intel i3-3217U, AMD+Intel hybrid GPU, CT240BX500 SSD, AC power

### Pending (requires root)
- Regenerate fallback grub.cfg to include Void Linux entries: `doas grub-mkconfig -o /boot/grub/grub.cfg`
- Verify fallback sync: `grub-theme verify` (Fish alias)

### GRUB Verify v5 + Sync-All Fix (2026-07-17 continued)
- **Root cause:** `/boot/grub/grub.cfg` mode 600 (root:root) caused all verify/sync scripts to fail when run as user `alpine`
- **grub-verify v5:** Copies mode-600 main grub.cfg to temp via `doas cp` before auditing
  - Added: duplicate `--id` check, entry parity (main vs fallback), theme `($root)` normalization
  - Removed: obsolete "kswarm NOT patched" warning → replaced with TUI dispatch check
- **grub-sync-all:** 3 doas-wrapped reads fixed (lines 283, 313, 321 — `wc -l`, `grep -c`, `grep theme`)
- **omni-master TUI dispatch:** `[s] Grub-Sync` → `/usr/local/bin/grub-sync-all`, `[u] Grub-Update` → `doas grub-mkconfig -o /boot/grub/grub.cfg`
- **Theme normalization:** `set theme=($root)/boot/grub/themes/tela/theme.txt` (main) vs `set theme="/boot/grub/themes/tela/theme.txt"` (fallback) — now normalized via `sed 's/[(][^)]*[)]//'` before comparison
- **Stale generators:** `41_void_custom` + `42_advanced_submenu` not executable — safe, entries ignored by grub-mkconfig
  - 41_void_custom refs: vmlinuz-7.2.0-rc1_1, vmlinuz-6.18.37_1 (stale)
  - 42_advanced_submenu refs: vmlinuz-7.2.0-rc1, vmlinuz-7.2.0-rc1_1, vmlinuz-6.18.37_1 (stale)
  - Actual Void: vmlinuz-7.2.0-rc3_1, 7.2.0-rc2_1, 6.18.38_1 (correct in main grub.cfg via 10_kswarm)
- **Final audit (100% clean):**
  - Main: 211 lines, syntax valid, 2 menuentries + 1 submenu
  - Fallback: 80 lines, syntax valid, 2 menuentries + 1 submenu
  - Entry parity: main=2 fallback=2
  - 15/15 kernel/initrd files present
  - All 9 terminal_box PNGs present
  - Theme: tela (consistent)
  - No duplicate --id values
  - Default: alpine-top (resolves)
  - EFI chain: alpine-fallback/grubx64.efi + BOOT/BOOTX64.EFI present

## Recovery Prompt
Read this file, then run:
  git status --short
  git log --oneline --decorate -10
  git tag --sort=-version:refname | head -20
Report: branch, commit, tags, dirty files, latest milestone, failing gates.
Never push unless all gates pass.
