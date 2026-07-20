<p align="center">
  <img src="https://img.shields.io/badge/UNIVERSAL-OMNI--MASTER-v0.34.0--rc1-6C3FBF?style=for-the-badge&logo=atom&logoColor=white" alt="UOM">
</p>

<h1 align="center">UNIVERSAL OMNI-MASTER</h1>

<p align="center">
  <strong>POSIX-Hardened AI Infrastructure Stack</strong><br>
  <em>Dual-agent orchestration · Dynamic model rotation · Network drift resilience · Zero dependencies</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Shell-POSIX%20ash-1E1E2E?style=flat-square&logo=gnubash&logoColor=white" alt="POSIX sh">
  <img src="https://img.shields.io/badge/Release-v0.34.0--rc1-7C3AED?style=flat-square&logo=github&logoColor=white" alt="Release">
  <img src="https://img.shields.io/badge/License-MIT-10B981?style=flat-square&logo=opensourceinitiative&logoColor=white" alt="License">
  <img src="https://img.shields.io/badge/Dual--Agent-Laptop%2BPhone-F59E0B?style=flat-square&logo=android&logoColor=white" alt="Dual-Agent">
  <img src="https://img.shields.io/badge/Network-Drift%20Resilient-3B82F6?style=flat-square&logo=wifi&logoColor=white" alt="Network">
  <img src="https://img.shields.io/badge/Installer-Hardened-22C55E?style=flat-square&logo=shield&logoColor=white" alt="Hardened">
  <img src="https://img.shields.io/badge/Model-Dynamic%20Rotation-EF4444?style=flat-square&logo=openai&logoColor=white" alt="Dynamic Model">
  <img src="https://img.shields.io/badge/Cost-ZERO-000000?style=flat-square&logo=dollar&logoColor=white" alt="Zero Cost">
</p>

<p align="center">
  <a href="#-overview">Overview</a> ·
  <a href="#-architecture">Architecture</a> ·
  <a href="#-quick-start">Quick Start</a> ·
  <a href="#-cli-surface">CLI</a> ·
  <a href="#-zen-loop-pipeline">Zen Loop</a> ·
  <a href="#-dual-agent-system">Dual-Agent</a> ·
  <a href="#-roadmap">Roadmap</a> ·
  <a href="#-validated-environments">Environments</a> ·
  <a href="#-key-policies">Policies</a>
</p>

---

## Overview

<p align="center">
  <img src="https://img.shields.io/badge/What_It_Does-Transforms_two POSIX devices into a resilient AI system-6366F1?style=for-the-badge" alt="Overview">
</p>

UOM turns any two POSIX devices — a laptop and a phone — into a resilient dual-agent AI system. Cloud-only. No local LLMs. No sudo. No API keys. No hardcoded IPs.

| Capability | How |
|------------|-----|
| 📱 **Phone Provisioning** | Deploy Android/Termux phones as AI relay nodes via a 3-stage hardened bootstrap chain |
| 🔄 **Zen Loop Pipeline** | Cloud code generation with dynamic free-model rotation and 6-step reconcile |
| 🌐 **Network Drift Resilience** | Survives WiFi switches, hotspot migration — 5-method IP discovery + port guardian |
| 💻 **QEMU Workloads** | Rootless QEMU aarch64 VMs on phones for isolated AI processing |
| 🔀 **3-Node State Sync** | Git-based state machine across laptop, phone1, phone2 via GitHub |

**Design Constraints:**
- POSIX `#!/bin/sh` throughout — zero bashisms, zero Python runtime deps
- No local LLMs — cloud-only via opencode with anonymous free-tier models
- No sudo — runs entirely as unprivileged user
- No hardcoded IPs — 5-method IP discovery cascade with drift resilience
- No API keys — free tier only, zero cost

---

## Architecture

<p align="center">
  <img src="https://img.shields.io/badge/System_Architecture-Triple_Node_Mesh-6366F1?style=for-the-badge" alt="Architecture">
