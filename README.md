<p align="center">
  <img src="https://img.shields.io/badge/Shell-POSIX%20%2F%20BusyBox%20ash-000000?logo=gnubash&logoColor=white" alt="POSIX sh">
  <img src="https://img.shields.io/badge/Release-v0.33.0--rc1-blueviolet?logo=github" alt="Release">
  <img src="https://img.shields.io/badge/License-MIT-green?logo=opensourceinitiative" alt="License">
  <img src="https://img.shields.io/badge/Cross--Libc-musl%20%E2%86%94%20glibc-orange?logo=linux" alt="Cross-Libc">
  <img src="https://img.shields.io/badge/AI%20Economy-Ready-ff6b6b?logo=openai" alt="AI Economy">
  <img src="https://img.shields.io/badge/Dynamic-Model%20%2B%20Port-brightgreen" alt="Dynamic">
  <img src="https://img.shields.io/badge/Init-OpenRC%20%7C%20systemd%20%7C%20runit%20%7C%20s6%20%7C%20dinit-informational" alt="Init">
  <img src="https://img.shields.io/badge/Dual--Agent-Laptop+Phone-orange?logo=android" alt="Dual-Agent">
  <img src="https://img.shields.io/badge/Network-Drift%20Resilient-blue" alt="Network">
</p>

<h1 align="center">UNIVERSAL OMNI-MASTER</h1>
<p align="center">
  <b>POSIX-Hardened AI Infrastructure OS for the Agentic Economy</b><br>
  <i>Dynamic model selection. Network drift resilience. Free-tier model rotation.<br>
  Zero dependencies. Zero sudo. Zero local LLMs.</i>
</p>

<p align="center">
  <a href="#-ai-infrastructure-market">Market</a> ·
  <a href="#-zero-trust-bootstrap">Bootstrap</a> ·
  <a href="#-dual-agent-orchestration">Dual-Agent</a> ·
  <a href="#-zen-loop-pipeline">Zen Loop</a> ·
  <a href="#%EF%B8%8F-architecture">Architecture</a> ·
  <a href="#-file-structure">Structure</a> ·
  <a href="#-cli-surface">CLI</a> ·
  <a href="#-roadmap">Roadmap</a> ·
  <a href="#-quick-start">Quick Start</a> ·
  <a href="docs/SCRIPT-CATALOG.md">Catalog</a> ·
  <a href="docs/CONCURRENCY.md">Concurrency</a> ·
  <a href="docs/NETWORK-SCENARIOS.md">Network</a> ·
  <a href="docs/ZEN-LOOP.md">Zen Loop</a>
</p>

---

## AI Infrastructure Market

**Gartner forecasts $2.6T in global AI spending by 2026** — 47% YoY growth, with infrastructure accounting for 45%+ of the total. The agentic AI market alone is projected at $8.5B in 2026, accelerating toward $35B by 2030. **72% of agentic AI projects stall at pilot** due to infrastructure complexity, not model capability.

UOM is the **operating system for that bottleneck** — a POSIX-hardened, zero-dependency, self-healing provisioning engine that turns any hardware into AI-grade infrastructure.

> *"The $2.6T AI economy runs on infrastructure that doesn't fail. UOM makes sure yours doesn't."*

---

## Zero-Trust Bootstrap

One curl command. Zero trust. Auto-detects Termux/Android (ARM64) or Alpine Linux (x86_64).

```sh
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh | bash
```

| Component | What It Does |
|-----------|-------------|
| tmux + opencode | Dual-pane AI agent workspace |
| ed25519 keys | Zero-password SSH (no passwords allowed) |
| SSH config | Aliases for tunnel/LAN/mDNS discovery |
| Reverse tunnel | `autossh`-backed phone→laptop at `127.0.0.1:31415` |
| nftables firewall | Drop-all-inbound except `22`, `31415`, established |
| Pre-commit hook | Blocks accidental secret commits |

---

## Dual-Agent Orchestration

Laptop (Alpine) + Phone (Termux/Android) operate as a **resilient AI agent pair** connected via SSH reverse tunnel. Git serves as the shared state store. When one node fails, the other takes over autonomously.

```
┌──────────────────────────────────────────────────────────────────────┐
│                    UOM DUAL-AGENT SYSTEM                              │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌────────────────────────┐          ┌────────────────────────┐      │
│  │   LAPTOP (Primary)     │◄────────►│   PHONE (Secondary)    │      │
│  │   Alpine / Void Linux  │  SSH     │   Termux / Android     │      │
│  │   opencode + omni      │  reverse │   opencode (Go build)  │      │
│  │   dynamic IP           │  tunnel  │   dynamic IP:PORT      │      │
│  └──────────┬─────────────┘  31415   └──────────┬─────────────┘      │
│             │                                    │                    │
│  ┌──────────▼────────────────────────────────────▼──────────────┐    │
│  │              Git (Shared State Store)                        │    │
│  │  .uom-agent/state.json  │  queue.json  │  done.json         │    │
│  │  heartbeat/schema v2    │  multi-node  │  takeover_count    │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                       │
│  ┌──────────┬─────────────────────────┬─────────────────────────┐    │
│  │ Mode     │ Trigger                 │ Who Runs opencode       │    │
│  ├──────────┼─────────────────────────┼─────────────────────────┤    │
│  │ dual     │ Both reachable          │ Laptop primary          │    │
│  │ solo     │ Laptop unreachable      │ Phone autonomous        │    │
│  │ pending  │ >15 min (3 watchdog)    │ Manual confirm to dual  │    │
│  └──────────┴─────────────────────────┴─────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
```

