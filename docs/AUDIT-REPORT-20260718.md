# AUDIT REPORT — 2026-07-18

**Branch:** `refactor/structure-audit-2026-07-17`
**Commit:** `ebe18b6` (three-way verified: laptop = GitHub = phone)
**Tag:** `uom-phone-qemu-phase9-20260718`
**Auditor:** opencode (automated, Step 0 of refactoring plan)

---

## 1. COMPLETE FILE INVENTORY

### 1A. Laptop Repo — Tracked Files (436 total)

#### `bin/` — CLI entry points (30 files)

| File | Purpose | Status |
|------|---------|--------|
| `bin/uom-qemu-phone` | **UNTRACKED** — QEMU launcher v2.1 | COMPLETE (deployed to phone) |
| `bin/uom-sync` | Git sync tool | COMPLETE |
| `bin/uom-sync-status` | Sync status display | COMPLETE |
| `bin/uom-status.sh` | Hybrid status check | PARTIAL — references orchestrator logs |
| `bin/uom-orchestrator.sh` | Unified hybrid orchestrator | DUPLICATE of `bin/omni-orchestrator.sh` |
| `bin/omni-orchestrator.sh` | Unified hybrid orchestrator | DUPLICATE of `bin/uom-orchestrator.sh` |
| `bin/omni-orchestrator-monitor.sh` | Status monitor | DUPLICATE of `bin/create_omni_status_alias.sh` |
| `bin/create_omni_status_alias.sh` | Status alias generator | DUPLICATE of monitor above |
| `bin/create_status_alias.py` | Python status alias | DUPLICATE of shell version |
| `bin/omni-status` | Python status CLI | DUPLICATE of shell version |
| `bin/uom-deploy-phone.sh` | Phone deployment | PARTIAL — hardcodes IPs |
| `bin/uom-phone-provision.sh` | Phone provisioning | PARTIAL |
| `bin/uom-reverse-ssh.sh` | Reverse SSH tunnel | COMPLETE |
| `bin/uom-resume.sh` | Session resume | PARTIAL |
| `bin/uom-fix-connectivity.sh` | Connectivity repair | PARTIAL |
| `bin/uom-statectl.sh` | State control | PARTIAL |
| `bin/uom-port-guardian.sh` | Port guardian | WRAPPER → `orchestrators/` |
| `bin/uom-hybrid.sh` | Hybrid orchestrator | WRAPPER → `orchestrators/` |
| `bin/uom-tmux-watchdog.sh` | Tmux watchdog | WRAPPER → `orchestrators/` |
| `bin/omni-orchestrator-monitor.sh` | Orchestrator monitor | DUPLICATE |
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

#### `scripts/` — Phone-specific scripts (43 files)

| File | Purpose | Status |
|------|---------|--------|
| `scripts/phone-shortcuts/00-UOM-Status` | Status widget | COMPLETE (deployed) |
| `scripts/phone-shortcuts/20-UOM-Guest-Shell` | SSH widget | COMPLETE (deployed) |
| `scripts/phone-shortcuts/30-UOM-Zen-Console` | Zen console widget | COMPLETE (deployed) |
| `scripts/phone-shortcuts/40-UOM-Host-Console` | Host console widget | COMPLETE (deployed) |
| `scripts/phone-shortcuts/50-UOM-Logs` | Logs widget | COMPLETE (deployed) |
| `scripts/phone-shortcuts/90-UOM-Stop` | Stop widget | COMPLETE (deployed) |
| `scripts/phone-shortcuts/tasks/10-UOM-Start` | Start task | COMPLETE (deployed) |
| `scripts/phone-shortcuts/uom-widget-lib.sh` | **UNTRACKED** — Widget shared lib | COMPLETE (deployed) |
| `scripts/phone-shortcuts/opencode-zen-smart` | Zen wrapper | NOT_IN_REPO (only in guest) |
| `scripts/phone-shortcuts/PHONE-APP-ACTION-REQUIRED.md` | User instructions | COMPLETE |
| `scripts/uom-phone-bootstrap.sh` | Bootstrap script | PARTIAL — missing doctor/verify |
| `scripts/uom-phone-bootstrap.sh.sha256` | Bootstrap checksum | COMPLETE |
| `scripts/uom-dryrun.sh` | Dry-run test suite | COMPLETE |
| `scripts/uom-generator.sh` | Zen Loop generator agent | COMPLETE |
| `scripts/uom-verifier.sh` | Zen Loop verifier agent | COMPLETE |
| `scripts/uom-reconcile.sh` | Reconcile (wrapper) | WRAPPER → `orchestrators/` |
| `scripts/uom-sync.sh` | Sync script | PARTIAL — hardcodes IPs |
| `scripts/uom-llm-remote.sh` | Remote LLM via SSH | PARTIAL — hardcodes IPs |
| `scripts/uom-final-fix.sh` | Final fix script | PARTIAL |
| `scripts/uom-proot-setup.sh` | proot setup | COMPLETE |
| `scripts/audit-m11.sh` | M11 audit test | COMPLETE |
| `scripts/test-*.sh` | Test scripts (25 files) | COMPLETE |

