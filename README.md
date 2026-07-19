<p align="center">
  <img src="https://img.shields.io/badge/Shell-POSIX%20BusyBox%20ash-000000?logo=gnubash&logoColor=white" alt="POSIX sh">
  <img src="https://img.shields.io/badge/Release-v0.34.0--rc1-blueviolet?logo=github" alt="Release">
  <img src="https://img.shields.io/badge/License-MIT-green?logo=opensourceinitiative" alt="License">
  <img src="https://img.shields.io/badge/Dual--Agent-Laptop+Phone-orange?logo=android" alt="Dual-Agent">
  <img src="https://img.shields.io/badge/Network-Drift%20Resilient-blue" alt="Network">
  <img src="https://img.shields.io/badge/Installer-Hardened-brightgreen" alt="Hardened">
  <img src="https://img.shields.io/badge/Model-Dynamic%20Rotation-ff6b6b" alt="Dynamic Model">
</p>

<h1 align="center">UNIVERSAL OMNI-MASTER</h1>
<p align="center">
  <b>POSIX-Hardened AI Infrastructure Stack</b><br>
  <i>Dual-agent orchestration. Dynamic model rotation. Network drift resilience. Zero dependencies.</i>
</p>

<p align="center">
  <a href="#-overview">Overview</a> ·
  <a href="#-architecture">Architecture</a> ·
  <a href="#-bootstrap--installer">Bootstrap</a> ·
  <a href="#-file-structure">Structure</a> ·
  <a href="#-cli-surface">CLI</a> ·
  <a href="#-dual-agent-system">Dual-Agent</a> ·
  <a href="#-zen-loop-pipeline">Zen Loop</a> ·
  <a href="#-roadmap">Roadmap</a> ·
  <a href="#-quick-start">Quick Start</a>
</p>

---

## Overview

UOM is a POSIX-hardened AI infrastructure stack that turns any two POSIX devices (laptop + phone) into a resilient dual-agent AI system.

**What it does:**
- Provisions Android/Termux phones as AI relay nodes
- Runs a cloud code generation pipeline (Zen Loop) with dynamic free-model rotation
- Survives network changes (WiFi switch, hotspot migration) without reconfiguration
- Deploys rootless QEMU aarch64 VMs on phones for isolated AI workloads
- Syncs state across 3 nodes via Git (laptop, phone1, phone2)

**Key design constraints:**
- POSIX `#!/bin/sh` throughout — zero bashisms, zero Python runtime deps
- No local LLMs — cloud-only via opencode with anonymous free-tier models
- No sudo — runs entirely as unprivileged user
- No hardcoded IPs — 5-method IP discovery cascade with drift resilience

---

## Bootstrap + Installer

### One curl command — zero-trust phone deployment

```sh
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh | bash
```

This single command deploys the full phone/laptop agent stack via a **secure 3-stage chain**:

```
curl pipe
  │
  ▼
Stage 1: bootstrap.sh (88 lines) — Secure download-validate-exec
  ├─ Auto-detects Termux/Android vs Alpine Linux
  ├─ Downloads child script from GitHub raw with 3-retry, 60s timeout
  ├─ Validates: size <500KB, shebang present, not HTML, POSIX syntax
  └─ exec child with all forwarded arguments
  │
  ▼
Stage 2 (Termux): bootstrap-termux.sh (950 lines, hardened)
  ├─ phone-relay (default): tmux, openssh, git, jq, curl, autossh, fzf
  │   SSH key (id_ed25519_uom), SSH config (UOM-managed block),
  │   repo clone (SHA-safe + tarball fallback), Termux:Boot
  │   opencode install ladder: pkg → npm → go install → remote installer
  └─ phone-vm-agent (opt-in): +QEMU aarch64/proot-distro + Alpine VM
      Consent required: --allow-large-download --allow-vm --allow-opencode-install
  │
  ▼
Stage 2 (Alpine): bootstrap-laptop.sh (45 lines)
  └─ apk packages, npm/Ginstall opencode CLI (free/no-auth tier),
     fish PATH persistence (~/.opencode/bin), clone repo,
     enable sshd/avahi, doas guard
  │
  ▼
Result: Fully provisioned phone agent + laptop with SSH tunnel, tmux,
        opencode CLI (free tier, no auth), and optional QEMU aarch64 VM
```