**Key differentiator:** Unlike LangGraph + Temporal stacks that require Python, gRPC, and cloud infra, UOM's dual-agent system runs on **any two POSIX devices** connected by SSH. Zero cloud dependency. Zero lock-in.

---

## Zen Loop Pipeline

The **Zen Loop** is a cloud-only code generation pipeline with **dynamic model selection** and **network drift resilience**. No ollama, no sudo, no hardcoded model names.

```
┌────────────────────────────────────────────────────────────────────┐
│                    ZEN LOOP                                         │
│                                                                     │
│  ┌──────────┐   ┌───────────┐   ┌────────────┐   ┌──────────┐    │
│  │ Step 0   │──>│ Step 1-2  │──>│ Step 3-4   │──>│ Step 5-6 │    │
│  │ Pre-fl   │   │ tmux +    │   │ Network +  │   │ Generate │    │
│  │ checks   │   │ model     │   │ tunnel     │   │ + verify │    │
│  │          │   │ selection │   │ discovery  │   │ + super  │    │
│  └──────────┘   └───────────┘   └────────────┘   └──────────┘    │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────┐     │
│  │  FREE MODEL POOL (4 models, auto-failover):               │     │
│  │  1. deepseek-v4-flash-free                                │     │
│  │  2. nemotron-3-ultra-free                                 │     │
│  │  3. north-mini-code-free                                  │     │
│  │  4. big-pickle                                            │     │
│  │  Cache TTL: 300s │ Retry-After: respected │ History: 50   │     │
│  └───────────────────────────────────────────────────────────┘     │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────┐     │
│  │  TUNNEL PORT: fixed 31415 with drift resilience            │     │
│  │  Network fingerprint: SHA256(gw + laptop_ip + phone)      │     │
│  │  On drift: port guardian rewrites SSH config, restarts     │     │
│  └───────────────────────────────────────────────────────────┘     │
└────────────────────────────────────────────────────────────────────┘
```

**6-Step Reconcile Pipeline** (`orchestrators/uom-reconcile.sh`):

| Step | Action | Details |
|------|--------|---------|
| 0 | Pre-flight | sshd, jq, opencode, routing, API reachability, network sanity |
| 1 | Tmux guard | Auto-create `uom-hybrid` session with orchestrator/generator/verifier/status windows |
| 2 | Cloud bootstrap | Dynamic model selection from 4-model pool, health probe, cache, degraded fallback |
| 3 | Network + tunnel | Fingerprint compute, port 31415 liveness check, restart on drift |
| 4 | Port guardian | Start guardian daemon, validate host hint freshness, signal on topology change |
| 5 | Zen agents | Launch generator (dynamic model) + verifier (stub-aware) in tmux windows |
| 6 | Supervisor | Status report, structured JSON log, model/tunnel/network health monitoring |

**Scripts:**

| Script | Location | Purpose |
|--------|----------|---------|
| `uom-reconcile.sh` | `orchestrators/` | 6-step Zen Loop orchestrator with dynamic model + port |
| `uom-generator.sh` | `scripts/` | Cloud code generator via opencode stdin, 3-retry + stub fallback |
| `uom-verifier.sh` | `scripts/` | Syntax/policy verifier, stub-aware (no LLM calls) |
| `uom-model-rotate.sh` | `tools/` | Free model rotation with Retry-After handling + history |
| `uom-proot-setup.sh` | `scripts/` | Cloud env verifier (curl/jq/internet) |

**Reference documentation:**
- `docs/ZEN-LOOP.md` — Full Zen Loop architecture, singleton protection, verifier rejection
- `docs/SCRIPT-CATALOG.md` — Complete script inventory with caller/callee map
- `docs/CONCURRENCY.md` — Conflict matrix, canonical service ownership, singleton patterns
- `docs/NETWORK-SCENARIOS.md` — 10 network scenarios, port guardian, model rotation