#### `tools/` — Shared tooling (7 files)

| File | Purpose | Status |
|------|---------|--------|
| `tools/uom-orch-laptop.sh` | Laptop orchestrator | COMPLETE — dynamic IPs |
| `tools/uom-orch-phone.sh` | Phone orchestrator/watchdog | COMPLETE — dynamic IPs |
| `tools/uom-orch-state.sh` | Shared state functions | COMPLETE |
| `tools/uom-state-lib.sh` | State library | COMPLETE |
| `tools/uom-ip-discover.sh` | IP discovery | COMPLETE |
| `tools/uom-net-detect.sh` | Network detection | COMPLETE |
| `tools/uom-port-watch.sh` | Port watcher | COMPLETE |

#### `orchestrators/` — Orchestrator variants (6 files)

| File | Purpose | Status |
|------|---------|--------|
| `orchestrators/uom-hybrid.sh` | Hybrid orchestrator | DUPLICATE of `bin/uom-orchestrator.sh` |
| `orchestrators/uom-solo-orchestrator.sh` | Solo orchestrator | COMPLETE |
| `orchestrators/uom-watchdog.sh` | Laptop reachability watchdog | DIFFERENT from QEMU health watchdog |
| `orchestrators/uom-tmux-watchdog.sh` | Tmux session watchdog | DIFFERENT from QEMU health watchdog |
| `orchestrators/uom-port-guardian.sh` | Port guardian | COMPLETE |
| `orchestrators/uom-reconcile.sh` | Reconcile | COMPLETE |

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
| `docs/ROADMAP.md` | Project roadmap | PARTIAL — stale M30 references |
| `docs/SESSION-RESUME-2026-07-17.md` | Session resume | STALE — superseded by 07-18 |
| `docs/SESSION-RESUME-2026-07-18.md` | Session resume | CURRENT |
| `docs/M30-MANUAL-RUNBOOK.md` | M30 runbook | COMPLETE |
| `docs/M30-SOURCE-VERIFICATION.md` | M30 source verification | COMPLETE |
| `docs/M11-ROADMAP.md` | M11 roadmap | STALE |
| `docs/SCRIPT-CATALOG.md` | Script catalog | STALE — missing phone scripts |
| `docs/PHONE-SETUP.md` | Phone setup | STALE — superseded by bootstrap |
| `docs/VOID-SYNC.md` | Void Linux sync | IRRELEVANT to phone |

#### `config/` — Configuration (4 files)

| File | Purpose | Status |
|------|---------|--------|
| `config/phone/opencode.json` | OpenCode config template | COMPLETE |
| `config/uom/zen.env.example` | Zen config template | COMPLETE |
| `config/omni-snapshot.conf.example` | Snapshot config | COMPLETE |
| `config/profiles/hp-pavilion-n010tx.toml` | Laptop profile | IRRELEVANT to phone |

#### Other tracked directories

| Directory | Files | Status |
|-----------|-------|--------|
| `src/` | ~130 files | COMPLETE — core UOM library |
| `sandbox/` | ~80 files | COMPLETE — test fixtures |
| `security/` | 4 files | COMPLETE |
| `install/` | 5 files | PARTIAL — `bootstrap-termux.sh` duplicates `scripts/uom-phone-bootstrap.sh` |
| `.uom-agent/` | ~15 files | STALE — M30 in_progress, M33-M37 pending |

### 1B. Phone-side Files

#### `~/bin/` (13 files)

| File | Purpose | Status |
|------|---------|--------|
| `uom-qemu-phone` | Launcher v2.1 | COMPLETE — deployed |
| `uom-widget-lib.sh` | Widget shared lib | COMPLETE — deployed |
| `opencode-musl` | OpenCode binary (173MB) | COMPLETE |
| `opencode-v17` | OpenCode binary (3.4MB) | STALE — superseded by musl |
| `opencode-v18` | OpenCode binary (178MB) | STALE — superseded by musl |
| `opencode.broken.*` | Broken OpenCode | OBSOLETE — delete |
| `ssh-alpine.sh` | SSH to Alpine | OBSOLETE — replaced by launcher |
| `uom-install-alpine.sh` | Alpine installer | PARTIAL |
| `uom-reverse-ssh.sh` | Reverse SSH | COMPLETE |
| `uom-session.sh` | Session helper | PARTIAL |
| `uom-status.sh` | Status script | DUPLICATE |
| `uom-tmux-watchdog.sh` | Tmux watchdog | DEPLOYED — from `orchestrators/` |
| `omni-project-start.sh` | Project start | DEPLOYED — from `bin/` |