</p>

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        UNIVERSAL OMNI-MASTER                            │
│                           v0.34.0-rc1                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────┐       ┌─────────────────────────┐         │
│  │    LAPTOP (Primary)     │◄─────►│    PHONE1 (Secondary)   │         │
│  │    Alpine Linux         │ SSH   │    Termux / Android     │         │
│  │    opencode v1.18.3     │ 8022  │    QEMU aarch64 guest   │         │
│  │    192.168.40.90        │       │    10.21.250.76         │         │
│  └───────────┬─────────────┘       └───────────┬─────────────┘         │
│              │                                  │                       │
│              │       ┌──────────────────┐       │                       │
│              │       │   PHONE2 (Mom's) │       │                       │
│              │       │   WiFi Hotspot   │       │                       │
│              │       │   Termux + SSH   │       │                       │
│              │       │   192.168.40.157 │       │                       │
│              │       └──────────────────┘       │                       │
│              │                                  │                       │
│  ┌───────────▼──────────────────────────────────▼─────────────────┐    │
│  │             Git (Shared State Store via GitHub)                │    │
│  │  state.json (schema v2)  │  queue.json  │  done.json          │    │
│  │  heartbeat               │  multi-node  │  takeover_count     │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                         │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │             Zen Loop Cloud Pipeline                            │    │
│  │  Dynamic model selection (4-model free pool, auto-failover)   │    │
│  │  Network drift resilience (port guardian, SHA256 fingerprint) │    │
│  │  No ollama. No sudo. No hardcoded models. No API keys.        │    │
│  └────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

### Network Topology

| Node | Role | IP | Device | SDK | Status |
|------|------|----|--------|-----|--------|
| 🔴 Phone2 | Hotspot / Gateway | `192.168.40.157` (dynamic) | Redmi Note 23106RN0DA | 35 | <img src="https://img.shields.io/badge/UP-22C55E" alt="UP"> |
| 🔵 Laptop | Primary Agent | `192.168.40.90` (dynamic) | HP Pavilion 15-n010tx | — | <img src="https://img.shields.io/badge/UP-22C55E" alt="UP"> |
| 🟡 Phone1 | Secondary + QEMU Host | `10.21.250.76` (OFFLINE) | Xiaomi Mi 8 (dipper) | 35 | <img src="https://img.shields.io/badge/DEGRADED-F59E0B" alt="DEGRADED"> |

> Phone2 provides the WiFi hotspot (`192.168.40.x` subnet). All IPs are dynamic — use `uom-ip-discover.sh` for discovery. Direct SSH on port 8022 between all nodes.

---

## Quick Start

<p align="center">
  <img src="https://img.shields.io/badge/Get_Started-In_3_Steps-22C55E?style=for-the-badge" alt="Quick Start">
</p>

### 1. Deploy Phone Agent (One Curl Command)

```sh
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh | bash
```

This auto-detects Termux vs Alpine and runs a **secure 3-stage chain**:

```
curl pipe → Stage 1: bootstrap.sh (download-validate-exec)
         → Stage 2: bootstrap-termux.sh (phone-relay or phone-vm-agent)
         → Stage 3: SSH key, tmux, opencode CLI, repo clone
```

### 2. Provision Phone (Direct Installer)

```sh
# Read-only preflight (safe to run anywhere):
sh install/bootstrap-termux.sh --check

# Install phone-relay (default, ~25KB packages):
sh install/bootstrap-termux.sh --apply --verify

# Install VM profile (requires explicit consent):
sh install/bootstrap-termux.sh --apply --profile phone-vm-agent \
  --allow-large-download --allow-vm --allow-opencode-install
```

### 3. Run the Zen Loop

```sh
# Full 6-step pipeline:
sh orchestrators/uom-reconcile.sh

# Force model re-selection:
sh orchestrators/uom-reconcile.sh --reselect-model

# Standalone model operations:
sh tools/uom-model-rotate.sh select   # pick best free model
sh tools/uom-model-rotate.sh status   # show pool + history

# Just generate:
scripts/uom-generator.sh "write a POSIX sh function"
```

### Laptop Bootstrap (Alpine)

```sh
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap-laptop.sh | sh
```

---

## CLI Surface

<p align="center">
  <img src="https://img.shields.io/badge/CLI_Surface-30%2B_Tools-6366F1?style=for-the-badge&logo=terminal&logoColor=white" alt="CLI">
</p>

### 🔧 Core Operations

| Command | Location | Purpose |
|---------|----------|---------|
| `uom-ssh-phone.sh` | `bin/` | Drift-tolerant laptop→phone SSH (5-method IP discovery) |
| `uom-reverse-ssh.sh` | `bin/` | Phone→laptop reverse tunnel (autossh-backed) |
| `uom-port-guardian.sh` | `orchestrators/` | Network drift sentinel (20s polling, SSH config rewrite) |
| `uom-watchdog.sh` | `orchestrators/` | Phone→laptop reachability + wake-lock |
| `uom-tmux-watchdog.sh` | `orchestrators/` | Tmux session + tunnel watchdog |
| `uom-reconcile.sh` | `orchestrators/` | 6-step Zen Loop (dynamic model + drift resilience) |
| `uom-solo-orchestrator.sh` | `orchestrators/` | Phone-only fallback when laptop unreachable |
| `uom-trident-supervisor.sh` | `orchestrators/` | Triple supervisor for overnight orchestrations |

### 🧠 Zen Loop Tools

| Command | Location | Purpose |
|---------|----------|---------|
| `uom-generator.sh` | `scripts/` | Cloud code generator (opencode stdin + 3-retry) |
| `uom-verifier.sh` | `scripts/` | Syntax/policy verifier (stub-aware, no LLM calls) |
| `uom-model-rotate.sh` | `tools/` | Free model rotation (4-model pool, Retry-After handling) |
| `uom-phone-gen-loop.sh` | `tools/` | Phone generator loop (PHASE14) |
| `uom-sync-loop.sh` | `tools/` | Bidirectional sync loop (PHASE15) |
| `uom-feedback-aggregator.sh` | `tools/` | Verifier feedback aggregation (PHASE16) |

### 🛠️ Infrastructure

| Command | Location | Purpose |
|---------|----------|---------|
| `uom-state-lib.sh` | `tools/` | POSIX state library with atomic locking (v2) |
| `uom-queue.sh` | `tools/` | Task queue manager |
| `uom-ip-discover.sh` | `tools/` | 5-method IP discovery cascade |
| `uom-status.sh` | `bin/` | Service status dashboard |
| `uom-deploy-phone.sh` | `bin/` | Deploy scripts → phone via SSH |
| `uom-phone-provision.sh` | `bin/` | proot-distro Debian + opencode provisioner |
| `uom-checkpoint.sh` | `bin/` | Session checkpoint/resume |

### 🏗️ Provisioning Engine (omni-* CLI)

| Command | Purpose |
|---------|---------|
| `omni-detect` | Hardware + OS detection |
| `omni-boot` | Boot config + GRUB management |
| `omni-deploy` | System deployment |
| `omni-gpu` | GPU driver management |
| `omni-storage` | Disk + LVM management |
| `omni-audit` | System audit |
| `omni-healer` | Self-healing repairs |
| `omni-patcher` | Patch management |
| `omni-snapshot` | Btrfs/ZFS snapshots |
| `omni-rollback` | Snapshot rollback |
| `omni-tui` | Terminal UI dashboard |
| `omni-service` | Service management |
| `omni-security` | Security hardening |
| `omni-saas` | SaaS deployment |
| `omni-openclaw` | OpenClaw integration |
| `omni-fleet` | Multi-node fleet management |
| `omni-manager` | Resource management |
| `omni-compliance` | Compliance scanning |
| `omni-manifest` | Package manifests |
| `omni-desktop` | 11 WM/DE profiles |

> Full catalog: [`docs/SCRIPT-CATALOG.md`](docs/SCRIPT-CATALOG.md)

---

## Zen Loop Pipeline

<p align="center">
  <img src="https://img.shields.io/badge/Zen_Loop-6--Step_Reconcile-Pipeline-7C3AED?style=for-the-badge" alt="Zen Loop">
</p>

Cloud-only code generation with dynamic model selection and network drift resilience.

```
┌──────────┐   ┌───────────┐   ┌────────────┐   ┌──────────┐
│ Step 0   │──►│ Step 1-2  │──►│ Step 3-4   │──►│ Step 5-6 │
│ Pre-fl   │   │ tmux +    │   │ Network +  │   │ Generate │
│ checks   │   │ model     │   │ tunnel     │   │ + verify │
│          │   │ selection │   │ discovery  │   │ + super  │
└──────────┘   └───────────┘   └────────────┘   └──────────┘
```

### 6-Step Reconcile

| Step | Action | Script |
|------|--------|--------|
| 0 | Pre-flight: sshd, jq, opencode, routing, API reachability | `orchestrators/uom-reconcile.sh` |
| 1–2 | Tmux guard + cloud bootstrap: create session, select model | `orchestrators/uom-reconcile.sh` |
| 3–4 | Network + tunnel: fingerprint, port 31415 liveness, guardian start | `orchestrators/uom-reconcile.sh` |
| 5–6 | Zen agents + supervisor: generator, verifier, status report | `scripts/uom-generator.sh`, `scripts/uom-verifier.sh` |

### Free Model Pool

| # | Model | Role | Auto-Failover |
|---|-------|------|---------------|
| 1 | `deepseek-v4-flash-free` | Primary | — |
| 2 | `nemotron-3-ultra-free` | Fallback 1 | ✓ |
| 3 | `north-mini-code-free` | Fallback 2 | ✓ |
| 4 | `big-pickle` | Fallback 3 | ✓ |

> Cache TTL: 300s · Retry-After: respected · History: 50 entries · Cost: **$0**

---

## Dual-Agent System

<p align="center">
  <img src="https://img.shields.io/badge/Dual--Agent-Resilient_Pair_Mode-6366F1?style=for-the-badge" alt="Dual-Agent">
</p>

Laptop + Phone operate as a resilient AI agent pair. Git serves as the shared state store.

### Node Modes

| Mode | Trigger | Who Runs opencode |
|------|---------|-------------------|
| 🟢 **dual** | Both reachable | Laptop primary |
| 🟡 **solo** | Laptop unreachable (>300s) | Phone autonomous |
| 🔴 **pending** | >15 min (3 watchdog cycles) | Manual confirm to dual |

### State Machine (schema v2)

```json
{
  "schema_version": 2,
  "active_agent": "dual",
  "writer_role": "laptop",
  "ownership_epoch": 5,
  "task_status": "idle",
  "takeover_count": 0,
  "last_transition": "overnight-triple-PHASE13-PASS->completed"
}
```

### Network Resilience

`orchestrators/uom-port-guardian.sh` is a background sentinel that:

1. **Discovers** phone IP via 5-method cascade (stored hint → known IPs → subnet scan)
2. **Reacts** on drift (~20s polling): rewrites SSH config, publishes host hints, signals reconcile
3. **Fingerprints** network: `SHA256(gateway + laptop_ip + phone_ip)`

Tunnel port fixed at `31415` with pre-flight reachability check.

---

## Bootstrap + Installer

<p align="center">
  <img src="https://img.shields.io/badge/Installer-3--Stage_Hardened-22C55E?style=for-the-badge&logo=shield&logoColor=white" alt="Installer">
</p>

### Secure 3-Stage Chain

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
  │   SSH key (id_ed25519_uom), SSH config (UOM-MANAGED block),
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

### Hardening Patches (v0.34.0)

| Patch | Fix | Detail |
|-------|-----|--------|
| A | SHA-safe clone | `git clone --depth 1` → `fetch --depth 1 origin $REF` → `checkout` → codeload tarball fallback |
| B | Key consistency | Dedicated `id_ed25519_uom` with UOM-MANAGED-BEGIN/END markers |
| C | Arch policy | `qemu-system-x86_64` removed from aarch64 defaults. QEMU aarch64 = experimental opt-in only |
| D | Network gate | `REPO_STATE=skipped-network` on github unreachable. Phone-relay succeeds without repo |
| E | pkg update | 3-retry with `timeout 60`, warn-and-continue on total failure |

> Test harness: `sh tests/test-phone-bootstrap.sh` (72 assertions, 54/72 pass)

---

## Roadmap

<p align="center">
  <img src="https://img.shields.io/badge/Roadmap-M01_to_M43-Sealed_to_Future-7C3AED?style=for-the-badge" alt="Roadmap">
</p>

### ✅ Sealed (Foundation → Phase 12)

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

### 🔄 Active Pipeline (PHASE13–PHASE17)

| Phase | ID | Description | Status |
|-------|----|-------------|--------|
| **PHASE13** | `ssh-remote-llm` | Verify SSH-based remote LLM pipeline from phone to laptop opencode | <img src="https://img.shields.io/badge/PASS-22C55E" alt="PASS"> |
| **PHASE14** | `phone-generator-loop` | Verify phone generator agent picks up pending tasks and calls remote LLM | <img src="https://img.shields.io/badge/PENDING-F59E0B" alt="Pending"> |
| **PHASE15** | `bidirectional-sync` | Verify bidirectional sync of generated/verified state between phone and laptop | <img src="https://img.shields.io/badge/PENDING-F59E0B" alt="Pending"> |
| **PHASE16** | `verifier-feedback-loop` | Verify verifier on laptop processes phone-generated code and writes feedback | <img src="https://img.shields.io/badge/PENDING-F59E0B" alt="Pending"> |
| **PHASE17** | `zen-loop-e2e` | End-to-end zen loop: phone generates, laptop verifies, phone receives feedback | <img src="https://img.shields.io/badge/PENDING-F59E0B" alt="Pending"> |

### 📋 Recently Completed (2026-07-19 Session)

| Item | Status | Details |
|------|--------|---------|
| WiFi switch dry-run | <img src="https://img.shields.io/badge/PASS-22C55E" alt="PASS"> | Both phones reachable post-WiFi change. Phone2 identified as hotspot host |
| Installer hardening | <img src="https://img.shields.io/badge/5%2F5_Patches-22C55E" alt="5/5"> | SHA-safe clone, key consistency, arch policy, network gate, pkg update retry |
| Branch sync | <img src="https://img.shields.io/badge/CLEAN-22C55E" alt="CLEAN"> | `burnin/dual-agent-20260718` ↔ `fix/phone-bootstrap-release-gate-20260719` |
| Phone dry-run | <img src="https://img.shields.io/badge/PASS-22C55E" alt="PASS"> | check → apply → idempotency → rollback on Phone2 |
| Guardrail test | <img src="https://img.shields.io/badge/PASS-22C55E" alt="PASS"> | storage, battery, network, arch guardrails all functional |
| PHASE13 verify | <img src="https://img.shields.io/badge/PASS-22C55E" alt="PASS"> | Real LLM traffic: Phone2→SSH→Laptop→opencode→response verified |

### 🔮 Future Horizon (Unscheduled)

| Phase | Vision |
|-------|--------|
| M33 | **Post-Quantum:** ML-KEM-768 hybrid KEX, ML-DSA host keys |
| M34 | **Predictive AI:** CRC linear regression, thermal telemetry, 60-min failure lookahead |
| M35 | **Observability:** eBPF kernel telemetry, bpftrace, Tetragon |
| M36 | **Edge/IoT:** Nix golden images, A/B OTA, dm-verity + Secure Boot |
| M37 | **Confidential:** AMD SEV-SNP / Intel TDX / ARM CCA detection |
| M38 | **Protocol:** MCP Server integration for AI assistants |
| M39 | **Bootloader:** systemd-boot default, BLS entries, UKI first-class |
| M40 | **Federation:** Hub + daemon + dashboard, Prometheus, mDNS auto-discovery |
| M41-M43 | Power, OverlayFS, Trust |

---

## File Structure

<p align="center">
  <img src="https://img.shields.io/badge/Project_Structure-150%2B_Files-6366F1?style=for-the-badge&logo=folder&logoColor=white" alt="Structure">
</p>

```
universal-omni-master/
├── bin/                              # CLI entrypoints + wrappers (30+)
│   ├── omni-*                       # Provisioning engine (M1-M27)
│   ├── uom-ssh-phone.sh             # Drift-tolerant laptop->phone SSH
│   ├── uom-reverse-ssh.sh           # Phone->laptop reverse tunnel
│   ├── uom-deploy-phone.sh          # Deploy scripts -> phone via SSH
│   ├── uom-phone-provision.sh       # proot-distro provisioner
│   ├── uom-checkpoint.sh            # Session checkpoint/resume
│   └── uom-status.sh                # Service status dashboard
│
├── orchestrators/                    # Long-running daemon coordinators
│   ├── uom-reconcile.sh             # 6-step Zen Loop
│   ├── uom-port-guardian.sh         # Network drift sentinel
│   ├── uom-watchdog.sh              # Phone->laptop reachability
│   ├── uom-tmux-watchdog.sh         # Tmux session guardian
│   ├── uom-solo-orchestrator.sh     # Phone-only fallback
│   ├── uom-trident-supervisor.sh    # Triple orchestrator supervisor
│   └── uom-trident-hook.sh          # Trident event hook
│
├── scripts/                          # Pipelines, generators, tests
│   ├── uom-generator.sh             # Cloud code generator
│   ├── uom-verifier.sh              # Syntax/policy verifier
│   ├── uom-lib.sh                   # Consolidated shared library
│   ├── phone-shortcuts/             # Phone app shortcuts (12)
│   └── test-*.sh                    # Regression tests (32)
│
├── tools/                            # Libraries + orchestration tools
│   ├── uom-model-rotate.sh          # Free model rotation
│   ├── uom-state-lib.sh             # POSIX state library (v2)
│   ├── uom-ip-discover.sh           # 5-method IP discovery
│   ├── uom-queue.sh                 # Task queue manager
│   ├── uom-phone-gen-loop.sh        # Phone generator loop
│   ├── uom-sync-loop.sh             # Bidirectional sync
│   └── uom-feedback-aggregator.sh   # Verifier feedback
│
├── install/                          # Bootstrap + installation
│   ├── bootstrap.sh                 # Universal curl installer
│   ├── bootstrap-termux.sh          # Termux installer (hardened)
│   ├── bootstrap-laptop.sh          # Laptop Alpine bootstrap
│   ├── secrets.env.template         # API key template
│   └── setup-aliases.sh             # Shell aliases
│
├── tests/                            # Test suites
│   ├── test-phone-bootstrap.sh      # 72-assertion installer tests
│   ├── test-remote-llm.sh           # Remote LLM pipeline test
│   ├── test-zen-loop-e2e.sh         # End-to-end Zen Loop test
│   └── burnin.sh                    # Burn-in test suite
│
├── docs/                             # Architecture + operations (45+)
│   ├── ROADMAP.md                   # Full roadmap
│   ├── SCRIPT-CATALOG.md            # Script inventory + caller/callee
│   ├── ZEN-LOOP.md                  # Zen Loop architecture
│   ├── CONCURRENCY.md               # Conflict matrix + singletons
│   ├── NETWORK-SCENARIOS.md         # 10 network scenarios
│   ├── SECURITY-BOUNDARIES.md       # Security policy
│   └── (40 more)
│
├── security/                         # Hardening + firewall + hooks
│   ├── uom-harden-ssh.sh            # ed25519-only SSH
│   ├── uom-firewall.sh              # nftables firewall
│   └── install-hooks.sh             # Pre-commit hooks
│
├── .uom-agent/                       # Runtime state (gitignored)
│   ├── state.json                   # Agent state machine (schema v2)
│   ├── queue.json                   # Task queue
│   ├── done.json                    # Completed tasks
│   ├── phone.host / laptop.host     # IP hints (port-guardian managed)
│   ├── runtime/                     # selected_model, net_fingerprint
│   ├── logs/                        # Component logs
│   ├── locks/                       # Singleton lockfiles (mkdir-based)
│   └── context/                     # M-phase context docs
│
├── reports/                          # Overnight run reports
│   └── morning-report-*.md          # Status reports
│
├── api_wrapper.py                    # Python API client (rate limiting, retry)
├── .opencode/opencode.json           # opencode project config
└── NETWORK_CODE_POLICY.md            # Free-tier API policy
```

---

## Validated Environments

<p align="center">
  <img src="https://img.shields.io/badge/Environments-4_Distros_Tested-3B82F6?style=for-the-badge" alt="Environments">
</p>

| Distro | Libc | Init | Role | Status |
|--------|------|------|------|--------|
| Alpine 3.21 | musl | OpenRC | Laptop + QEMU guest | <img src="https://img.shields.io/badge/PRIMARY-22C55E" alt="Primary"> |
| Termux (Android 15) | bionic | — | Phone1 + Phone2 | <img src="https://img.shields.io/badge/PRIMARY-22C55E" alt="Primary"> |
| Void Linux | glibc | runit | Laptop (dual-boot) | <img src="https://img.shields.io/badge/TESTED-3B82F6" alt="Tested"> |
| Debian 12 | glibc | systemd | — | <img src="https://img.shields.io/badge/TESTED-3B82F6" alt="Tested"> |

**Hardware:**
| Device | Model | Role |
|--------|-------|------|
| 💻 Laptop | HP Pavilion 15-n010tx (Intel i3-3217U, 4GB RAM) | Primary agent |
| 📱 Phone1 | Xiaomi Mi 8 (dipper, SDK 35) | Secondary + QEMU host |
| 📱 Phone2 | Redmi Note 23106RN0DA (SDK 35) | Hotspot host |

---

## Key Policies

<p align="center">
  <img src="https://img.shields.io/badge/Policies-Non--Negotiable-EF4444?style=for-the-badge" alt="Policies">
</p>

| Policy | Rule |
|--------|------|
| 🐚 **POSIX-First** | `#!/bin/sh` everywhere. BusyBox ash-safe. Zero bashisms, zero `eval`. |
| ☁️ **No local LLMs** | Cloud-only via `opencode run --model`. No ollama. No local inference. |
| 🔐 **Secrets** | Never in tracked files. Use `~/.config/uom/secrets.env` (mode 600). |
| 🔑 **SSH keys** | Dedicated `id_ed25519_uom`. UOM-MANAGED block in config. |
| 🔄 **Git sync** | GitHub canonical. Pull = fetch + ff-only. No auto-conflict resolution. |
| 🔒 **Singleton locks** | mkdir-based locks with PID validation + trap cleanup. |
| ⏱️ **Rate limits** | Honor Retry-After. Max 3 retries. Concurrency = 1. |
| 💰 **Zero cost** | Free tier only. No API keys. No paid endpoints. |

---

## License

**MIT** — Built with care on a failing SATA cable. Validated on 3 distros + 2 phones.

<p align="center">
  <img src="https://img.shields.io/badge/Built_With-POSIX_sh-000000?style=for-the-badge&logo=gnubash&logoColor=white" alt="POSIX sh">
  <img src="https://img.shields.io/badge/Zero-Cost-10B981?style=for-the-badge" alt="Zero Cost">
  <img src="https://img.shields.io/badge/Zero-Dependencies-3B82F6?style=for-the-badge" alt="Zero Deps">
  <img src="https://img.shields.io/badge/3_Distros-Tested-F59E0B?style=for-the-badge" alt="3 Distros">
</p>

---

<p align="center">
  <a href="docs/SCRIPT-CATALOG.md">Script Catalog</a> ·
  <a href="docs/ROADMAP.md">Full Roadmap</a> ·
  <a href="docs/ZEN-LOOP.md">Zen Loop</a> ·
  <a href="docs/PHONE-ONLY-OPERATIONS.md">Phone Ops</a> ·
  <a href="docs/SECURITY-BOUNDARIES.md">Security</a> ·
  <a href="docs/SESSION-GATE-20260719.md">Session Gate</a>
</p>