**Usage:**
```sh
# Full pipeline (dynamic model + network drift resilience):
sh orchestrators/uom-reconcile.sh

# Force model re-selection:
sh orchestrators/uom-reconcile.sh --reselect-model

# Force network re-discovery:
sh orchestrators/uom-reconcile.sh --reset-network

# Dry run (stop at Step 0):
sh orchestrators/uom-reconcile.sh --dryrun

# Model rotation standalone:
sh tools/uom-model-rotate.sh select   # pick best free model
sh tools/uom-model-rotate.sh next     # rotate to next
sh tools/uom-model-rotate.sh status   # show pool + history

# Just generate:
scripts/uom-generator.sh "write a POSIX sh function to check disk health"

# Just verify:
scripts/uom-verifier.sh path/to/file.sh
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    UNIVERSAL OMNI-MASTER (UOM)                       │
│                        v0.33.0-rc1 — AI Infrastructure Stack         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐       │
│  │omni-detect│  │omni-deploy│  │omni-healer│  │omni-fleet │       │
│  │ Discovery │  │Automator  │  │Watchdog   │  │Orchestr.  │       │
│  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘       │
│        │              │               │               │              │
│  ┌─────▼──────────────▼───────────────▼───────────────▼─────┐       │
│  │              20 POSIX Shell Library Modules                 │       │
│  │  core/ boot/ gpu/ storage/ init/ deploy/ healer/          │       │
│  │  fleet/ snapshot/ security/ manifest/ saas/ ai/           │       │
│  │  compliance/ desktop/ diag/ manager/ plugin/ tui/ test    │       │
│  └──────────────────────────┬────────────────────────────────┘       │
│                             │                                        │
│  ┌──────────────────────────▼────────────────────────────────┐       │
│  │          5 Init Backends  │  3 GPU Vendors                  │       │
│  │  openrc│systemd│runit│s6│dinit  AMD│Intel│NVIDIA            │       │
│  └──────────────────────────┬────────────────────────────────┘       │
│                             │                                        │
│  ┌──────────────────────────▼────────────────────────────────┐       │
│  │         omni-monolith.sh (Single-File Delivery)             │       │
│  │    21 CLIs + 20 Libraries → One Self-Extracting Shell      │       │
│  └────────────────────────────────────────────────────────────┘       │
│                                                                      │
│  ┌─────────────────────┐  ┌─────────────────┐  ┌────────────────┐  │
│  │  Dual-Agent Layer   │  │  AI FinOps Layer │  │  Commercial    │  │
│  │  laptop + phone     │  │  usage accounting│  │  telemetry     │  │
│  │  state machine      │  │  tier enforcement│  │  Stripe billing│  │
│  └─────────────────────┘  └─────────────────┘  └────────────────┘  │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │         Zen Loop Cloud Pipeline                               │   │
│  │  Dynamic model selection (4-model free pool, auto-failover)  │   │
│  │  Network drift resilience (port guardian, fingerprint)        │   │
│  │  No ollama. No sudo. No hardcoded models. No API keys.       │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## File Structure

```
universal-omni-master/
├── bin/                          # CLI entrypoints + compatibility wrappers
│   ├── omni-{detect,deploy,...}  # 21 monolith CLI entrypoints
│   ├── uom-port-guardian.sh      # → orchestrators/ (wrapper)
│   ├── uom-tmux-watchdog.sh      # → orchestrators/ (wrapper)
│   ├── uom-reverse-ssh.sh        # Phone→laptop reverse SSH tunnel
│   ├── uom-ssh-phone.sh          # Drift-tolerant laptop→phone SSH
│   ├── uom-status.sh             # Status dashboard
│   ├── uom-deploy-phone.sh       # Deploy scripts → phone via SSH
│   ├── uom-phone-provision.sh    # proot-distro Debian + OpenCode provisioner
│   └── uom-statectl.sh           # State file management
│
├── orchestrators/                # Long-running daemon coordinators
│   ├── uom-reconcile.sh          # ★ 6-step Zen Loop (dynamic model + drift resilience)
│   ├── uom-port-guardian.sh      # Network drift sentinel (20s polling, SSH rewrite)
│   ├── uom-watchdog.sh           # Phone→laptop reachability + IP drift + wake-lock
│   ├── uom-solo-orchestrator.sh  # Phone-only fallback
│   └── uom-tmux-watchdog.sh      # Tmux session guardian + tunnel watchdog
│
├── scripts/                      # Pipelines, generators, verifiers, tests
│   ├── uom-generator.sh          # Cloud code generator (opencode stdin)
│   ├── uom-verifier.sh           # Syntax/policy verifier (stub-aware)
│   ├── uom-dryrun.sh             # Full dry-run test suite
│   ├── uom-lib.sh                # Consolidated shared library (280 lines)
│   ├── uom-qemu-watchdog.sh      # QEMU health watchdog (P1-P10)
│   ├── build-monolith.sh         # Single-file delivery builder
│   └── test-*.sh                 # 32 milestone regression tests
│
├── tools/                        # Shared libraries + orchestrator scripts
│   ├── uom-model-rotate.sh       # ★ Free model rotation (Retry-After, history)
│   ├── uom-state-lib.sh          # POSIX state library with atomic locking (v2)
│   ├── uom-port-watch.sh         # Network probe primitives (read-only)
│   ├── uom-ip-discover.sh        # 5-method IP discovery cascade
│   ├── uom-net-detect.sh         # Network topology detection
│   ├── uom-orch-laptop.sh        # Laptop-side orchestrator
│   └── uom-orch-phone.sh         # Phone-side orchestrator
│
├── docs/                         # Architecture + operations documentation
│   ├── SCRIPT-CATALOG.md         # Complete script inventory + caller/callee map
│   ├── CONCURRENCY.md            # Conflict matrix + singleton patterns
│   ├── NETWORK-SCENARIOS.md      # 10 network scenarios + model rotation
│   ├── NETWORK-AUTOSWITCH-AUDIT.md # Phase 9 gap analysis + implementation
│   ├── ZEN-LOOP.md               # Zen Loop architecture + verifier rejection
│   ├── SESSION-RESUME-2026-07-18.md # Current session state
│   └── PHONE-SETUP.md            # Phone setup guide
│
├── install/                      # Bootstrap + installation
│   ├── bootstrap.sh              # Universal curl installer (auto-detects platform)
│   ├── bootstrap-termux.sh       # Termux-specific bootstrap
│   ├── bootstrap-laptop.sh       # Laptop bootstrap
│   ├── setup-aliases.sh          # Shell alias installer
│   └── secrets.env.template      # API key template (keys blank)
│
├── security/                     # Hardening + firewall + hooks
│   ├── uom-harden-ssh.sh         # ed25519-only SSH
│   ├── uom-firewall.sh           # nftables: allow 22/31415, drop-all-inbound
│   ├── SECRETS.md                # Secrets storage pattern
│   └── install-hooks.sh          # Pre-commit secret scanner
│
├── config/                       # Configuration templates
│   ├── profiles/                 # Hardware profiles (HP Pavilion, etc.)
│   └── phone/                    # Phone-specific opencode config
│
├── UOM-DUAL-AGENT/               # Legacy design doc only (scripts removed)
│   └── UOM-DUAL-AGENT-ORCHESTRATOR.md
│
├── sandbox/                      # Test fixtures (Alpine sysroot mock)
├── src/                          # Core UOM library (20 modules, 449 functions)
├── .uom-agent/                   # Runtime state (gitignored contents)
│   ├── state.json                # Agent state machine (schema v2)
│   ├── queue.json                # Task queue (PHASE13-17)
│   ├── done.json                 # Completed tasks
│   ├── phone.host                # Phone IP:PORT hint (port-guardian managed)
│   ├── laptop.host               # Laptop IP:PORT hint
│   ├── runtime/                  # Ephemeral runtime state
│   │   ├── selected_model        # Current cloud model (300s TTL cache)
│   │   ├── net_fingerprint       # Network topology SHA256
│   │   └── last-reconcile.json   # Structured reconciliation log
│   ├── logs/                     # Component logs
│   ├── locks/                    # Singleton lockfiles (mkdir-based)
│   └── generated/verified/       # Zen Loop output staging
│
├── api_wrapper.py                # Free-tier API client wrapper
├── NETWORK_CODE_POLICY.md        # Network code requirements
└── README.md                     # This file
```

---

## CLI Surface

**21 POSIX CLI entrypoints** compiled into a single monolith:

| Command | Domain | Purpose |
|---------|--------|---------|
| `omni-detect` | **Discovery** | Hardware/software topology, AI workload baseline |
| `omni-service` | **Init** | Agnostic service control across 5 init backends |
| `omni-boot` | **Bootloader** | GRUB + systemd-boot + EFI stub management |
| `omni-gpu` | **Graphics** | Hybrid switching, muxless dGPU, AI accelerator detection |
| `omni-storage` | **Storage** | SMART/NVMe/Btrfs, 30+ health subcommands |
| `omni-audit` | **Logging** | Unified structured NDJSON event log |
| `omni-deploy` | **Installer** | Full-disk partition → bootstrap → chroot → deploy |
| `omni-healer` | **Watchdog** | Parallel self-healing daemon (3-layer engine) |
| `omni-snapshot` | **Btrfs** | Snapshot lifecycle, staged rollback, boot-once |
| `omni-security` | **SecOps** | TPM2, UKI, SBAT, PQC KEX detection |
| `omni-fleet` | **Swarm** | Parallel SSH, telemetry aggregation, inventory |
| `omni-manifest` | **Config** | Desired-state drift detection + plan/apply |
| `omni-saas` | **FinOps** | Tier switching, usage accounting, credit enforcement |
| `omni-patcher` | **AI** | LLM-based auto-remediation with consensus + rollback |
| `omni-compliance` | **Compliance** | STIG/CIS enforcement, NDJSON audit |
| `omni-openclaw` | **Commercial** | Telemetry bridge for AI sales agent upsell |
| `omni-desktop` | **Desktop** | 11 WM/DE profiles with telemetry |
| `omni-manager` | **Control** | Central control, module registry, snapshot mgmt |
| `omni-tui` | **Interface** | Fish 4.x adaptive dashboard (16:9 ↔ 9:16) |
| `omni-project-start.sh` | **Dashboard** | Interactive mode switching menu (9 sub-commands) |
| `omni-project-status` | **Status** | Quick status display |

**Operational tools:**

| Tool | Location | Purpose |
|------|----------|---------|
| `uom-reverse-ssh.sh` | `bin/` | Phone→laptop reverse SSH tunnel (autossh-backed) |
| `uom-ssh-phone.sh` | `bin/` | Drift-tolerant laptop→phone SSH (5-method discovery) |
| `uom-port-guardian.sh` | `orchestrators/` | Network drift sentinel (20s polling, SSH config rewrite) |
| `uom-watchdog.sh` | `orchestrators/` | Phone→laptop reachability + IP drift + wake-lock |
| `uom-tmux-watchdog.sh` | `orchestrators/` | Tmux session + tunnel watchdog |
| `uom-solo-orchestrator.sh` | `orchestrators/` | Phone-only fallback when laptop dies |
| `uom-reconcile.sh` | `orchestrators/` | 6-step Zen Loop (dynamic model + drift resilience) |
| `uom-generator.sh` | `scripts/` | Cloud code generator (opencode stdin + retry) |
| `uom-verifier.sh` | `scripts/` | Syntax/policy verifier (stub-aware) |
| `uom-model-rotate.sh` | `tools/` | Free model rotation (Retry-After, history, online-only) |
| `uom-state-lib.sh` | `tools/` | POSIX state library with atomic locking |
| `uom-port-watch.sh` | `tools/` | Network probe primitives (read-only) |
| `uom-ip-discover.sh` | `tools/` | 5-method IP discovery cascade |
| `uom-orch-laptop.sh` | `tools/` | Laptop-side orchestrator |
| `uom-orch-phone.sh` | `tools/` | Phone-side orchestrator |

---

## Roadmap

### Sealed: Foundation through Phase 12 (M1–M31 + Phases 0–12)

| Phase | Milestones | Core Deliverables | Tags |
|-------|-----------|-------------------|------|
| **Foundation** | M1–M6 | Detection, Init, Boot, GPU, Storage, Audit | `v0.1.0`–`v0.6.0` |
| **Deployment** | M7–M12 | Installer, Healer, Snapshot, Rollback, TUI | `v0.7.2`–`v0.12.0` |
| **Ecosystem** | M13–M15 | Monolith, SSH, Plugins, Security, Fleet | `v0.13.0`–`v0.15.0` |
| **Intelligence** | M16–M20 | State Machine, Adaptive TUI, Seed, Manifests | `v0.16.0`–`v0.20.0` |
| **Commercial** | M21–M26 | Manager, KVM, SaaS, AI-Patcher, Compliance | `v0.21.0`–`v0.26.0` |
| **Desktop** | M27 | 11 WM/DE Profiles, Telemetry, Postboot Verify | `v0.27.0`–`v0.27.4` |
| **Dual-Agent** | M28–M29 | IP Discovery, State Machine, Bootstrap, Solo Mode | `v0.28.0`–`v0.29.0` |
| **Mobile** | M30 | Project start menu, tmux watchdog, port-guardian sentinel | `v0.30.0`–`v0.30.1` |
| **Cloud + Zen** | M30.5 | Cloud-only redirect, Zen Loop reconciler, pure cloud pipeline | `v0.31.0` |
| **Dynamic** | M31 | Dynamic model selection, network fingerprinting, singleton locks | `v0.32.0` |
| **Phase 0** | — | Repo structure audit, file inventory, session resume | — |
| **Phase 1** | — | Watchdog audit, 7 scripts catalogued, gaps identified | — |
| **Phase 2** | — | Boot script updated, bootstrap-termux.sh canonical | — |
| **Phase 3** | — | State machine (schema v2), queue.json, atomic locking | — |
| **Phase 4** | — | Security hardening, SSH ed25519-only, nftables firewall | — |
| **Phase 5** | — | Full dual-agent loop, interactive TUI dashboard | — |
| **Phase 6** | — | Network switching stress test | — |
| **Phase 7** | — | Power-failure recovery test | — |
| **Phase 8** | — | Commercialization prep (M44-M51 backlog) | — |
| **Phase 9** | — | Network auto-switch: port guardian restored, watchdog extended, tunnel hardened, SSH wrapper enhanced | `uom-phone-qemu-phase9-20260718` |
| **Phase 10** | — | Free model rotation: `uom-model-rotate.sh`, 4-model pool, Retry-After handling | — |
| **Phase 11** | — | Integration verification: 129/132 dryrun PASS, 3 false-positives identified | — |
| **Phase 12** | — | Documentation: NETWORK-SCENARIOS.md, SCRIPT-CATALOG.md updated | — |

### Active Pipeline Queue (PHASE13–PHASE17)

| Phase | ID | Description | Status |
|-------|----|-------------|--------|
| **PHASE13** | `ssh-remote-llm` | Verify SSH-based remote LLM pipeline from phone to laptop opencode | Pending |
| **PHASE14** | `phone-generator-loop` | Verify phone generator agent can pick up pending tasks and call remote LLM | Pending |
| **PHASE15** | `bidirectional-sync` | Verify bidirectional sync of generated/verified state between phone and laptop | Pending |
| **PHASE16** | `verifier-feedback-loop` | Verify verifier on laptop can process phone-generated code and write feedback | Pending |
| **PHASE17** | `zen-loop-e2e` | End-to-end zen loop: phone generates, laptop verifies, phone receives feedback | Pending |

### Future Horizon (M33–M43) — Unscheduled

> **Note:** These milestone numbers are roadmap placeholders for future features.
> They are distinct from the PHASE13-17 pipeline queue above.
> Do not confuse M33 (horizon) with PHASE13 (active pipeline).

| M | Phase | Vision |
|---|-------|--------|
| **M33** | Post-Quantum | ML-KEM-768 hybrid KEX, crypto inventory, ML-DSA host keys |
| **M34** | Predictive AI | CRC linear regression, thermal telemetry, 60-min failure lookahead |
| **M35** | Observability | eBPF kernel telemetry, bpftrace, Tetragon TracingPolicy |
| **M36** | Edge/IoT | Nix golden images, A/B OTA, dm-verity + Secure Boot |
| **M37** | Confidential | AMD SEV-SNP / Intel TDX / ARM CCA detection |
| **M38** | Protocol | MCP Server integration for AI assistants |
| **M39** | Bootloader | systemd-boot default, BLS entries, UKI first-class |
| **M40** | Federation | Hub + daemon + dashboard, Prometheus, mDNS auto-discovery |
| **M41** | Power | TLP integration, CPU governor auto-tune, RAPL profiling |
| **M42** | OverlayFS | Distro switching, SquashFS + writable overlay |
| **M43** | Trust | Merkle-rooted healing log, PQ-signed entries, TPM identity |

### Commercialization (M44–M51) — Unscheduled

| M | Phase | Revenue Model | Target Market |
|---|-------|--------------|---------------|
| **M44** | Enterprise Bundle | $5K–$50K/node license | Enterprise IT, defense, finance |
| **M45** | Omni-Cloud Managed | $0.10/node/hr usage-based | Startups, AI labs, edge |
| **M46** | AI Agent Marketplace | 30% platform fee | DevOps, MSPs, AI consultants |
| **M47** | Compliance Suite | $15K/year add-on | Regulated industries |
| **M48** | AI FinOps Dashboard | $500/month per 100 nodes | Cloud FinOps teams |
| **M49** | MCP Enterprise Gateway | $2K/month | Enterprise AI platforms |
| **M50** | Edge AI Federation | $100/node/month (100-node min) | Retail, manufacturing, logistics |
| **M51** | Omni-Genesis | Strategic partnerships / white-label | OEMs, telcos, cloud providers |

**TAM:** $2.6T global AI spending. **SAM:** ~$150B serviceable across bare-metal provisioning, edge orchestration, and AI FinOps.

---

## Quick Start

```sh
# Bootstrap any device (auto-detects platform)
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh | bash