#### `~/.shortcuts/` (7 files + 1 task)

| File | Purpose | Status |
|------|---------|--------|
| `00-UOM-Status` | Status widget | COMPLETE |
| `20-UOM-Guest-Shell` | SSH widget | COMPLETE |
| `30-UOM-Zen-Console` | Zen console | COMPLETE |
| `40-UOM-Host-Console` | Host console | COMPLETE |
| `50-UOM-Logs` | Logs widget | COMPLETE |
| `90-UOM-Stop` | Stop widget | COMPLETE |
| `tasks/10-UOM-Start` | Start task | COMPLETE |
| `Alpine SSH.sh` | Old SSH script | OBSOLETE |
| `PHONE-APP-ACTION-REQUIRED.md` | User instructions | COMPLETE |

#### `~/uom-vm/` — VM directory

| File | Purpose | Status |
|------|---------|--------|
| `images/uom-phone.qcow2` | VM disk | COMPLETE |
| `edk2-aarch64-code.fd` | EFI firmware code | COMPLETE |
| `edk2-aarch64-vars.fd` | EFI firmware vars | COMPLETE |
| `uom-efi-vars.fd` | Writable EFI vars copy | COMPLETE |
| `uom-phone-vars.fd` | DUPLICATE EFI vars | OBSOLETE |
| `efi-code.fd` | DUPLICATE firmware | OBSOLETE |
| `efi-vars.fd` | DUPLICATE firmware | OBSOLETE |
| `uom-qemu.pid` | PID tracking | COMPLETE |
| `boot.log` | Boot log | COMPLETE |
| `RESUME-PROMPT.md` | Resume instructions | COMPLETE |
| `KSU-MANUAL-REQUIRED.md` | KSU instructions | COMPLETE |
| `credentials.env` | Credentials | SENSITIVE — never commit |
| `opencode-zen-smart` | Copy of zen wrapper | OBSOLETE — only needed in guest |
| `alpine-virt-3.21.3-aarch64.iso` | Alpine ISO | KEEP |
| `alpine-disk.qcow2.bak` | Old disk backup | OBSOLETE |
| `alpine-minirootfs-*.tar.gz` | Mini rootfs | OBSOLETE |
| `autoinstall.sh` | Auto-install | OBSOLETE |
| `setup-vm.sh` | VM setup | OBSOLETE |
| `vm-install.sh` | VM install | OBSOLETE |
| `poll-install.sh` | Install polling | OBSOLETE |
| `run_qemu_test.sh` | Test script | OBSOLETE |
| `run_qemu_test2.sh` | Test script | OBSOLETE |
| `vmlinuz-virt` | Kernel | OBSOLETE (using direct UEFI boot) |
| `initramfs-virt` | Initramfs | OBSOLETE (using direct UEFI boot) |
| `uom-phone-vars.fd` | Vars copy | OBSOLETE |
| `serial*.log` | Serial logs (5 files) | OBSOLETE |
| `qemu-tmux.log` | Tmux log | OBSOLETE |
| `qemu_debug.log` | Debug log | OBSOLETE |
| `qemu_err.log` | Error log | OBSOLETE |
| `boot_out.txt` | Boot output | OBSOLETE |
| `logs/` | Log directory | PARTIAL — has old install logs |
| `state/` | State directory | MISSING — not created |
| `locks/` | Lock directory | MISSING — not created |

#### `~/.termux/boot/`

| File | Purpose | Status |
|------|---------|--------|
| `start-uom.sh` | Boot script | COMPLETE — starts SSH, tunnel, watchdog, orch |

#### `~/.config/uom/`

| File | Purpose | Status |
|------|---------|--------|
| `zen.env` | MISSING on phone | N/A — phone uses launcher |

### 1C. Guest-side Files

#### Identity
- **OS:** Alpine Linux 3.21.7 (updated from 3.21.3)
- **Hostname:** uom-phone-qemu
- **User:** uom (uid=1000)
- **Disk:** 330M used of 8.3G (5%)

#### `~/bin/` (2 files)

| File | Purpose | Status |
|------|---------|--------|
| `opencode-zen-smart` | Hardened zen wrapper | COMPLETE |
| `opencode-zen-free` | Basic zen rotation | COMPLETE |

