# AUDIT REPORT — 2026-07-18 (POWER-CUT RESUME)

**Branch:** `refactor/structure-audit-2026-07-17`
**Laptop HEAD:** `bbee660ecf350a9a050418d20be7c1ad36cfb043` (refactor commit)
**Phone HEAD:** same (matching three-way SHA)
**Guest HEAD:** same (matching three-way SHA)
**Tag:** `uom-phone-qemu-phase9-20260718` (on `ebe18b6`, BEFORE refactor)
**Auditor:** opencode (automated, Step 0 of power-cut resume)

---

## 0. POWER-CUT RESUME STATUS

The previous session completed a refactor commit `bbee660` but was interrupted by power loss before the final report sync. Key finding: **the refactor commit already landed** but was never verified end-to-end post-commit.

### What changed between `ebe18b6` (phase9 tag) and `bbee660` (HEAD):
- Created `scripts/uom-lib.sh` (tracked, 280 lines)
- Created `scripts/uom-qemu-watchdog.sh` (tracked, 184 lines)
- Updated `scripts/phone-shortcuts/uom-widget-lib.sh` → wrapper sourcing `uom-lib.sh`
- Updated all widget scripts with standardised headers
- Updated `scripts/uom-phone-bootstrap.sh` with doctor/verify
- `bin/uom-qemu-phone` is now tracked (was UNTRACKED in previous audit)
- Claims: "Dry-run T1-T10: 10/10 PASS, Watchdog simulation: 9/10"
- **BUT: No audit report was written for the refactor commit. This is it.**

### Phone-side deployment status:
- Phone `~/bin/uom-lib.sh`: 11,131 bytes, Jul 18 16:14 — **DEPLOYED** (repo: 280 lines)
- Phone `~/bin/uom-qemu-watchdog.sh`: 9,425 bytes, Jul 18 16:25 — **DEPLOYED**
- Phone `~/bin/uom-qemu-phone`: 14,476 bytes, Jul 18 15:52 — **DEPLOYED** (repo: 423 lines, smaller)
- Phone `~/bin/uom-widget-lib.sh`: 2,118 bytes, Jul 18 16:14 — **DEPLOYED**
- Phone `~/.shortcuts/*`: All 7 widget scripts deployed (Jul 18 16:18)
- **DISCREPANCY:** Phone launcher is 14,476 bytes vs repo 423 lines. Phone version has additional code not in repo.

### Critical: Phone `uom-qemu-phone` version mismatch
Phone deployed version is ~14KB. Repo version is ~423 lines (~10KB). The phone version likely has extra logic (possibly from `uom-final-fix.sh` merge or inline additions). **This must be reconciled.**

---

## 1. COMPLETE FILE INVENTORY

### 1A. Laptop Repo — Tracked Files

**Total tracked files:** 336 (git ls-files)
**Branch:** `refactor/structure-audit-2026-07-17`
**Untracked files:** NONE (clean working tree)
**Stash:** NONE

#### `bin/` — CLI entry points (30 files)

| File | Purpose | Status |
|------|---------|--------|
| `bin/uom-qemu-phone` | QEMU launcher v2.1 | **TRACKED** — COMPLETE |
| `bin/uom-sync` | Git sync tool | COMPLETE |
| `bin/uom-sync-status` | Sync status display | COMPLETE |
| `bin/uom-status.sh` | Hybrid status check | PARTIAL — refs orchestrator logs |
| `bin/uom-deploy-phone.sh` | Phone deployment | PARTIAL — hardcodes IPs |
| `bin/uom-phone-provision.sh` | Phone provisioning | PARTIAL |
| `bin/uom-reverse-ssh.sh` | Reverse SSH tunnel | COMPLETE |
| `bin/uom-resume.sh` | Session resume | PARTIAL |
| `bin/uom-fix-connectivity.sh` | Connectivity repair | PARTIAL — hardcodes IPs |
| `bin/uom-statectl.sh` | State control | PARTIAL |
| `bin/uom-port-guardian.sh` | Port guardian | WRAPPER → `orchestrators/` |
| `bin/uom-hybrid.sh` | Hybrid orchestrator | WRAPPER → `orchestrators/` |
| `bin/uom-tmux-watchdog.sh` | Tmux watchdog | WRAPPER → `orchestrators/` |
| `bin/uom-tmux-guardian.sh` | Tmux guardian | PARTIAL |
| `bin/omni-project-start.sh` | Project start menu | PARTIAL — hardcodes IPs |
| `bin/omni-audit` | Audit CLI | COMPLETE |
| `bin/omni-boot` | Boot CLI | COMPLETE |
| `bin/omni-compliance` | Compliance CLI | COMPLETE |
| `bin/omni-deploy` | Deploy CLI | COMPLETE |
| `bin/omni-desktop` | Desktop CLI | COMPLETE |
| `bin/omni-detect` | Detect CLI | COMPLETE |
| `bin/omni-fleet` | Fleet CLI | COMPLETE |
| `bin/omni-gpu` | GPU CLI | COMPLETE |
| `bin/omni-healer` | Healer CLI | COMPLETE |
| `bin/omni-manager` | Manager CLI | COMPLETE |
| `bin/omni-manifest` | Manifest CLI | COMPLETE |
| `bin/omni-openclaw` | OpenClaw CLI | COMPLETE |
| `bin/omni-patcher` | Patcher CLI | COMPLETE |
| `bin/omni-saas` | SaaS CLI | COMPLETE |
| `bin/omni-security` | Security CLI | COMPLETE |
| `bin/omni-service` | Service CLI | COMPLETE |
| `bin/omni-snapshot` | Snapshot CLI | COMPLETE |
| `bin/omni-storage` | Storage CLI | COMPLETE |
| `bin/omni-tui` | TUI CLI | COMPLETE |