# Clone manually
git clone https://github.com/dharani-sg/universal-omni-master.git
cd universal-omni-master

# Detect hardware + baseline
./bin/omni-detect

# Build portable monolith
./scripts/build-monolith.sh /tmp/omni.sh
```

### Dual-Agent Quick Start

```sh
# Laptop (Alpine):
cd ~/src/universal-omni-master
sh tools/uom-orch-laptop.sh

# Phone (Termux):
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh | bash

# Verify tunnel from laptop:
ssh -o ConnectTimeout=5 -p 31415 u0_a608@127.0.0.1 "echo TUNNEL OK"

# Check state:
cat .uom-agent/state.json
```

### Zen Loop Quick Start

```sh
# Full 6-step reconcile (dynamic model + drift resilience):
sh orchestrators/uom-reconcile.sh

# Force model re-selection:
sh orchestrators/uom-reconcile.sh --reselect-model

# Force network re-discovery:
sh orchestrators/uom-reconcile.sh --reset-network

# Model rotation standalone:
sh tools/uom-model-rotate.sh select

# Just generate:
scripts/uom-generator.sh "write a POSIX sh function to parse /proc/meminfo"

# Just verify:
scripts/uom-verifier.sh path/to/generated/file.sh
```

### Dual-Agent Start Menu

```sh
omni-project-start              # Interactive menu
omni-project-start status       # Dashboard + exit
omni-project-start hybrid       # Start hybrid auto-orchestrator
omni-project-start tmux         # Start/attach tmux session
omni-project-start test         # Connectivity test suite
```

### Network Drift Resilience

`orchestrators/uom-port-guardian.sh` is a background sentinel that watches for network drift:

- **Discovery** (`tools/uom-port-watch.sh`): stored hint → known IPs → subnet scan
- **Drift reaction** (every ~20s): rewrites SSH config, publishes host hints, signals reconcile
- **Tunnel port**: fixed 31415 with pre-flight reachability check

```sh
sh bin/uom-port-guardian.sh start      # background daemon (tmux)
sh bin/uom-port-guardian.sh status     # running? last-seen targets?
sh bin/uom-port-guardian.sh dryrun     # self-test primitives
```

### Model Rotation

`tools/uom-model-rotate.sh` manages free-tier model selection:

```sh
sh tools/uom-model-rotate.sh select    # pick best free model
sh tools/uom-model-rotate.sh next      # rotate to next
sh tools/uom-model-rotate.sh current   # show current
sh tools/uom-model-rotate.sh verify    # test current model
sh tools/uom-model-rotate.sh status    # pool + history (last 50)
```

### Phone Provisioning via proot-distro

```sh
# From LAPTOP (phone tunnel must be up):
sh bin/uom-phone-provision.sh          # Full interactive (proot → opencode → mirror)
sh bin/uom-phone-provision.sh --auto   # Non-interactive
sh bin/uom-phone-provision.sh --check  # Verify installation
```

### Bulletproof State Recovery

1. **Git as state store**: Every heartbeat committed and pushed. On restart, pull latest.
2. **Stale detection**: Crashed tasks remain `in_progress`. Orchestrator resets on restart.
3. **Watchdog takeover**: Phone checks laptop reachability. Unreachable >300s → phone takes over.
4. **Handback**: Laptop returns → phone detects fresh heartbeat → returns to watchdog mode.
5. **opencode timeout**: 1800s laptop / 2400s phone. Hung tasks marked `failed`.

---

## Validated Environments

| Distro | Libc | Init | Pkg Mgr | Status |
|--------|------|------|---------|--------|
| **Alpine 3.21** | musl | OpenRC | apk | Primary |
| **Void Linux** | glibc | runit | xbps | Dual-boot |
| **Arch Linux** | glibc | systemd | pacman | Tested |
| **Debian 12** | glibc | systemd | apt | Tested |
| **Artix Linux** | glibc | OpenRC/runit/s6 | pacman | Tested |
| **Chimera Linux** | musl | dinit | apk | Experimental |

**Reference hardware:** HP Pavilion 15-n010tx (Intel i3-3217U, 4GB RAM, degraded SATA cable).

---

## The UOM Manifesto

| # | Rule | Rationale |
|:--|:-----|:----------|
| 1 | **POSIX-First** | `#!/bin/sh` everywhere; BusyBox ash-safe; zero bashisms, zero `eval`. |
| 2 | **Mutation Safety** | State-changing ops return 126 when `OMNI_SYSROOT` is set. |
| 3 | **Baseline Telemetry** | Relative degradation, not absolute. Alerts on deltas. |
| 4 | **Monolithic Delivery** | 21 CLIs + 20 libraries → one `scp`-able script. |
| 5 | **Gate-Verified** | No milestone tagged until all test suites pass 100%. |
| 6 | **Rule #12** | `$`/`${}`/backticks in commit messages → `git commit -F file`. |