#### `~/src/universal-omni-master/`
- **Git repo EXISTS** (earlier audit false-negative due to directory context)
- **Status:** Partial clone — has `.uom-agent/` but limited files visible

#### `~/.config/`

| File | Purpose | Status |
|------|---------|--------|
| `uom/zen.env` | Zen config (254 bytes) | COMPLETE |
| `uom/zen-model-policy.txt` | Model policy | COMPLETE |
| `uom/zen-state.txt` | Zen state | COMPLETE |
| `uom/zen-counter.txt` | Counter | COMPLETE |
| `uom/zen-usage.log` | Usage log | COMPLETE |
| `opencode/opencode.json` | OpenCode config | COMPLETE |

#### `~/.opencode/bin/opencode`
- ELF 64-bit ARM aarch64, 173MB, dynamically linked musl
- **Status:** COMPLETE

#### Network
- eth0: 10.0.2.15/24 (QEMU user-mode)
- Ping 8.8.8.8: OK (62ms)
- Models API: Returns 54 models (including 6 free-tier models)

---

## 2. DUPLICATE AND CONTRADICTORY CODE

### 2A. Orchestrator Scripts — 4 COPIES

| Location | Script | Purpose |
|----------|--------|---------|
| `tools/uom-orch-laptop.sh` | Laptop orchestrator | **CANONICAL** — dynamic IPs, singleton |
| `tools/uom-orch-phone.sh` | Phone orchestrator | **CANONICAL** — dynamic IPs, singleton |
| `bin/uom-orchestrator.sh` | Unified hybrid | DUPLICATE — hardcoded paths |
| `bin/omni-orchestrator.sh` | Unified hybrid | DUPLICATE — nearly identical to above |
| `orchestrators/uom-hybrid.sh` | Hybrid orchestrator | DUPLICATE — another copy |
| `orchestrators/uom-solo-orchestrator.sh` | Solo orchestrator | UNIQUE — keep |

**Recommendation:** KEEP `tools/uom-orch-{laptop,phone}.sh` and `orchestrators/uom-solo-orchestrator.sh`. DELETE `bin/uom-orchestrator.sh`, `bin/omni-orchestrator.sh`, `orchestrators/uom-hybrid.sh`.

### 2B. Watchdog Scripts — 5+ COPIES

| Location | Script | Purpose |
|----------|--------|---------|
| `orchestrators/uom-watchdog.sh` | Laptop reachability | Monitors laptop heartbeat/tunnel |
| `orchestrators/uom-tmux-watchdog.sh` | Tmux sessions | Monitors tmux session health |
| `bin/uom-tmux-watchdog.sh` | Wrapper | Just execs orchestrators/ version |
| `bin/omni-orchestrator-monitor.sh` | Status monitor | Shows orchestrator status |
| `bin/create_omni_status_alias.sh` | Alias generator | DUPLICATE of monitor |
| `bin/create_status_alias.py` | Python alias | DUPLICATE of shell version |
| `scripts/uom-final-fix.sh` | Fix script | Has `_run_watchdog()` function |
| Phone `~/bin/uom-tmux-watchdog.sh` | Deployed copy | DEPLOYED version |

**Recommendation:** KEEP `orchestrators/uom-watchdog.sh` (laptop) and `orchestrators/uom-tmux-watchdog.sh` (tmux). CREATE new `scripts/uom-qemu-watchdog.sh` for QEMU health monitoring (Step 6). DELETE wrappers and duplicates.

### 2C. IP Discovery — 4 COPIES

| Location | Script |
|----------|--------|
| `tools/uom-ip-discover.sh` | **CANONICAL** |
| `tools/uom-net-detect.sh` | **CANONICAL** |
| `UOM-DUAL-AGENT/uom-ip-discover.sh` | DUPLICATE |
| `UOM-DUAL-AGENT/uom-net-detect.sh` | DUPLICATE |
| `UOM-DUAL-AGENT/setup/www/uom-ip-discover.sh` | DUPLICATE |
| `UOM-DUAL-AGENT/setup/www/uom-net-detect.sh` | DUPLICATE |

**Recommendation:** KEEP `tools/` versions. DELETE `UOM-DUAL-AGENT/` script copies.

### 2D. Bootstrap Scripts — 3 COPIES

| Location | Script | Purpose |
|----------|--------|---------|
| `scripts/uom-phone-bootstrap.sh` | One-shot bootstrap | **CANONICAL** — has doctor/plan/install |
| `install/bootstrap-termux.sh` | Termux bootstrap | DUPLICATE — different interface |
| `UOM-DUAL-AGENT/setup/phone-bootstrap.sh` | Legacy bootstrap | OBSOLETE |
| `UOM-DUAL-AGENT/setup/www/phone-bootstrap.sh` | Web bootstrap | OBSOLETE |