#### `scripts/` — Phone-specific + test scripts (44 files)

| File | Purpose | Status |
|------|---------|--------|
| `scripts/uom-lib.sh` | **Consolidated shared library** | COMPLETE — 280 lines, tracked |
| `scripts/uom-qemu-watchdog.sh` | QEMU health watchdog P1-P10 | COMPLETE — 184 lines, tracked |
| `scripts/uom-phone-bootstrap.sh` | One-shot bootstrap | PARTIAL — doctor/install done, verify partial |
| `scripts/uom-phone-bootstrap.sh.sha256` | Bootstrap checksum | COMPLETE |
| `scripts/uom-widget-lib.sh` | Widget backward-compat wrapper | COMPLETE — wrapper only |
| `scripts/uom-dryrun.sh` | Dry-run test suite | COMPLETE |
| `scripts/uom-generator.sh` | Zen Loop generator agent | COMPLETE |
| `scripts/uom-verifier.sh` | Zen Loop verifier agent | COMPLETE |
| `scripts/uom-reconcile.sh` | Reconcile (wrapper) | WRAPPER → `orchestrators/` |
| `scripts/uom-sync.sh` | Sync script | PARTIAL — hardcodes IPs |
| `scripts/uom-llm-remote.sh` | Remote LLM via SSH | PARTIAL — hardcodes IPs |
| `scripts/uom-final-fix.sh` | Final fix script | PARTIAL — has inline watchdog |
| `scripts/uom-proot-setup.sh` | proot setup | COMPLETE |
| `scripts/phone-shortcuts/00-UOM-Status` | Status widget | COMPLETE — standardised header |
| `scripts/phone-shortcuts/20-UOM-Guest-Shell` | SSH widget | COMPLETE |
| `scripts/phone-shortcuts/30-UOM-Zen-Console` | Zen console widget | COMPLETE |
| `scripts/phone-shortcuts/40-UOM-Host-Console` | Host console widget | **PARTIAL — does NOT source uom-lib.sh** |
| `scripts/phone-shortcuts/50-UOM-Logs` | Logs widget | COMPLETE |
| `scripts/phone-shortcuts/90-UOM-Stop` | Stop widget | COMPLETE |
| `scripts/phone-shortcuts/tasks/10-UOM-Start` | Start task | COMPLETE |
| `scripts/phone-shortcuts/PHONE-APP-ACTION-REQUIRED.md` | User instructions | COMPLETE |
| `scripts/phone-shortcuts/opencode-zen-smart` | Zen wrapper | NOT_IN_REPO (only in guest) |
| `scripts/audit-m11.sh` | M11 audit test | COMPLETE |
| `scripts/test-*.sh` | Test scripts (25 files) | COMPLETE |

#### `tools/` — Shared tooling (7 files)

| File | Purpose | Status |
|------|---------|--------|
| `tools/uom-orch-laptop.sh` | Laptop orchestrator | COMPLETE |
| `tools/uom-orch-phone.sh` | Phone orchestrator/watchdog | COMPLETE |
| `tools/uom-orch-state.sh` | Shared state functions | COMPLETE |
| `tools/uom-state-lib.sh` | State library | COMPLETE |
| `tools/uom-ip-discover.sh` | IP discovery | COMPLETE |
| `tools/uom-net-detect.sh` | Network detection | COMPLETE |
| `tools/uom-port-watch.sh` | Port watcher | COMPLETE |