---

## Singleton Protection

All long-running orchestrators use **mkdir-based singleton locks** (`/tmp/.uom_*_lock`) with PID liveness validation and trap cleanup. This prevents duplicate daemon instances across hotplug/reboot cycles.

| Script | Lock Path | Cleanup |
|--------|-----------|---------|
| `uom-reconcile.sh` | `.uom-agent/locks/reconcile.lock` | EXIT INT TERM |
| `uom-port-guardian.sh` | `.uom-agent/runtime/portguard.lock` | EXIT INT TERM |
| `uom-watchdog.sh` | `/tmp/.uom_watchdog_lock` | EXIT INT TERM |
| `uom-tmux-watchdog.sh` | `/tmp/.uom_tmuxwatch_lock` | EXIT INT TERM |
| `uom-orch-laptop.sh` | `/tmp/.uom_orch_laptop_lock` | EXIT INT TERM |
| `uom-orch-phone.sh` | `/tmp/.uom_orch_phone_lock` | EXIT INT TERM |

---

## Contributing

1. **Read the Manifesto** — POSIX-first, mutation safety, gate-verified.
2. **Run the regression gate** — `./scripts/compat-check.sh` must pass 100%.
3. **No bashisms** — `#!/bin/sh` everywhere. BusyBox ash-safe.
4. **No comments unless asked** — Code is self-documenting.
5. **Secrets never in tracked files** — Use `~/.config/uom/secrets.env` (mode 600).
6. **No local LLMs** — Cloud-only via `opencode --model`. No ollama. No local inference.