**Recommendation:** KEEP `scripts/uom-phone-bootstrap.sh`. RENAME/REFACTOR `install/bootstrap-termux.sh` as a thin wrapper or merge. DELETE `UOM-DUAL-AGENT/setup/` copies.

### 2E. Status Display — 4 COPIES

| Location | Script |
|----------|--------|
| `bin/uom-status.sh` | Shell status |
| `bin/omni-status` | Python status |
| `bin/omni-orchestrator-monitor.sh` | Shell monitor |
| `bin/create_omni_status_alias.sh` | Alias generator |
| `bin/create_status_alias.py` | Python alias generator |

**Recommendation:** KEEP `bin/uom-status.sh` as canonical. DELETE others or make thin wrappers.

### 2F. Widget Scripts — 2 COPIES

| Location | Scripts |
|----------|---------|
| `scripts/phone-shortcuts/` | **CANONICAL** (repo) |
| Phone `~/.shortcuts/` | DEPLOYED (phone) |

**Recommendation:** KEEP `scripts/phone-shortcuts/` as canonical. Deploy from there.

### 2G. Widget Lib — 2 COPIES

| Location | Script |
|----------|--------|
| `scripts/phone-shortcuts/uom-widget-lib.sh` | **CANONICAL** (repo, UNTRACKED) |
| Phone `~/bin/uom-widget-lib.sh` | DEPLOYED (phone) |

**Recommendation:** TRACK in repo, rename to `scripts/uom-widget-lib.sh`. Deploy from there.

---

## 3. HARDCODED VALUES THAT MUST BECOME DYNAMIC

| Value | Where Used | How to Make Dynamic |
|-------|-----------|---------------------|
| `192.168.40.207` (phone IP) | `bin/uom-deploy-phone.sh`, `bin/omni-project-start.sh`, `scripts/uom-sync.sh` | `uom_network_discover()` |
| `192.168.40.90` (laptop IP) | `scripts/uom-llm-remote.sh`, `scripts/uom-sync.sh`, `scripts/uom-final-fix.sh` | `~/.config/uom/runtime.env` |
| `uom` (guest username) | Launcher, widget-lib, all widgets, bootstrap | `~/.config/uom/runtime.env` |
| `127.0.0.1:2222` (guest SSH) | Launcher, widget-lib, all widgets | Constant (QEMU user-mode is stable) |
| `127.0.0.1:8022` (phone SSH) | Some scripts | `~/.config/uom/runtime.env` |
| `u0_a608` (Termux UID) | Deployment scripts | Not needed — use `$USER` or `whoami` |
| `alpine123` | Not found in code | OK — no hardcoded passwords |

---

## 4. HALF-BAKED IMPLEMENTATIONS

### 4A. Guest Git Repo — PRESENT but not verified
- Guest has `~/src/universal-omni-master/` with `.git/`
- Earlier audit said "NOT a git repository" — was a context error
- **Status:** Present but not verified for sync state

### 4B. Guest tmux sessions — NOT RUNNING
- No tmux sessions in guest
- Zen Loop (Phase 10) not started
- **Status:** BLOCKED on Phase 10

### 4C. M33-M37 Tasks — ALL PENDING
- Queue: M33, M34, M35, M36, M37 all pending
- State file: `active_agent: "laptop"`, `current_task_id: "M30-termux-native"`, `task_status: "pending"`
- **Status:** STALE — needs reset for phone-only mode

### 4D. Dynamic Config — NOT IMPLEMENTED
- No `~/.config/uom/runtime.env` on phone
- No `~/.config/uom/runtime.env` template in repo
- All config is hardcoded
- **Status:** NOT STARTED — Step 3-5 will implement

### 4E. QEMU Health Watchdog — NOT IMPLEMENTED
- Existing watchdogs monitor: laptop reachability, tmux sessions
- No watchdog monitors: QEMU process, guest SSH, guest network, memory, disk, model quota
- **Status:** NOT STARTED — Step 6 will implement

### 4F. Phone Bootstrap — PARTIAL
- `scripts/uom-phone-bootstrap.sh` has `doctor` and `install` but missing full automation
- `install/bootstrap-termux.sh` has different interface
- **Status:** PARTIALLY IMPLEMENTED

### 4G. `uom-qemu-phone` in Repo — UNTRACKED
- File exists at `bin/uom-qemu-phone` but is not tracked by git
- **Status:** NEEDS `git add`