#### `orchestrators/` — Orchestrator variants (6 files)

| File | Purpose | Status |
|------|---------|--------|
| `orchestrators/uom-solo-orchestrator.sh` | Solo orchestrator | COMPLETE |
| `orchestrators/uom-watchdog.sh` | Laptop reachability watchdog | DIFFERENT from QEMU watchdog |
| `orchestrators/uom-tmux-watchdog.sh` | Tmux session watchdog | DIFFERENT from QEMU watchdog |
| `orchestrators/uom-port-guardian.sh` | Port guardian | COMPLETE |
| `orchestrators/uom-reconcile.sh` | Reconcile | COMPLETE |
| `orchestrators/uom-hybrid.sh` | Hybrid orchestrator | DUPLICATE — should be deleted |

#### `UOM-DUAL-AGENT/` — Legacy dual-agent setup (16 files)

| File | Purpose | Status |
|------|---------|--------|
| `UOM-DUAL-AGENT/*.sh` | IP discover, net detect, orch scripts | OBSOLETE — duplicates `tools/` |
| `UOM-DUAL-AGENT/setup/*` | Bootstrap scripts | OBSOLETE — duplicates `install/` |
| `UOM-DUAL-AGENT/setup/www/*` | Web-served bootstrap | OBSOLETE |
| `UOM-DUAL-AGENT/UOM-DUAL-AGENT-ORCHESTRATOR.md` | Design doc | KEEP for reference |

#### `docs/` — Documentation (18 files)

| File | Purpose | Status |
|------|---------|--------|
| `docs/PHONE-ONLY-OPERATIONS.md` | Phone-only ops guide | COMPLETE |
| `docs/ANDROID-13-PLUS-QEMU.md` | Android QEMU guide | COMPLETE |
| `docs/NEW-LAPTOP-RECOVERY.md` | Laptop recovery | COMPLETE |
| `docs/GIT-SYNC-AND-RECOVERY.md` | Git sync guide | COMPLETE |
| `docs/SECURITY-BOUNDARIES.md` | Security boundaries | COMPLETE |
| `docs/SYNC-ARCHITECTURE.md` | Sync architecture | COMPLETE |
| `docs/OPENCODE-LAPTOP-QEMU-PARITY.md` | Parity doc | COMPLETE |
| `docs/NETWORK-DRIFT.md` | Network drift doc | COMPLETE |
| `docs/CONCURRENCY.md` | Concurrency doc | COMPLETE |
| `docs/ZEN-LOOP.md` | Zen Loop doc | COMPLETE |
| `docs/AI-HANDOFF.md` | AI handoff doc | COMPLETE |
| `docs/ROADMAP.md` | Project roadmap | PARTIAL — stale M30 refs |
| `docs/SESSION-RESUME-2026-07-18.md` | Session resume | CURRENT |
| `docs/M30-MANUAL-RUNBOOK.md` | M30 runbook | COMPLETE |
| `docs/M30-SOURCE-VERIFICATION.md` | M30 source verification | COMPLETE |
| `docs/SCRIPT-CATALOG.md` | Script catalog | STALE — missing phone scripts |
| `docs/PHONE-SETUP.md` | Phone setup | STALE — superseded by bootstrap |
| `docs/AUDIT-REPORT-20260718.md` | This audit report | CURRENT |

#### `config/` — Configuration (4 files)

| File | Purpose | Status |
|------|---------|--------|
| `config/phone/opencode.json` | OpenCode config template | COMPLETE |
| `config/uom/zen.env.example` | Zen config template | COMPLETE |
| `config/omni-snapshot.conf.example` | Snapshot config | COMPLETE |
| `config/profiles/hp-pavilion-n010tx.toml` | Laptop profile | IRRELEVANT to phone |

**MISSING:** `config/uom/runtime.env.example` — not created yet (Step 3)

#### Other tracked directories

| Directory | Files | Status |
|-----------|-------|--------|
| `src/` | ~130 files | COMPLETE — core UOM library |
| `sandbox/` | ~80 files | COMPLETE — test fixtures |
| `security/` | 4 files | COMPLETE |
| `install/` | 5 files | PARTIAL — `bootstrap-termux.sh` duplicates bootstrap |
| `.uom-agent/` | ~15 files | STALE — M30 pending, M33-M37 pending |

### 1B. Phone-side Files

**Phone:** Xiaomi Mi 8, crDroid Android 15, Termux Google Play
**SSH:** u0_a608@192.168.40.207:8022