---

## Known Issues (v0.33.0-rc1)

- **Reverse tunnel:** DOWN until phone runs `sh bin/uom-reverse-ssh.sh` — Termux:Boot restarts on device boot
- **SATA CRC:** 5361 (degraded cable) — avoid large writes to primary disk
- **Disk usage:** 85% on root partition — monitor for space exhaustion
- **Phone opencode:** recommended path is proot-distro Debian via `sh bin/uom-phone-provision.sh`
- **Cloud-only:** All generation uses dynamic model selection from 4-model free pool. Requires internet. Stub generator on total failure.
- **Dryrun false positives:** 3 known (comment-matching `sudo`, read-only `state.json` jq, stale `18022` in verifier)
- **Port:** Fixed 31415. No dynamic port range — drift handled by port guardian SSH config rewrite.

---

## Phone-Only QEMU Architecture

UOM runs entirely on a Xiaomi Mi 8 (dipper) with crDroid Android 15 inside a rootless QEMU VM. No laptop required for daily operation after initial setup.

```
Phone (Termux, Android 15, SDK 35)
  └─ QEMU rootless TCG (no KVM)
       └─ Alpine 3.21 aarch64 (musl/OpenRC)
            ├─ opencode-zen-smart (curl wrapper, primary transport)
            ├─ opencode-zen-free (basic rotation)
            └─ UOM repo (~/src/universal-omni-master)
```