### 4H. `uom-widget-lib.sh` in Repo — UNTRACKED
- File exists at `scripts/phone-shortcuts/uom-widget-lib.sh` but is not tracked
- **Status:** NEEDS `git add`

---

## 5. WATCHDOG GAP ANALYSIS

### Existing Watchdogs

| Script | Monitors | Does NOT Monitor |
|--------|----------|------------------|
| `orchestrators/uom-watchdog.sh` | Laptop heartbeat, tunnel health, direct reachability | QEMU process, guest health |
| `orchestrators/uom-tmux-watchdog.sh` | tmux session existence, CPU/battery | QEMU process, guest health |
| Phone `~/bin/uom-tmux-watchdog.sh` | Same as above (deployed copy) | Same gaps |

### Missing Failure Pattern Detection (per Step 6 spec)

| Pattern | Detection | Auto-Repair | Status |
|---------|-----------|-------------|--------|
| P1: Stale PID file | ps + PID file compare | Adopt PID | NOT IMPLEMENTED |
| P2: Guest SSH failing | SSH probe 3x | Console log check | NOT IMPLEMENTED |
| P3: Guest network broken | ping from guest | `udhcpc` repair | NOT IMPLEMENTED |
| P4: Model API failing | curl probe | DNS/TLS repair | NOT IMPLEMENTED |
| P5: QEMU died | PID + SSH check | Restart or alert | NOT IMPLEMENTED |
| P6: tmux session missing | tmux has-session | Create session | NOT IMPLEMENTED |
| P7: Duplicate QEMU | Process count | Kill newest | NOT IMPLEMENTED |
| P8: Memory pressure | /proc/meminfo | Alert only | NOT IMPLEMENTED |
| P9: Guest disk full | df from guest | Alert only | NOT IMPLEMENTED |
| P10: Model quota exhaustion | Usage log grep | Cooldown lockfile | NOT IMPLEMENTED |

---

## 6. DRY-RUN TEST RESULTS (T1-T10)

| Test | Description | Previous Result | Notes |
|------|-------------|-----------------|-------|
| T1 | Status shows RUNNING | **PASS** (realistic env) | Shows RUNNING, PID=13862, adopted, SSH OK |
| T1 | Status (env -i) | **FAIL** | "Permission denied" — env -i too restrictive |
| T2 | Start recognizes already-running | **NOT RUN** | Needs realistic Termux env |
| T3 | Guest shell connects | **NOT RUN** | Needs realistic Termux env |
| T4 | Zen console shows session | **NOT RUN** | Needs realistic Termux env |
| T5 | Logs show useful content | **NOT RUN** | Needs realistic Termux env |
| T6 | Stop with wrong word cancels | **NOT RUN** | Needs realistic Termux env |
| T7 | QEMU count = 1 after T1-T6 | **NOT RUN** | Needs realistic Termux env |
| T8 | Stop with "STOP" shuts down | **NOT RUN** | Blocked on T7 |
| T9 | Cold start from widget | **NOT RUN** | Blocked on T8 |
| T10 | Status after restart | **NOT RUN** | Blocked on T9 |

**Critical finding:** `env -i` is NOT how Termux:Widget runs scripts. Real env has HOME, PATH, PREFIX, TERM. Testing must use realistic env vars.

---

## 7. PROPOSED REFACTORING PLAN

Ordered from least to most risky.

### 7.1. Track untracked files (RISK: LOW)
- `git add bin/uom-qemu-phone scripts/phone-shortcuts/uom-widget-lib.sh`
- Move widget-lib to `scripts/uom-widget-lib.sh`
- **Files:** `bin/uom-qemu-phone`, `scripts/uom-widget-lib.sh`

### 7.2. Prune phone stale files (RISK: LOW)
- Delete from `~/uom-vm/`: `alpine-disk.qcow2.bak`, `run_qemu_test*.sh`, `serial*.log`, `qemu_*.log`, `boot_out.txt`, `opencode-zen-smart`, `uom-phone-vars.fd`, `efi-*.fd`, `autoinstall.sh`, `setup-vm.sh`, `vm-install.sh`, `poll-install.sh`, `vmlinuz-virt`, `initramfs-virt`
- Delete from `~/bin/`: `opencode-v17`, `opencode-v18`, `opencode.broken.*`, `ssh-alpine.sh`
- Delete from `~/.shortcuts/`: `Alpine SSH.sh`
- **Files:** ~20 files on phone