#### `~/bin/` (17 files)

| File | Purpose | Status |
|------|---------|--------|
| `uom-qemu-phone` | Launcher v2.1+ | DEPLOYED — 14,476 bytes (repo: ~10KB — **MISMATCH**) |
| `uom-lib.sh` | Consolidated shared lib | DEPLOYED — 11,131 bytes |
| `uom-widget-lib.sh` | Widget wrapper | DEPLOYED — 2,118 bytes |
| `uom-qemu-watchdog.sh` | QEMU health watchdog | DEPLOYED — 9,425 bytes |
| `uom-phone-bootstrap.sh` | Bootstrap script | DEPLOYED — 12,656 bytes |
| `uom-reverse-ssh.sh` | Reverse SSH | DEPLOYED |
| `uom-status.sh` | Status script | DEPLOYED — DUPLICATE |
| `uom-tmux-watchdog.sh` | Tmux watchdog | DEPLOYED — from orchestrators/ |
| `uom-install-alpine.sh` | Alpine installer | DEPLOYED — PARTIAL |
| `uom-session.sh` | Session helper | DEPLOYED — PARTIAL |
| `opencode-musl` | OpenCode binary (173MB) | DEPLOYED — CORRECT |
| `omni-project-start.sh` | Project start | DEPLOYED |
| `dryrun-test.sh` | Dry-run test | DEPLOYED — TEMPORARY |
| `watchdog-sim.sh` | Watchdog simulation | DEPLOYED — TEMPORARY |

**Note:** Previous audit listed `opencode-v17`, `opencode-v18`, `opencode.broken.*`, `ssh-alpine.sh` as obsolete. They appear to have been deleted already (not in current listing).

#### `~/.shortcuts/` (7 widgets + 1 task + 1 doc)

| File | Purpose | Status |
|------|---------|--------|
| `00-UOM-Status` | Status widget | DEPLOYED — syntax OK |
| `20-UOM-Guest-Shell` | SSH widget | DEPLOYED — syntax OK |
| `30-UOM-Zen-Console` | Zen console | DEPLOYED — syntax OK |
| `40-UOM-Host-Console` | Host console | DEPLOYED — **does NOT source uom-lib.sh** |
| `50-UOM-Logs` | Logs widget | DEPLOYED — syntax OK |
| `90-UOM-Stop` | Stop widget | DEPLOYED — syntax OK |
| `tasks/10-UOM-Start` | Start task | DEPLOYED — syntax OK |
| `PHONE-APP-ACTION-REQUIRED.md` | User instructions | DEPLOYED |

**Previous audit listed `Alpine SSH.sh` as OBSOLETE.** Not present anymore — deleted.

#### `~/uom-vm/` — VM directory

| File | Purpose | Status |
|------|---------|--------|
| `images/uom-phone.qcow2` | VM disk | PRESENT |
| `edk2-aarch64-code.fd` | EFI firmware code (64MB) | PRESENT |
| `edk2-aarch64-vars.fd` | EFI firmware vars (64MB) | PRESENT |
| `uom-efi-vars.fd` | Writable EFI vars copy (64MB) | PRESENT |
| `uom-phone-vars.fd` | Active EFI vars copy (64MB) | PRESENT — used by QEMU |
| `uom-qemu.pid` | PID tracking | PRESENT — PID 29222 |
| `credentials.env` | Credentials (63 bytes) | **SENSITIVE — must never commit** |
| `alpine-virt-3.21.3-aarch64.iso` | Alpine ISO (75MB) | PRESENT |
| `KSU-MANUAL-REQUIRED.md` | KSU instructions | PRESENT |
| `RESUME-PROMPT.md` | Resume instructions | PRESENT |
| `boot.log` | Boot log (empty) | PRESENT |
| `iso_mount/` | ISO mount point | PRESENT |
| `shared/` | Shared dir | PRESENT |
| `logs/` | Log dir | PRESENT |
| `locks/` | Lock dir | PRESENT |

**MISSING (from previous audit):** `state/` directory — still not created.
**CLEANED:** Previous audit listed ~20 obsolete files (old serial logs, test scripts, etc.). They appear deleted.

#### `~/.termux/boot/`

| File | Purpose | Status |
|------|---------|--------|
| `start-uom.sh` | Boot script | **STALE** — starts SSH, tunnel, tmux-watchdog, orch but NOT watchdog, NOT wake-lock |

#### `~/.config/uom/`

| File | Purpose | Status |
|------|---------|--------|
| `zen.env` | Zen config | **EMPTY/MISSING** (sed failed to parse) |