| Component | Version | Notes |
|-----------|---------|-------|
| Phone | Xiaomi Mi 8 (dipper) | crDroid Android 15, SDK 35 |
| Termux | Google Play 2026.06.21 | Same source for all plugins |
| QEMU | 10.2.1 | Rootless, TCG (no KVM) |
| Alpine | 3.21 aarch64 | musl/OpenRC, hostname uom-phone-qemu |
| OpenCode | 1.18.3 (guest) | Native binary BLOCKED (IPv6 hang) |
| Transport | anonymous-api-fallback | curl wrapper primary |

See [docs/PHONE-ONLY-OPERATIONS.md](docs/PHONE-ONLY-OPERATIONS.md) for daily operations.

## Security Boundaries

| Boundary | Policy |
|----------|--------|
| QEMU process | Runs as Termux UID, never root |
| Guest SSH | Key-only, 127.0.0.1:2222 only |
| Networking | User-mode (no TAP/bridge/root) |
| Storage | Termux private storage only |
| AI models | Anonymous, zero-cost, no auth |
| Git | GitHub canonical, no private keys on phone |
| TLS | Never disable verification |

See [docs/SECURITY-BOUNDARIES.md](docs/SECURITY-BOUNDARIES.md) for full policy.

## Git Sync Policy

GitHub is the canonical transport. Both laptop and phone sync through GitHub, not directly to each other.

