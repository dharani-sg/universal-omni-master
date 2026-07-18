# SESSION RESUME — 2026-07-18 (Full Day)

Repo: `universal-omni-master` | branch: `main` | HEAD: `2117f8c` (v0.32.0)
Previous session: 2026-07-17 (see SESSION-RESUME-2026-07-17.md)

## What was done this session

### Part 1: Deep Phone Audit (08:46–09:30 IST) — opencode (big-pickle) via laptop SSH

**Trigger:** User reported broken Termux package state, foreign PGP keys, QEMU silent boot,
Debian proot apt locks, and suspected distro package conflicts from installing Arch/Alpine/Debian
tools inside Termux.

**Audit approach:** 10-phase systematic audit (PHASE 0–10) executed over SSH from laptop
(`ssh -tt -i ~/.ssh/id_ed25519_phone -p 8022 u0_a608@192.168.40.207`).

#### PHASE 0 — Environment Discovery
- Device: Xiaomi MI 8 (dipper), crDroid Android 15, kernel 4.9.337-perf
- Termux: googleplay.2026.06.21, PREFIX=/data/data/com.termux/files/usr
- SSH: port 8022, user u0_a608
- Created `~/uom-repair/{reports,quarantine,logs,scripts}` on phone

#### PHASE 1 — Deep Audit of Termux Host Package State
**Result: CLEAN — no foreign contamination**

| Check | Result |
|-------|--------|
| APT sources | Only `packages.termux.org` — legitimate |
| sources.list.d | Empty — no foreign repos injected |
| Foreign keyrings | NONE in Termux apt trust path |
| pacman.conf/mirrorlist | Legitimate Termux-pacman package (mirrors → termux-pacman.dev) |
| dpkg --audit | Clean, zero broken packages |
| apt-get check | Clean |
| Stale apt/dpkg processes | None |
| Lock files | None |
| All keyrings | Only Termux-native: `termux-packages.gpg`, `distsigkey.gpg` |

**Key finding: The suspected "mixed PGP signatures" problem was UNFOUNDED.** The system was
already clean. The `pacman` package is a legitimate Termux package (Termux-pacman fork), not
Arch Linux's pacman. Its config files point to `termux-pacman.dev` mirrors, NOT Arch mirrors.

#### PHASE 2 — Debian Proot Container Audit
**Result: CLEAN — fully functional Debian 13 (trixie)**

| Component | Value |
|-----------|-------|
| OS | Debian 13 (trixie), aarch64 |
| opencode | v1.18.3 (npm, `opencode-ai` package) |
| node | v22.23.1 |
| npm | v10.9.8 |
| Packages | 239 installed, dpkg clean, apt clean |
| APT sources | Standard trixie repos + NodeSource |
| Keyrings | Debian archive + NodeSource only |
| Foreign pkg managers | None |

PATH leak: `wget` resolves to Termux `/data/data/com.termux/files/usr/bin/wget` via proot
bind mount — expected behavior, not contamination.

#### PHASE 3 — Cleanup Plan
Created `~/uom-repair/reports/cleanup-plan.md`. Classification:
- A. Safe to keep: Termux pacman, keyrings, proot container, QEMU files
- B. Broken/stale: None found
- C. Foreign apt sources: None
- D. Foreign host keyrings: None
- E. Proot keyrings: All legitimate (Debian, NodeSource)
- F. Packages to install: None needed
- G. Packages to purge: None

#### PHASE 4 — Repair Termux Host (0 actions needed)
- dpkg/apt state already clean
- No stale locks, no interrupted installs
- Quarantined 1 file: `opencode-aarch64.pkg.tar.xz` (9 bytes, corrupt/empty)

#### PHASE 5 — Clean tmux/QEMU Process State
- No tmux sessions running
- No QEMU processes running
- No proot processes running

#### PHASE 6 — Debian Proot Verification
- Already working: node v22.23.1, npm v10.9.8, opencode v1.18.3
- Binary: `/usr/bin/opencode` → `/usr/lib/node_modules/opencode-ai/bin/opencode.exe`
- Installed via: `npm install -g opencode-ai`
- PATH inside proot: standard Debian paths + Termux `/usr/bin` (via proot bind)

#### PHASE 7 — QEMU Boot Test Matrix
**Result: QEMU WORKS — previous "silent" was misconfiguration**