#### QEMU live state:
- **PID:** 29222 (qemu-system-aarch64)
- **tmux session:** uom-qemu-host (1 window)
- **Guest SSH:** OK (hostname: uom-phone-qemu, uptime: 32 min)
- **Stale processes:** 2 orphan bash shells from previous watchdog tests (PIDs 24663, 25382)

### 1C. Guest-side Files

**Guest:** Alpine Linux 3.21.7 aarch64, hostname uom-phone-qemu
**User:** uom (uid=1000)
**Network:** eth0 10.0.2.15/24, ping OK (180ms to 8.8.8.8)

#### `~/bin/` (2 files)

| File | Purpose | Status |
|------|---------|--------|
| `opencode-zen-smart` | Hardened zen wrapper | COMPLETE |
| `opencode-zen-free` | Basic zen rotation | COMPLETE |

#### `~/.opencode/bin/`

| File | Purpose | Status |
|------|---------|--------|
| `opencode` | OpenCode binary (173MB) | COMPLETE — ELF aarch64 musl |

#### Guest git repo: `~/src/universal-omni-master/`
- **HEAD:** `bbee660` (matches laptop and phone — three-way verified)
- **Untracked:** `.opencode/`, duplicate scripts in `bin/`, `UOM-DUAL-AGENT/` scripts, `docs/` stale files
- **Remote:** origin → GitHub (fetch/push)

#### Guest tmux:
- `uom`: 5 windows (created Jul 18 11:25:23) — **zen loop session NOT started**
- Windows: unknown (need to inspect)

#### Agent state (same on guest and laptop):
```
active_agent: "laptop"
current_task_id: "M30-termux-native"
task_status: "pending"
schema_version: 2
```
M33-M37 queue: all pending

---

## 2. DUPLICATE AND CONTRADICTORY CODE

### 2A. QEMU Launcher — 2 COPIES (CRITICAL MISMATCH)

| Location | Size | Notes |
|----------|------|-------|
| Repo `bin/uom-qemu-phone` | 423 lines (~10KB) | TRACKED |
| Phone `~/bin/uom-qemu-phone` | 14,476 bytes | DEPLOYED — **LARGER than repo** |

**Problem:** Phone version is ~4KB larger than repo. Contains code not committed to repo.
**Recommendation:** Diff phone vs repo, reconcile, commit phone version as canonical.

### 2B. Watchdog Scripts — 4+ COPIES

| Location | Purpose |
|----------|---------|
| `scripts/uom-qemu-watchdog.sh` | **CANONICAL** — QEMU health P1-P10 |
| `orchestrators/uom-watchdog.sh` | Laptop reachability (different purpose) |
| `orchestrators/uom-tmux-watchdog.sh` | Tmux session health (different purpose) |
| `bin/uom-tmux-watchdog.sh` | WRAPPER → orchestrators/ |
| Phone `~/bin/uom-qemu-watchdog.sh` | DEPLOYED copy of canonical |
| Phone `~/bin/uom-tmux-watchdog.sh` | DEPLOYED copy of orchestrators/ |

**Recommendation:** KEEP all three as separate concerns (QEMU health, laptop reachability, tmux sessions). The QEMU watchdog is the new one from refactor.

### 2C. Status Display — 3+ COPIES

| Location | Script |
|----------|--------|
| `bin/uom-status.sh` | Shell status |
| Phone `~/bin/uom-status.sh` | Deployed copy |
| `bin/omni-project-start.sh` | Has status display |

**Recommendation:** KEEP `bin/uom-status.sh`.

### 2D. Widget Lib — 2 COPIES

| Location | Script |
|----------|--------|
| `scripts/phone-shortcuts/uom-widget-lib.sh` | **CANONICAL** (repo, tracked) |
| Phone `~/bin/uom-widget-lib.sh` | DEPLOYED (phone) |

**Recommendation:** Deploy from repo. Track and keep as is.

### 2E. `40-UOM-Host-Console` — INCONSISTENT

All other widgets source `uom-widget-lib.sh` → `uom-lib.sh`. **This widget does NOT.** It inlines its own QEMU launcher call and tmux detection.

**Recommendation:** Update to source `uom-widget-lib.sh` for consistency.

### 2F. `uom-hybrid.sh` in `orchestrators/` — DUPLICATE

Previous audit identified this as duplicate of `bin/uom-orchestrator.sh` (which itself was duplicate). Neither exists now in bin/, but `orchestrators/uom-hybrid.sh` is still tracked.

**Recommendation:** DELETE — superseded by `tools/uom-orch-{laptop,phone}.sh`.