### 7.3. Delete obsolete repo files (RISK: LOW)
- `UOM-DUAL-AGENT/uom-ip-discover.sh`, `uom-net-detect.sh`, `uom-orch-*.sh`
- `UOM-DUAL-AGENT/setup/www/*.sh`
- `bin/uom-orchestrator.sh` (duplicate of omni-orchestrator.sh)
- `bin/omni-orchestrator.sh` (duplicate of bin/uom-orchestrator.sh)
- `orchestrators/uom-hybrid.sh` (duplicate)
- `bin/create_omni_status_alias.sh` (duplicate)
- `bin/create_status_alias.py` (duplicate)
- `bin/omni-status` (duplicate)
- `bin/omni-orchestrator-monitor.sh` (duplicate)
- **Files:** ~15 files in repo

### 7.4. Create consolidated shared library (RISK: MEDIUM)
- Create `scripts/uom-lib.sh` absorbing `uom-widget-lib.sh`
- Functions: `uom_qemu_find_pid`, `uom_qemu_running`, `uom_qemu_adopt_pid`, `uom_guest_ssh_test`, `uom_wait_guest_ssh`, `uom_log`, `uom_ensure_qemu`, `uom_network_discover`, `uom_mode_detect`, `uom_config_load`
- Deploy to phone `~/bin/uom-lib.sh`
- Update all widgets to source `uom-lib.sh` instead of `uom-widget-lib.sh`
- **Files:** CREATE `scripts/uom-lib.sh`, MODIFY all widgets

### 7.5. Standardize script headers (RISK: LOW)
- Add NAME/PURPOSE/VERSION/DEPENDS/SAFE/TESTED to all phone scripts
- **Files:** All scripts in `scripts/phone-shortcuts/`

### 7.6. Dynamic network discovery (RISK: MEDIUM)
- Create `config/uom/runtime.env.example` (committed)
- Create `~/.config/uom/runtime.env` on phone (not committed)
- Implement `uom_network_discover()` in `uom-lib.sh`
- Replace hardcoded IPs in deployment scripts
- **Files:** CREATE `config/uom/runtime.env.example`, MODIFY `scripts/uom-lib.sh`

### 7.7. Solo/dual mode detection (RISK: MEDIUM)
- Implement `uom_mode_detect()` in `uom-lib.sh`
- Add singleton lock to orchestrator scripts
- **Files:** MODIFY `scripts/uom-lib.sh`, `tools/uom-orch-*.sh`

### 7.8. Dynamic username/password (RISK: MEDIUM)
- Replace hardcoded `uom` with `${GUEST_USER:-uom}` in launcher, widget-lib, widgets
- Update bootstrap to prompt for credentials
- **Files:** MODIFY launcher, widget-lib, all widgets, bootstrap

### 7.9. QEMU health watchdog (RISK: HIGH)
- Create `scripts/uom-qemu-watchdog.sh` with P1-P10 detection
- Deploy to phone `~/bin/uom-qemu-watchdog.sh`
- Integrate with launcher start/stop
- Add tmux window `uom-qemu-host:watchdog`
- **Files:** CREATE `scripts/uom-qemu-watchdog.sh`, MODIFY launcher

### 7.10. One-click bootstrap (RISK: HIGH)
- Rewrite `scripts/uom-phone-bootstrap.sh` with full doctor/plan/install/resume/verify
- Generate launcher, watchdog, widgets from templates
- Automate Alpine setup with answer file
- **Files:** REWRITE `scripts/uom-phone-bootstrap.sh`

---

## 8. FILES TO CREATE (new)

| File | Purpose |
|------|---------|
| `scripts/uom-lib.sh` | Consolidated shared library |
| `scripts/uom-qemu-watchdog.sh` | QEMU health watchdog (P1-P10) |
| `config/uom/runtime.env.example` | Runtime config template |
| `docs/AUDIT-REPORT-20260718.md` | This report |

---

## 9. FILES TO MODIFY (existing)

| File | Changes |
|------|---------|
| `scripts/phone-shortcuts/00-UOM-Status` | Source `uom-lib.sh`, standardize header |
| `scripts/phone-shortcuts/20-UOM-Guest-Shell` | Source `uom-lib.sh`, standardize header |
| `scripts/phone-shortcuts/30-UOM-Zen-Console` | Source `uom-lib.sh`, standardize header |
| `scripts/phone-shortcuts/40-UOM-Host-Console` | Standardize header |
| `scripts/phone-shortcuts/50-UOM-Logs` | Source `uom-lib.sh`, standardize header |
| `scripts/phone-shortcuts/90-UOM-Stop` | Source `uom-lib.sh`, standardize header |
| `scripts/phone-shortcuts/tasks/10-UOM-Start` | Source `uom-lib.sh`, standardize header |
| `bin/uom-qemu-phone` | Dynamic user/port, watchdog integration, standardize header |
| `scripts/uom-phone-bootstrap.sh` | Full doctor/plan/install/resume/verify |
| `tools/uom-orch-phone.sh` | Singleton lock, watchdog integration |
| `docs/PHONE-ONLY-OPERATIONS.md` | Update with watchdog, dynamic config |