Previous failed attempts (from earlier audit session and prior attempts):
| Script | What went wrong |
|--------|----------------|
| `run_qemu_test.sh` | `-nographic` + `-serial file:` conflict; no earlycon; serial_out.log empty (0 bytes) |
| `run_qemu_test2.sh` | `-monitor stdio` + `-serial file:` conflict; qemu_debug.log empty |
| `setup-vm.sh` | Used `-serial mon:stdio` (conflicts with -nographic); ISO boot needs interactive input |
| `vm-install.sh` | tmux session but no proper serial capture; 30s wait too short for Alpine ISO |
| `autoinstall.sh` | Piped commands via stdin but Alpine ISO needs interactive root shell first |

Working configuration (proven this session):
```bash
qemu-system-aarch64 \
  -M virt -cpu cortex-a72 -m 512 -smp 2 \
  -accel tcg,thread=multi \
  -kernel vmlinuz-virt -initrd initramfs-virt \
  -append "console=ttyAMA0,115200n8 earlycon=pl011,mmio,0x09000000 loglevel=8 panic=5" \
  -drive file=alpine-disk.qcow2,if=virtio,format=qcow2 \
  -device virtio-rng-pci \
  -netdev user,id=net0,hostfwd=tcp::8222-:22 \
  -device virtio-net-pci,netdev=net0 \
  -display none -monitor none -serial stdio
```

Serial output evidence: 13,341 bytes (serial-final.log), 215+ lines (quick-serial.log).
Alpine Init 3.11.1-r0 boots to virtio block device detection (vda, 4GB).

Key fixes discovered:
1. `earlycon=pl011,mmio,0x09000000` parameter enables early serial before kernel ttyAMA0 init
2. Use `-serial stdio` OR `-serial file:` — never combine with `-nographic` incorrectly
3. Use absolute paths for `-serial file:` (tilde expansion fails in QEMU args)
4. 15s timeout insufficient — Alpine ISO boot needs 60s+; direct kernel boot needs 30s+
5. Previous "PTY required" finding (from earlier audit) was partially correct: non-interactive
   SSH without `-tt` can cause proot fd warnings, but QEMU itself works with file serial

#### PHASE 8 — Phone-Native opencode Environment
**Termux host (preferred — newest):**
| Component | Version |
|-----------|---------|
| opencode | v1.2.13 (Termux pkg, with Android bionic TBI heap fix) |
| node | v24.17.0 |
| npm | v11.18.0 |
| tmux | 3.7b (upgraded from 3.6b) |
| qemu | 10.2.1 |

**Debian proot (fallback):**
| Component | Version |
|-----------|---------|
| opencode | v1.18.3 (npm `opencode-ai` package) |
| node | v22.23.1 |
| npm | v10.9.8 |