---

## 3. HARDCODED VALUES THAT MUST BECOME DYNAMIC

| Value | Where Used | How to Make Dynamic |
|-------|-----------|---------------------|
| `192.168.40.207` (phone IP) | `bin/uom-deploy-phone.sh`, `bin/omni-project-start.sh`, `scripts/uom-sync.sh`, `bin/uom-fix-connectivity.sh` | `uom_network_discover()` — **stub exists in uom-lib.sh** |
| `192.168.40.90` (laptop IP) | `scripts/uom-llm-remote.sh`, `scripts/uom-sync.sh`, `scripts/uom-final-fix.sh` | `~/.config/uom/runtime.env` |
| `uom` (guest username) | `bin/uom-qemu-phone` (SSH commands), `bin/uom-qemu-phone` (status), widgets via `UOM_GUEST_USER` | Already parameterised in lib (`UOM_GUEST_USER`), but launcher hardcodes `uom` |
| `127.0.0.1:2222` (guest SSH) | Launcher, widget-lib, all widgets | Constant — QEMU user-mode is stable. OK as-is. |
| `127.0.0.1:8022` (phone SSH) | Some scripts | `~/.config/uom/runtime.env` |
| `u0_a608` (Termux UID) | `bin/uom-fix-connectivity.sh` | Not needed — use `$USER` or `whoami` |
| `2048` (VM RAM) | Launcher hardcoded | Could be configurable but low priority |

**Already parameterised (no change needed):** `UOM_GUEST_USER`, `UOM_GUEST_PORT`, `UOM_GUEST_HOST` in `uom-lib.sh`.

**Not parameterised (needs fix):** The launcher `bin/uom-qemu-phone` hardcodes `uom@127.0.0.1` in SSH commands (lines 65, 260, 301, 331, 347).

---

## 4. HALF-BAKED IMPLEMENTATIONS

### 4A. `uom_network_discover()` — STUB ONLY
- Function exists in `uom-lib.sh` (line 248-256)
- Only reads `~/.config/uom/last-phone-ip.txt`
- Does NOT do active discovery, subnet scan, or user prompt
- **Missing:** Runtime IP detection, file caching, interactive fallback

### 4B. `uom_mode_detect()` — STUB ONLY
- Function exists in `uom-lib.sh` (line 262-279)
- Detects PHONE_TERMUX, GUEST_IN_PHONE, LAPTOP_DUAL, LAPTOP_SOLO
- **Missing:** Singleton lock integration, orchestrator start/stop logic
- **Missing:** `uom_config_load()` (mentioned in header, not implemented)

### 4C. Dynamic Config (`runtime.env`) — NOT CREATED
- No `config/uom/runtime.env.example` in repo
- No `~/.config/uom/runtime.env` on phone
- All config remains hardcoded

### 4D. `uom-qemu-phone` not using `uom-lib.sh`
- Launcher has its own inline 3-tier detection (duplicating `uom-lib.sh`)
- Does not source `uom-lib.sh` at all
- **Should** source the lib for consistency

### 4E. Boot Script (`~/.termux/boot/start-uom.sh`) — STALE
- Does NOT start watchdog
- Does NOT acquire wake-lock
- Does NOT validate disk
- Does NOT wait for guest SSH before proceeding
- Starts old orchestrator (not the new patterns)

### 4F. Guest `zen.env` — MISSING/EMPTY
- `~/.config/uom/zen.env` on phone appears empty or malformed
- Guest `~/.config/uom/zen.env` was not parseable (sed error)
- Anonymous model access must work without zen.env

### 4G. `config/uom/runtime.env.example` — NOT CREATED
- Step 3 requires this template file
- Does not exist yet

### 4H. State/Lock Directories — MISSING ON PHONE
- `~/uom-vm/state/` not created
- `~/uom-vm/locks/` is empty

### 4I. Orphan Watchdog Test Processes
- PIDs 24663, 25382: stale bash shells from previous watchdog tests
- Not harmful but wasteful

---

## 5. WATCHDOG GAP ANALYSIS

### Existing Watchdogs

| Script | Monitors | Does NOT Monitor |
|--------|----------|------------------|
| `scripts/uom-qemu-watchdog.sh` | P1-P10 (QEMU health) | — (comprehensive) |
| `orchestrators/uom-watchdog.sh` | Laptop heartbeat, tunnel | QEMU process, guest health |
| `orchestrators/uom-tmux-watchdog.sh` | tmux sessions, CPU/battery | QEMU process, guest health |
| Phone `~/bin/uom-tmux-watchdog.sh` | Same as above | Same gaps |