### Profiles

| Profile | Size | What It Installs | Consent Required |
|---------|------|------------------|-----------------|
| `phone-relay` | ~25KB packages | tmux, openssh, git, jq, curl, autossh, fzf, SSH key, SSH config, UOM repo, Termux:Boot | None |
| `phone-vm-agent` | +proot-distro/QEMU | Same + QEMU aarch64 + proot-distro + Alpine VM image | `--allow-large-download --allow-vm --allow-opencode-install` |

```sh
# Read-only preflight (safe to run anywhere):
sh install/bootstrap-termux.sh --check

# Install phone-relay (default):
sh install/bootstrap-termux.sh --apply --verify

# Install VM profile (requires explicit consent):
sh install/bootstrap-termux.sh --apply --profile phone-vm-agent \
  --allow-large-download --allow-vm --allow-opencode-install

# Laptop Alpine:
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap-laptop.sh | sh
```

### Hardening Patches (v0.34.0)

| Patch | Fix | Detail |
|-------|-----|--------|
| A | SHA-safe clone | `git clone --depth 1` → `fetch --depth 1 origin $REF` → `checkout` → codeload tarball fallback. Non-empty dirs skipped safely. |
| B | Key consistency | Dedicated `id_ed25519_uom` with UOM-MANAGED-BEGIN/END markers. Never overwrites unrelated keys. |
| C | Arch policy | `qemu-system-x86_64` removed from aarch64 defaults. `DEFAULT_VM_BACKEND=proot`. QEMU aarch64 = experimental opt-in only. |
| D | Network gate | `REPO_STATE=skipped-network` on github unreachable. Phone-relay succeeds without repo. |
| E | pkg update | 3-retry with `timeout 60`, warn-and-continue on total failure. |