---

## 10. FILES TO DELETE (obsolete/duplicate)

### Repo (git rm)

| File | Reason |
|------|--------|
| `bin/uom-orchestrator.sh` | Duplicate of `bin/omni-orchestrator.sh` |
| `bin/omni-orchestrator.sh` | Duplicate of `tools/uom-orch-*.sh` |
| `orchestrators/uom-hybrid.sh` | Duplicate of above |
| `bin/omni-orchestrator-monitor.sh` | Duplicate of `bin/uom-status.sh` |
| `bin/create_omni_status_alias.sh` | Duplicate of monitor |
| `bin/create_status_alias.py` | Duplicate of shell version |
| `bin/omni-status` | Duplicate of shell version |
| `UOM-DUAL-AGENT/uom-ip-discover.sh` | Duplicate of `tools/` |
| `UOM-DUAL-AGENT/uom-net-detect.sh` | Duplicate of `tools/` |
| `UOM-DUAL-AGENT/uom-orch-laptop.sh` | Duplicate of `tools/` |
| `UOM-DUAL-AGENT/uom-orch-phone.sh` | Duplicate of `tools/` |
| `UOM-DUAL-AGENT/uom-orch-state.sh` | Duplicate of `tools/` |
| `UOM-DUAL-AGENT/setup/www/*.sh` | Duplicate of `install/` |
| `docs/SESSION-RESUME-2026-07-17.md` | Superseded by 07-18 |
| `docs/M11-ROADMAP.md` | Stale |
| `docs/VOID-SYNC.md` | Irrelevant to phone |

### Phone (rm via SSH)

| File | Reason |
|------|--------|
| `~/bin/opencode-v17` | Superseded by opencode-musl |
| `~/bin/opencode-v18` | Superseded by opencode-musl |
| `~/bin/opencode.broken.*` | Broken |
| `~/bin/ssh-alpine.sh` | Replaced by launcher |
| `~/.shortcuts/Alpine SSH.sh` | Replaced by launcher |
| `~/uom-vm/alpine-disk.qcow2.bak` | Old backup |
| `~/uom-vm/run_qemu_test*.sh` | Test scripts |
| `~/uom-vm/serial*.log` | Old serial logs |
| `~/uom-vm/qemu_*.log` | Old QEMU logs |
| `~/uom-vm/boot_out.txt` | Old boot output |
| `~/uom-vm/opencode-zen-smart` | Only needed in guest |
| `~/uom-vm/uom-phone-vars.fd` | Duplicate EFI vars |
| `~/uom-vm/efi-*.fd` | Duplicate firmware |
| `~/uom-vm/autoinstall.sh` | Obsolete |
| `~/uom-vm/setup-vm.sh` | Obsolete |
| `~/uom-vm/vm-install.sh` | Obsolete |
| `~/uom-vm/poll-install.sh` | Obsolete |
| `~/uom-vm/vmlinuz-virt` | Obsolete |
| `~/uom-vm/initramfs-virt` | Obsolete |

---

## 11. FILES TO MERGE (consolidate)

| Source | Target | Action |
|--------|--------|--------|
| `scripts/phone-shortcuts/uom-widget-lib.sh` | `scripts/uom-lib.sh` | Absorb into consolidated lib |
| `bin/uom-status.sh` | `scripts/uom-lib.sh` | Status functions → lib |
| `tools/uom-state-lib.sh` | `scripts/uom-lib.sh` | State functions → lib (or keep separate) |
| `install/bootstrap-termux.sh` | `scripts/uom-phone-bootstrap.sh` | Merge or make thin wrapper |

---

## CRITICAL ISSUES REQUIRING IMMEDIATE ATTENTION

1. **`env -i` testing is invalid** — Termux:Widget provides full env. All dry-run tests must use realistic env vars.
2. **`uom-qemu-phone` and `uom-widget-lib.sh` are UNTRACKED** — must be committed.
3. **Guest models API returns `[]` with `pricing.prompt=="0"` filter** — the API response doesn't have `pricing.prompt` field. Free models must be identified by ID suffix (`-free`) not pricing.
4. **State file is stale** — `active_agent: "laptop"` but phone is the active device. M30 is `in_progress` but actually completed.
5. **No QEMU health watchdog exists** — any QEMU crash, guest hang, or network failure goes undetected.
6. **Credentials file exists on phone** (`~/uom-vm/credentials.env`) — must never be committed.

---

**End of audit report. Awaiting approval before proceeding with refactoring steps.**