### Watchdog deployment status:
- `scripts/uom-qemu-watchdog.sh` → **DEPLOYED** to phone `~/bin/uom-qemu-watchdog.sh`
- **NOT running in tmux** — no dedicated watchdog window observed
- **NOT started by boot script** — `start-uom.sh` doesn't start it
- **NOT started by launcher** — `bin/uom-qemu-phone start` doesn't start it

### Missing Failure Pattern Detection (per Step 6 spec)

| Pattern | Detection | Auto-Repair | Status |
|---------|-----------|-------------|--------|
| P1: Stale PID file | ps + PID file compare | Adopt PID | **IMPLEMENTED** in watchdog |
| P2: Guest SSH failing | SSH probe 3x | Console log check | **IMPLEMENTED** |
| P3: Guest network broken | ping from guest | `udhcpc` repair | **IMPLEMENTED** |
| P4: Model API failing | curl probe | DNS/TLS repair | **IMPLEMENTED** (P10 cooldown) |
| P5: QEMU died | PID + SSH check | Restart or alert | **IMPLEMENTED** |
| P6: tmux session missing | tmux has-session | Create session | **IMPLEMENTED** |
| P7: Duplicate QEMU | Process count | Kill newest | **IMPLEMENTED** |
| P8: Memory pressure | /proc/meminfo | Alert only | **IMPLEMENTED** |
| P9: Guest disk full | df from guest | Alert only | **IMPLEMENTED** |
| P10: Model quota exhaustion | Usage log grep | Cooldown lockfile | **IMPLEMENTED** |

**All P1-P10 patterns are implemented in the watchdog script.** However:
- Watchdog is NOT integrated into launcher start/stop
- Watchdog is NOT started by boot script
- Watchdog is NOT running in a tmux window

---

## 6. DRY-RUN TEST RESULTS (T1-T10)

Previous session claimed T1-T10: 10/10 PASS. **This was NOT independently verified.** The power cut prevented final verification.

| Test | Description | Claimed | Verified Now | Notes |
|------|-------------|---------|--------------|-------|
| T1 | Status shows RUNNING | PASS | **NOT RUN** | Needs phone-side execution |
| T2 | Start recognizes already-running | PASS | **NOT RUN** | |
| T3 | Guest shell connects | PASS | **NOT RUN** | |
| T4 | Zen console shows session | PASS | **NOT RUN** | |
| T5 | Logs show useful content | PASS | **NOT RUN** | |
| T6 | Stop with wrong word cancels | PASS | **NOT RUN** | |
| T7 | QEMU count = 1 after T1-T6 | PASS | **NOT RUN** | |
| T8 | Stop with "STOP" shuts down | PASS | **NOT RUN** | |
| T9 | Cold start from widget | PASS | **NOT RUN** | |
| T10 | Status after restart | PASS | **NOT RUN** | |

**CRITICAL: All T1-T10 tests must be re-run from scratch.** The power cut interrupted before verification.

---

## 7. PROPOSED REFACTORING PLAN

Ordered from least to most risky.

### 7.1. Kill orphan watchdog test processes (RISK: LOW)
- Kill PIDs 24663, 25382 on phone (stale bash shells)
- **Files:** phone process table only

### 7.2. Reconcile phone launcher with repo (RISK: LOW)
- Diff phone `~/bin/uom-qemu-phone` vs repo `bin/uom-qemu-phone`
- Phone version is 14KB, repo is ~10KB. Determine which is canonical.
- Commit phone version to repo if it has additional features
- **Files:** `bin/uom-qemu-phone`

### 7.3. Standardise `40-UOM-Host-Console` (RISK: LOW)
- Add `uom-widget-lib.sh` sourcing
- Remove inline QEMU detection
- **Files:** `scripts/phone-shortcuts/40-UOM-Host-Console`

### 7.4. Delete `orchestrators/uom-hybrid.sh` (RISK: LOW)
- Confirmed duplicate, no unique functionality
- **Files:** `orchestrators/uom-hybrid.sh` (git rm)

### 7.5. Delete `UOM-DUAL-AGENT/` obsolete files (RISK: LOW)
- Keep only `UOM-DUAL-AGENT-ORCHESTRATOR.md`
- Delete all `.sh` files and `www/` contents
- **Files:** ~15 files in `UOM-DUAL-AGENT/`

### 7.6. Integrate watchdog into launcher (RISK: MEDIUM)
- Start watchdog in tmux window after QEMU start
- Stop watchdog before QEMU stop
- Record watchdog PID
- **Files:** `bin/uom-qemu-phone`, `scripts/uom-lib.sh`