Test harness: `sh tests/test-phone-bootstrap.sh` (72 assertions, 54/72 pass).

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         UNIVERSAL OMNI-MASTER                             │
│                           v0.34.0-rc1                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────┐        ┌─────────────────────────┐        │
│  │     LAPTOP (Primary)    │◄──────►│     PHONE1 (Secondary)  │        │
│  │     Alpine Linux        │  SSH   │     Termux / Android    │        │
│  │     opencode            │  rvrs  │     opencode + QEMU VM  │        │
│  │     dynamic IP          │  tunnel│     aarch64 guest       │        │
│  └───────────┬─────────────┘  31415 └───────────┬─────────────┘        │
│              │                                   │                       │
│              │        ┌──────────────────┐       │                       │
│              │        │  PHONE2 (Mom's)  │       │                       │
│              │        │  WiFi Hotspot    │       │                       │
│              │        │  Termux + SSH    │       │                       │
│              │        └──────────────────┘       │                       │
│              │                                   │                       │
│  ┌───────────▼───────────────────────────────────▼─────────────────┐    │
│  │              Git (Shared State Store via GitHub)                │    │
│  │  .uom-agent/state.json  │  queue.json  │  done.json             │    │
│  │  heartbeat/schema v2    │  multi-node   │  takeover_count       │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │              Zen Loop Cloud Pipeline                             │    │
│  │  Dynamic model selection (4-model free pool, auto-failover)      │    │
│  │  Network drift resilience (port guardian, SHA256 fingerprint)    │    │
│  │  No ollama. No sudo. No hardcoded models. No API keys.          │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

### Current Network Topology

| Node | Role | IP | User | Model | SDK | Status |
|------|------|----|------|-------|-----|--------|
| Phone2 | Hotspot/Gateway | 10.21.250.151 | u0_a217 | Redmi Note | 35 | UP |
| Laptop | Primary agent | 10.21.250.90 | alpine | HP Pavilion | — | UP |
| Phone1 | Secondary + QEMU host | 10.21.250.76 | u0_a608 | MI 8 | 35 | UP (QEMU running) |

- Phone2 provides the WiFi hotspot. Laptop and Phone1 connect through it.
- Direct SSH on port 8022 between all nodes (no reverse tunnel needed on same subnet).
- Phone1 runs `qemu-system-aarch64` with Alpine guest for isolated AI workloads.

---

## File Structure

```
universal-omni-master/
├── bin/                              # CLI entrypoints + wrappers
│   ├── uom-ssh-phone.sh              # Drift-tolerant laptop->phone SSH (5-method discovery)
│   ├── uom-reverse-ssh.sh            # Phone->laptop reverse tunnel (autossh-backed)
│   ├── uom-port-guardian.sh          # -> orchestrators/ (symlink wrapper)
│   ├── uom-tmux-watchdog.sh          # -> orchestrators/ (symlink wrapper)
│   ├── uom-status.sh                 # Service status dashboard
│   ├── uom-qemu-phone                # QEMU VM lifecycle manager
│   ├── uom-deploy-phone.sh           # Deploy scripts -> phone via SSH
│   ├── uom-phone-provision.sh        # proot-distro Debian + opencode provisioner
│   ├── uom-sync / uom-sync-status    # Git sync helpers
│   ├── uom-checkpoint.sh             # Session checkpoint/resume
│   ├── uom-statectl.sh               # State file management
│   └── uom-resume.sh                 # Session resume note
│
├── orchestrators/                    # Long-running daemon coordinators
│   ├── uom-reconcile.sh              # 6-step Zen Loop (dynamic model + drift resilience)
│   ├── uom-port-guardian.sh          # Network drift sentinel (20s polling, SSH rewrite)
│   ├── uom-watchdog.sh               # Phone->laptop reachability + wake-lock
│   ├── uom-tmux-watchdog.sh          # Tmux session guardian + tunnel watchdog
│   └── uom-solo-orchestrator.sh      # Phone-only fallback when laptop dies
│
├── scripts/                          # Pipelines, generators, verifiers, tests
│   ├── uom-generator.sh              # Cloud code generator (opencode stdin, 3-retry)
│   ├── uom-verifier.sh               # Syntax/policy verifier (stub-aware)
│   ├── uom-lib.sh                    # Consolidated shared library (~280 lines)
│   ├── uom-dryrun.sh                 # Full dry-run test suite
│   ├── uom-phone-bootstrap.sh        # Phone bootstrap wrapper + checksum
│   ├── uom-qemu-watchdog.sh          # QEMU health watchdog (P1-P10)
│   ├── uom-reconcile.sh              # Standalone reconcile entry
│   ├── uom-sync.sh                   # Sync loop helper
│   └── test-*.sh (32 files)          # Milestone regression tests (M1-M27)
│
├── tools/                            # Libraries + orchestration tools
│   ├── uom-model-rotate.sh           # Free model rotation (Retry-After, history, 4-model pool)
│   ├── uom-state-lib.sh              # POSIX state library with atomic locking (v2)
│   ├── uom-ip-discover.sh            # 5-method IP discovery cascade
│   ├── uom-queue.sh                  # Task queue manager
│   ├── uom-phone-gen-loop.sh         # Phone generator loop (PHASE14)
│   ├── uom-sync-loop.sh              # Bidirectional sync loop (PHASE15)
│   ├── uom-feedback-aggregator.sh    # Verifier feedback loop (PHASE16)
│   ├── uom-orch-laptop.sh            # Laptop-side orchestrator
│   ├── uom-orch-phone.sh             # Phone-side orchestrator
│   ├── uom-orch-state.sh             # State machine interface
│   └── uom-smoke-sync.sh             # Smoke test sync
│
├── install/                          # Bootstrap + installation
│   ├── bootstrap.sh                  # Universal curl installer (auto-detects platform)
│   ├── bootstrap-termux.sh           # Termux-specific installer (hardened, 926 lines)
│   ├── bootstrap-laptop.sh           # Laptop Alpine bootstrap
│   └── secrets.env.template          # API key template (keys blank)
│
├── tests/                            # Test suites
│   ├── test-phone-bootstrap.sh       # 72-assertion installer test harness
│   ├── test-remote-llm.sh            # Remote LLM pipeline test (PHASE13)
│   └── test-zen-loop-e2e.sh          # End-to-end Zen Loop test (PHASE17)
│
├── docs/                             # Architecture + operations (44 docs)
│   ├── ROADMAP.md                    # Full roadmap
│   ├── SCRIPT-CATALOG.md             # Complete script inventory + caller/callee map
│   ├── ZEN-LOOP.md                   # Zen Loop architecture + verifier rejection
│   ├── CONCURRENCY.md                # Conflict matrix + singleton patterns
│   ├── NETWORK-SCENARIOS.md          # 10 network scenarios + model rotation
│   ├── SECURITY-BOUNDARIES.md        # Security policy
│   ├── PHONE-ONLY-OPERATIONS.md      # Daily phone operations
│   ├── PHONE-SETUP.md                # Phone setup guide
│   ├── SYNC-ARCHITECTURE.md          # Git sync policy + architecture
│   ├── INSTALLER-TRUTH-MATRIX-20260719.md  # Installer audit results
│   ├── NET-ADAPT-WIFI-SWITCH-TEST-20260719.md  # WiFi switch test report
│   ├── POSTWIFI-INSTALLER-DRYRUN-20260719.md   # Post-wifi dry-run results
│   ├── GUARDRAIL-DRYRUN-20260719.md            # Guardrail test results
│   ├── SESSION-GATE-20260719.md                # Session gate table
│   └── (30 more)
│
├── scripts/phone-shortcuts/          # Phone app shortcuts (12 scripts)
│   ├── 00-UOM-Status                 # Status widget
│   ├── 30-UOM-Zen-Console            # Zen console launcher
│   ├── 50-UOM-Logs                   # Log viewer
│   ├── 90-UOM-Stop                   # Graceful stop
│   ├── tasks/10-UOM-Start            # Boot startup task
│   └── opencode-zen-smart            # Smart model selection shortcut
│
├── .uom-agent/                       # Runtime state (gitignored)
│   ├── state.json                    # Agent state machine (schema v2)
│   ├── queue.json                    # Task queue (PHASE13-17)
│   ├── done.json                     # Completed tasks
│   ├── phone.host                    # Phone IP:PORT hint (port-guardian managed)
│   ├── laptop.host                   # Laptop IP:PORT hint
│   ├── runtime/                      # selected_model, net_fingerprint, last-reconcile
│   ├── logs/                         # Component logs
│   ├── locks/                        # Singleton lockfiles (mkdir-based)
│   └── generated/verified/           # Zen Loop output staging
│
├── config/uom/                       # Configuration templates
│   └── zen.env.example               # Zen Loop env vars
│
└── security/                         # Hardening + firewall + hooks
    ├── uom-harden-ssh.sh             # ed25519-only SSH
    ├── uom-firewall.sh               # nftables firewall
    └── install-hooks.sh              # Pre-commit hooks
```

---

## CLI Surface

### Operational Tools

| Tool | Location | Purpose |
|------|----------|---------|
| `uom-ssh-phone.sh` | `bin/` | Drift-tolerant laptop->phone SSH (5-method IP discovery) |
| `uom-reverse-ssh.sh` | `bin/` | Phone->laptop reverse tunnel (autossh-backed) |
| `uom-port-guardian.sh` | `orchestrators/` | Network drift sentinel (20s polling, SSH config rewrite) |
| `uom-watchdog.sh` | `orchestrators/` | Phone->laptop reachability + wake-lock |
| `uom-tmux-watchdog.sh` | `orchestrators/` | Tmux session + tunnel watchdog |
| `uom-reconcile.sh` | `orchestrators/` | 6-step Zen Loop (dynamic model + drift resilience) |
| `uom-solo-orchestrator.sh` | `orchestrators/` | Phone-only fallback when laptop unreachable |
| `uom-generator.sh` | `scripts/` | Cloud code generator (opencode stdin + 3-retry) |
| `uom-verifier.sh` | `scripts/` | Syntax/policy verifier (stub-aware, no LLM calls) |
| `uom-model-rotate.sh` | `tools/` | Free model rotation (4-model pool, Retry-After handling) |
| `uom-state-lib.sh` | `tools/` | POSIX state library with atomic locking (v2) |
| `uom-queue.sh` | `tools/` | Task queue manager |
| `uom-sync-loop.sh` | `tools/` | Bidirectional sync loop |
| `uom-feedback-aggregator.sh` | `tools/` | Verifier feedback aggregation |
| `uom-phone-gen-loop.sh` | `tools/` | Phone generator loop |
| `uom-status.sh` | `bin/` | Service status dashboard |

---

## Dual-Agent System

Laptop + Phone operate as a resilient AI agent pair. Git serves as the shared state store.

### Node Modes

| Mode | Trigger | Who Runs opencode |
|------|---------|-------------------|
| **dual** | Both reachable | Laptop primary |
| **solo** | Laptop unreachable (>300s) | Phone autonomous |
| **pending** | >15 min (3 watchdog cycles) | Manual confirm to dual |

### State Machine (schema v2)

```
state.json:
  agent_mode: "dual" | "solo" | "pending"
  heartbeat: timestamp
  takeover_count: int
  last_sync: timestamp

queue.json:
  tasks[]: { id, phase, description, status, created, updated }
  status: "pending" | "in_progress" | "done" | "failed" | "stale"
```

### Network Resilience

`orchestrators/uom-port-guardian.sh` is a background sentinel that:

1. **Discovers** phone IP via 5-method cascade (stored hint → known IPs → subnet scan)
2. **Reacts** on drift (~20s polling): rewrites SSH config, publishes host hints, signals reconcile
3. **Fingerprints** network: SHA256(gateway + laptop_ip + phone_ip)

Tunnel port is fixed at `31415` with pre-flight reachability check.

---

## Zen Loop Pipeline

Cloud-only code generation with dynamic model selection and network drift resilience.

```
┌──────────┐   ┌───────────┐   ┌────────────┐   ┌──────────┐
│ Step 0   │──>│ Step 1-2  │──>│ Step 3-4   │──>│ Step 5-6 │
│ Pre-fl   │   │ tmux +    │   │ Network +  │   │ Generate │
│ checks   │   │ model     │   │ tunnel     │   │ + verify │
│          │   │ selection │   │ discovery  │   │ + super  │
└──────────┘   └───────────┘   └────────────┘   └──────────┘
```

### Free Model Pool

| # | Model | Auto-Failover |
|---|-------|---------------|
| 1 | `deepseek-v4-flash-free` | Primary |
| 2 | `nemotron-3-ultra-free` | Fallback 1 |
| 3 | `north-mini-code-free` | Fallback 2 |
| 4 | `big-pickle` | Fallback 3 |

Cache TTL: 300s | Retry-After: respected | History: 50

### 6-Step Reconcile Pipeline

| Step | Action | Script |
|------|--------|--------|
| 0 | Pre-flight: sshd, jq, opencode, routing, API reachability | `orchestrators/uom-reconcile.sh` |
| 1-2 | Tmux guard + cloud bootstrap: create session, select model | `orchestrators/uom-reconcile.sh` |
| 3-4 | Network + tunnel: fingerprint, port 31415 liveness, guardian start | `orchestrators/uom-reconcile.sh` |
| 5-6 | Zen agents + supervisor: generator, verifier, status report | `scripts/uom-generator.sh`, `scripts/uom-verifier.sh` |

### Usage

```sh
# Full pipeline:
sh orchestrators/uom-reconcile.sh

# Force model re-selection:
sh orchestrators/uom-reconcile.sh --reselect-model

# Model rotation standalone:
sh tools/uom-model-rotate.sh select   # pick best free model
sh tools/uom-model-rotate.sh status   # show pool + history

# Just generate:
scripts/uom-generator.sh "write a POSIX sh function"
```

---

## Roadmap

### Sealed (Foundation through Phase 12)

| Phase | Milestones | Core Deliverables |
|-------|-----------|-------------------|
| Foundation | M1–M6 | Detection, Init, Boot, GPU, Storage, Audit |
| Deployment | M7–M12 | Installer, Healer, Snapshot, Rollback, TUI |
| Ecosystem | M13–M15 | Monolith, SSH, Plugins, Security, Fleet |
| Intelligence | M16–M20 | State Machine, Adaptive TUI, Seed, Manifests |
| Commercial | M21–M26 | Manager, KVM, SaaS, AI-Patcher, Compliance |
| Desktop | M27 | 11 WM/DE Profiles, Telemetry, Postboot Verify |
| Dual-Agent | M28–M29 | IP Discovery, State Machine, Bootstrap, Solo Mode |
| Mobile | M30 | Project menu, tmux watchdog, port-guardian |
| Cloud + Zen | M30.5 | Cloud-only redirect, Zen Loop reconciler |
| Dynamic | M31 | Dynamic model selection, network fingerprinting |
| Phase 0–12 | — | Repo audit, watchdog catalog, state v2, security hardening, dual-agent loop, network switching test, power-failure recovery, commercialization prep, network auto-switch, free model rotation, integration verification, documentation |

### Active Pipeline (PHASE13–PHASE17)

| Phase | ID | Description | Status |
|-------|----|-------------|--------|
| **PHASE13** | `ssh-remote-llm` | Verify SSH-based remote LLM pipeline from phone to laptop opencode | Pending |
| **PHASE14** | `phone-generator-loop` | Verify phone generator agent picks up pending tasks and calls remote LLM | Pending |
| **PHASE15** | `bidirectional-sync` | Verify bidirectional sync of generated/verified state between phone and laptop | Pending |
| **PHASE16** | `verifier-feedback-loop` | Verify verifier on laptop processes phone-generated code and writes feedback | Pending |
| **PHASE17** | `zen-loop-e2e` | End-to-end zen loop: phone generates, laptop verifies, phone receives feedback | Pending |

### Recently Completed (2026-07-19 Session)

| Item | Status | Details |
|------|--------|---------|
| WiFi switch dry-run | PASS | Both phones reachable post-WiFi change. Phone2 identified as hotspot host. |
| Installer hardening | 5/5 patches | SHA-safe clone, key consistency, arch policy, network gate, pkg update retry |
| Branch sync | CLEAN | `burnin/dual-agent-20260718` ↔ `fix/phone-bootstrap-release-gate-20260719` at `f97f085` |
| Phone dry-run | PASS | check → apply → idempotency → rollback on Phone2 |
| Guardrail test | PASS | storage, battery, network, arch guardrails all functional |
| README overhaul | DONE | 758→280 lines, roadmap restructured, topology added |

### Future Horizon (Unscheduled)

| Phase | Vision |
|-------|--------|
| M33 | Post-Quantum: ML-KEM-768 hybrid KEX, ML-DSA host keys |
| M34 | Predictive AI: CRC linear regression, thermal telemetry, 60-min failure lookahead |
| M35 | Observability: eBPF kernel telemetry, bpftrace, Tetragon |
| M36 | Edge/IoT: Nix golden images, A/B OTA, dm-verity + Secure Boot |
| M37 | Confidential: AMD SEV-SNP / Intel TDX / ARM CCA detection |
| M38 | Protocol: MCP Server integration for AI assistants |
| M39 | Bootloader: systemd-boot default, BLS entries, UKI first-class |
| M40 | Federation: Hub + daemon + dashboard, Prometheus, mDNS auto-discovery |
| M41-M43 | Power, OverlayFS, Trust |

---

## Quick Start

### Bootstrap (deploy phone agent stack)

```sh
# Deploy full phone agent (auto-detects Termux vs Alpine, 3-stage secure chain):
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh | bash

# Or clone manually for local use:
git clone https://github.com/dharani-sg/universal-omni-master.git
cd universal-omni-master
```

### Phone (Termux) — direct installer

```sh
sh install/bootstrap-termux.sh --check                        # Read-only preflight
sh install/bootstrap-termux.sh --apply                        # Install phone-relay (default)
sh install/bootstrap-termux.sh --apply --verify               # Install + validate
sh install/bootstrap-termux.sh --apply --profile phone-vm-agent \
  --allow-large-download --allow-vm --allow-opencode-install  # Deploy QEMU VM + Alpine
```

### Zen Loop

```sh
sh orchestrators/uom-reconcile.sh                  # Full 6-step pipeline
sh tools/uom-model-rotate.sh select                # Pick best model
sh tools/uom-model-rotate.sh status                # Show pool + history
scripts/uom-generator.sh "write a function"        # Cloud generation
```

### Dual-Agent

```sh
# Laptop:
sh tools/uom-orch-laptop.sh

# Phone:
sh bin/uom-reverse-ssh.sh start    # Reverse tunnel
sh bin/uom-port-guardian.sh start  # Network sentinel

# Verify:
ssh -p 31415 u0_a608@127.0.0.1 "echo TUNNEL OK"
```

### Network Drift

```sh
sh bin/uom-port-guardian.sh start     # Background sentinel
sh bin/uom-port-guardian.sh status    # Running? last-seen targets?
sh bin/uom-port-guardian.sh dryrun    # Self-test
```

---

## Validated Environments

| Distro | Libc | Init | Role | Status |
|--------|------|------|------|--------|
| Alpine 3.21 | musl | OpenRC | Laptop + QEMU guest | Primary |
| Termux (Android 15) | bionic | — | Phone1 + Phone2 | Primary |
| Void Linux | glibc | runit | Laptop (dual-boot) | Tested |
| Debian 12 | glibc | systemd | — | Tested |

**Hardware:**
- HP Pavilion 15-n010tx (Intel i3-3217U, 4GB RAM) — laptop
- Xiaomi Mi 8 (dipper, SDK 35) — Phone1, QEMU host
- Redmi Note 23106RN0DA (SDK 35) — Phone2, hotspot host

---

## Key Policies

| Policy | Rule |
|--------|------|
| **POSIX-First** | `#!/bin/sh` everywhere. BusyBox ash-safe. Zero bashisms, zero `eval`. |
| **No local LLMs** | Cloud-only via `opencode run --model`. No ollama. No local inference. |
| **Secrets** | Never in tracked files. Use `~/.config/uom/secrets.env` (mode 600). |
| **SSH keys** | Dedicated `id_ed25519_uom`. UOM-MANAGED block in config. |
| **Git sync** | GitHub canonical. Pull = fetch + ff-only. No auto-conflict resolution. |
| **Singleton locks** | mkdir-based locks with PID validation + trap cleanup. |
| **Rate limits** | Honor Retry-After. Max 3 retries. Concurrency = 1. |

---

## License

**MIT** — Built with care on a failing SATA cable. Validated on 3 distros + 2 phones.

---

<p align="center">
  <a href="docs/SCRIPT-CATALOG.md">Script Catalog</a> ·
  <a href="docs/ROADMAP.md">Full Roadmap</a> ·
  <a href="docs/ZEN-LOOP.md">Zen Loop</a> ·
  <a href="docs/PHONE-ONLY-OPERATIONS.md">Phone Ops</a> ·
  <a href="docs/SECURITY-BOUNDARIES.md">Security</a> ·
  <a href="docs/SESSION-GATE-20260719.md">Session Gate</a>
</p>