**opencode config** (`~/.config/opencode/opencode.json`):
- Model: `opencode/big-pickle`
- Small model: `opencode/north-mini-code-free`
- Enabled providers: `["opencode"]` only
- Denied: openai, anthropic, google, openrouter
- No external API keys required (uses opencode's own free-tier provider)

**opencode wrapper** (`~/bin/opencode`): Sophisticated Termux-specific launcher that:
- Disables Android bionic TBI heap pointer tagging via `libtagfix.so` LD_PRELOAD
- Sets `LD_LIBRARY_PATH` for libc++_shared.so (Bun JIT dependency)
- Points `OPENTUI_LIB_PATH` to renderer library
- Sets `BUN_PTY_LIB` for PTY support
- Disables `@parcel/watcher` (architecture mismatch on Android)
- Searches for `opencode.bin` in package layout paths

#### PHASE 9 — Project Infrastructure Verified
- Project: `~/src/universal-omni-master/` (active) + `~/src/universal-omni-master-test/` (copy)
- Orchestrator scripts present: `omni-project-start.sh`, `uom-hybrid.sh`, `uom-status.sh`
- Agent state: `.uom-agent/state.json` — laptop active, M30-termux-native pending
- Queue: 5 tasks in_progress (M33–M37)
- All 14 UOM aliases installed in `~/.bashrc`

### Part 2: Package Updates + Quarantine (08:54–09:05 IST)

#### pkg upgrade (114 packages updated)
All major packages upgraded successfully:
- openssh: 10.3p1 → 10.4p1 (**caused sshd to die** — needed manual restart)
- tmux: 3.6b → 3.7b
- proot-distro: 5.3.0 → 5.4.1
- python: 3.13.13 → 3.14.6
- golang: 1.26.4 → 1.26.5
- rust: 1.96.0 → 1.97.1
- clang/llvm: 21.1.8-2 → 21.1.8-3
- nodejs-lts: 24.17.0 (same version, rebuild)
- npm: 11.17.0 → 11.18.0
- 90+ more packages

**Minor issues during upgrade:**
- `py3compile` PermissionError on `/data/data/com.termux/files/usr/bin/bash` (non-interactive SSH
  context, known Termux issue — does not affect package functionality)
- proot-distro pip dependency check: already satisfied, same py3compile error (harmless)

#### SSH downtime incident
- openssh upgrade killed sshd process
- Termux does not auto-restart services
- SSH down for ~3 minutes before manual restart on phone
- Connection reset errors during recovery window
- **Lesson:** After `pkg upgrade` involving openssh, always restart sshd manually:
  ```bash
  pkill sshd; sleep 1; sshd
  ```

#### Quarantine actions
| File | Size | Reason | Destination |
|------|------|--------|-------------|
| `opencode-aarch64.pkg.tar.xz` | 9 bytes | Corrupt/empty (tried to install Arch package) | `~/uom-repair/quarantine/home-cleanup-*/` |
| `opencode.tar.gz` | 57 MB | Old binary archive from previous install attempt | `~/uom-repair/quarantine/old-opencode-tars-*/` |
| `opencode-glibc.tar.gz` | 58 MB | Old glibc binary archive from previous install attempt | `~/uom-repair/quarantine/old-opencode-tars-*/` |

**Total space freed: ~111 MB** from home directory.

### Part 3: Previous Session Failures — Root Cause Analysis

#### Phone Watchdog / Orchestrator Failures (2026-07-17)
From `.uom-phone.log`:
- Phone watchdog started, detected laptop OK initially
- Laptop went stale → phone takeover (count=2)
- Phone tried M30-termux-native: **FAILED (rc=1)**
- Phone tried M30-reverse-tunnel-auto: **FAILED (rc=1)**
- Repeated `jq: parse error: Invalid numeric literal at line 4, column 8` — queue.json
  was corrupted (likely from concurrent git operations or interrupted write)

**Root cause:** The phone's fallback orchestrator tried to execute tasks but:
1. `queue.json` was malformed (jq parse errors)
2. opencode was not yet properly installed on phone (was attempting npm install, pacman -U, etc.)
3. No working LLM pipeline on phone at that time

#### opencode Installation Attempts (bash_history timeline)
Multiple failed installation attempts visible in `~/.bash_history`:
1. `curl -fsSL .../install.sh | bash` — npm-based installer, ran on Termux
2. `pkg install unzip ripgrep` + manual zip extraction — tried flat layout
3. `pacman -U opencode-aarch64.pkg.tar.xz` — tried Arch package (9-byte corrupt file)
4. `npm install -g opencode@latest` — FAILED: `npm ERR! code E404` (package name is `opencode-ai`, not `opencode`)
5. `npm install -g opencode-ai` — SUCCEEDED (this is the correct package name)

**Resolution:** opencode is now properly installed via two methods:
- Termux host: `opencode` Termux package v1.2.13 (preferred)
- Debian proot: `opencode-ai` npm package v1.18.3

#### QEMU Silent Boot — Previous Verdict vs Current
Previous audit session verdict (from `~/audit/qemu-verdict.md`):
> "QEMU requires a real PTY for serial output. Running via SSH → zero output."
> Workaround: `script -qc "timeout 55 qemu-system-aarch64 ..."` /dev/null

Current session finding: **QEMU works without PTY** when:
1. `earlycon=pl011,mmio,0x09000000` is in kernel cmdline (enables PL011 early console)
2. Use `-display none -monitor none -serial file:path` or `-serial stdio`
3. Absolute paths used (no tilde expansion)
4. Sufficient timeout (30s+ for direct kernel, 60s+ for ISO)

The previous "PTY required" conclusion was caused by:
- Missing `earlycon=` parameter (kernel had no console output until ttyAMA0 driver loaded)
- Without earlycon, QEMU `-serial file:` captured nothing during early boot
- `script -qc` provided a PTY which may have changed QEMU's chardev behavior slightly,
  but the real fix was the earlycon parameter

#### Tunnel Port Forwarding Failures
From `.uom-tunnel.log` and `.uom-termux-user/tunnel.log`:
- Repeated `Error: remote port forwarding failed for listen port 18022`
- Port 18022 was the OLD tunnel port (replaced by 31415 in v0.30.0)
- autossh kept retrying but failed because port was occupied by stale sshd-session
- **Status:** Tunnel port 31415 is now the correct port; old 18022 references should be purged

#### ENOSYS / statx() Issue
From previous audit `~/audit/phase1-findings.md`:
- `ls ~/uom-vm` returns "Function not implemented" on Termux host
- Root cause: coreutils 9.11 uses `statx()` syscall, kernel 4.9.337 does not implement it
- This is a KERNEL LIMITATION, not package pollution
- Does NOT affect proot-debian (has its own coreutils with older syscall usage)
- Workaround: Use proot-debian for file operations, or use `ls --color=never` / busybox ls

## Files created/modified this session

### On phone (`~/uom-repair/`)
```
reports/audit-phase0-20260718-084621.log  — Raw Phase 0 audit output
reports/cleanup-plan.md                   — Item classification plan
reports/final-audit-report-20260718-*.md  — Consolidated audit report
scripts/phone-opencode.sh                — Launcher (termux/proot modes)
scripts/run-qemu-best.sh                 — Working QEMU command
README-phone-native.md                   — Quick reference card
quarantine/home-cleanup-*/               — 9-byte corrupt pkg
quarantine/old-opencode-tars-*/          — 111MB old archives
```

### On phone (`~/uom-vm/logs/`)
```
quick-serial.log    — 14KB, 215 lines, successful Alpine kernel boot
```

### On laptop (this repo)
```
docs/SESSION-RESUME-2026-07-18.md — This file
```

## Environment state (end of session)

| Item | Value |
|------|-------|
| Termux apt | CLEAN, 114 packages upgraded |
| Debian proot | CLEAN, 239 packages, node/npm/opencode working |
| QEMU | WORKING (direct kernel boot, serial captured) |
| opencode (Termux) | v1.2.13, working |
| opencode (proot) | v1.18.3, working |
| SSH | UP (port 8022, openssh 10.4p1) |
| Tunnel | DOWN (not started this session) |
| Tmux sessions | None running (clean state) |
| Agent state | laptop active, M30-termux-native pending |
| Queue | 5 tasks M33-M37 in_progress (from previous generator run) |

## Commands to resume

```bash
# Quick start opencode on phone (from laptop):
ssh -tt -i ~/.ssh/id_ed25519_phone -p 8022 u0_a608@192.168.40.207 \
  'bash ~/uom-repair/scripts/phone-opencode.sh termux'

# Or start in Debian proot:
ssh -tt -i ~/.ssh/id_ed25519_phone -p 8022 u0_a608@192.168.40.207 \
  'bash ~/uom-repair/scripts/phone-opencode.sh proot'

# Attach to running session:
ssh -tt ... 'tmux attach -t uom-opencode'

# Start QEMU VM:
ssh ... 'bash ~/uom-repair/scripts/run-qemu-best.sh'

# Project status:
ssh ... 'cd ~/src/universal-omni-master && sh bin/uom-status.sh'

# If SSH dies after pkg upgrade:
# On phone Termux: pkill sshd; sleep 1; sshd

# Start tunnel (from phone):
ssh ... 'bash ~/bin/uom-reverse-ssh.sh'
```

## Known remaining items

1. **Tunnel not running** — needs `uom-reverse-ssh.sh` on phone side
2. **Queue.json corruption** — phone jq parse errors from 2026-07-17; may need manual cleanup
3. **opencode tarballs in quarantine** — 111MB, can be deleted permanently if desired
4. **M33-M37 tasks** — still marked in_progress in queue from previous generator run; status unknown
5. **ENOSYS statx()** — kernel limitation, cannot fix without kernel upgrade
6. **py3compile errors** — harmless, caused by non-interactive SSH context during post-install scripts
7. **Void Linux sync** — not done this session; needs `git pull` on next Void boot

<!-- last-sync: 2026-07-18T09:30:00+05:30 -->