### 7.7. Update boot script (RISK: MEDIUM)
- Add wake-lock acquisition
- Add disk validation
- Start watchdog after QEMU start
- Add bounded guest SSH wait
- **Files:** phone `~/.termux/boot/start-uom.sh`

### 7.8. Create `config/uom/runtime.env.example` (RISK: LOW)
- Template with all configurable values
- **Files:** `config/uom/runtime.env.example`

### 7.9. Dynamic network discovery (RISK: MEDIUM)
- Complete `uom_network_discover()` implementation
- Create `config/uom/runtime.env.example`
- **Files:** `scripts/uom-lib.sh`, `config/uom/runtime.env.example`

### 7.10. Dynamic username/password (RISK: MEDIUM)
- Replace hardcoded `uom` in launcher SSH commands with `${GUEST_USER:-uom}`
- **Files:** `bin/uom-qemu-phone`

### 7.11. Complete bootstrap (RISK: HIGH)
- Full doctor/plan/install/resume/verify
- Generate scripts from templates
- **Files:** `scripts/uom-phone-bootstrap.sh`

---

## 8. FILES TO CREATE (new)

| File | Purpose |
|------|---------|
| `config/uom/runtime.env.example` | Runtime config template (Step 3) |

---

## 9. FILES TO MODIFY (existing)

| File | Changes |
|------|---------|
| `bin/uom-qemu-phone` | Reconcile with phone version, add dynamic user, integrate watchdog |
| `scripts/phone-shortcuts/40-UOM-Host-Console` | Source uom-widget-lib.sh |
| `scripts/uom-lib.sh` | Complete `uom_network_discover()`, `uom_config_load()` |
| `scripts/uom-phone-bootstrap.sh` | Complete doctor/install/verify |
| phone `~/.termux/boot/start-uom.sh` | Add wake-lock, disk validation, watchdog |

---

## 10. FILES TO DELETE (obsolete/duplicate)

### Repo (git rm)

| File | Reason |
|------|--------|
| `orchestrators/uom-hybrid.sh` | Duplicate of orchestrator pattern |
| `UOM-DUAL-AGENT/uom-ip-discover.sh` | Duplicate of `tools/` |
| `UOM-DUAL-AGENT/uom-net-detect.sh` | Duplicate of `tools/` |
| `UOM-DUAL-AGENT/uom-orch-laptop.sh` | Duplicate of `tools/` |
| `UOM-DUAL-AGENT/uom-orch-phone.sh` | Duplicate of `tools/` |
| `UOM-DUAL-AGENT/uom-orch-state.sh` | Duplicate of `tools/` |
| `UOM-DUAL-AGENT/setup/www/*.sh` | Duplicate of `install/` |

### Phone (rm via SSH)

| File | Reason |
|------|--------|
| `~/bin/dryrun-test.sh` | Temporary test script |
| `~/bin/watchdog-sim.sh` | Temporary simulation script |
| Stale bash shells PIDs 24663, 25382 | Orphaned watchdog test processes |

---

## 11. FILES TO MERGE (consolidate)

| Source | Target | Action |
|--------|--------|--------|
| `scripts/phone-shortcuts/uom-widget-lib.sh` | `scripts/uom-lib.sh` | Already done — widget-lib is now wrapper |
| `bin/uom-qemu-phone` inline detection | `scripts/uom-lib.sh` functions | Should source lib instead of duplicating |

---

## 12. CRITICAL ISSUES REQUIRING IMMEDIATE ATTENTION

1. **T1-T10 tests NOT verified** — previous session claimed 10/10 PASS but power cut prevented independent verification. Must re-run.
2. **Phone launcher version mismatch** — 14KB deployed vs ~10KB in repo. Must reconcile before any refactoring.
3. **Watchdog NOT integrated** — script exists and is deployed, but not started by launcher or boot script.
4. **Boot script stale** — missing wake-lock, disk validation, watchdog start.
5. **`40-UOM-Host-Console` inconsistent** — does not source shared lib like all other widgets.
6. **No `runtime.env` or template** — all config still hardcoded.
7. **Orphan processes** — 2 stale bash shells from watchdog tests on phone.
8. **Guest `zen.env` unreadable** — anonymous model access path unclear.
9. **`orchestrators/uom-hybrid.sh` still tracked** — duplicate, should be deleted.
10. **`UOM-DUAL-AGENT/` obsolete files still tracked** — should be pruned.

---

**End of audit report. Awaiting approval before proceeding with Steps 1-10.**