```
Laptop ──push/fetch──► GitHub ◄──fetch── Phone
```

- Pull = fetch + fast-forward only
- Push requires clean tested tree
- No auto-conflict resolution
- Singleton lock prevents concurrent sync

See [docs/SYNC-ARCHITECTURE.md](docs/SYNC-ARCHITECTURE.md) for details.

## Anonymous Access Warning

Anonymous zero-cost access is an **observed runtime capability**, not a contract. Models may become paid or unavailable at any time. Always verify:
- Model presence via `/zen/v1/models`
- Zero input/output/cached cost in response
- `UOM_ZEN_READY` probe before first use

Never assume a model is free without verification.

## Rate Limit Compliance

- Honor `Retry-After` header on HTTP 429
- Enter global cooldown (never rotate-to-evade)
- Exponential backoff on 5xx/network errors (1s, 2s, 4s)
- Max 3 retries per request
- Concurrency = 1 (singleton lock)

## Native vs Fallback Transport

| Environment | Native OpenCode | Curl Wrapper |
|-------------|----------------|--------------|
| Laptop | Working (primary) | Diagnostic only |
| QEMU Guest | BLOCKED (IPv6 hang) | PRIMARY transport |
| Phone Termux | Working (if installed) | Fallback |

Native OpenCode hangs in QEMU guest due to IPv6 in QEMU user-mode networking. Curl wrapper uses `-4` flag for IPv4-only.

See [docs/OPENCODE-LAPTOP-QEMU-PARITY.md](docs/OPENCODE-LAPTOP-QEMU-PARITY.md) for details.

## Safe Bootstrap Download

```sh
# Download bootstrap script
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/scripts/uom-phone-bootstrap.sh -o /tmp/uom-phone-bootstrap.sh

# Verify checksum
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/scripts/uom-phone-bootstrap.sh.sha256 -o /tmp/uom-phone-bootstrap.sh.sha256
sha256sum -c /tmp/uom-phone-bootstrap.sh.sha256

# Run doctor (non-destructive)
sh /tmp/uom-phone-bootstrap.sh doctor

# Install (only if doctor passes)
sh /tmp/uom-phone-bootstrap.sh install
```

## Release Links

- **Branch:** [`refactor/structure-audit-2026-07-17`](https://github.com/dharani-sg/universal-omni-master/tree/refactor/structure-audit-2026-07-17)
- **Latest release:** [GitHub Releases](https://github.com/dharani-sg/universal-omni-master/releases/latest)

## Milestone Status

| Milestone | Description | Status |
|-----------|-------------|--------|
| M1-M31 + Phases 0-12 | Foundation through documentation | Sealed |
| PHASE13 | SSH remote LLM pipeline verification | Active (next) |
| PHASE14-17 | Phone generator, sync, verifier, e2e | Pending |
| M33-M43 | Future horizon (Post-Quantum → Trust) | Unscheduled |
| M44-M51 | Commercialization | Unscheduled |

---

## License

**MIT** — Forged in the constraints of legacy hardware, engineered for the AI-augmented fleet of the future.

---

<p align="center">
  <i>Built with care on a failing SATA cable. Validated on 6 distros. Targeting $2.6T AI infrastructure market.</i>
</p>
