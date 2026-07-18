# UOM Script Catalog

Reference: HEAD 97e4c76, refactor/structure-audit-2026-07-17.
Catalog date: 2026-07-18.

## Conventions

- **Canonical** — primary implementation, actively maintained.
- **Compatibility wrapper** — thin shim that delegates to canonical script.
- **Generated** — produced by a generator script, not hand-edited.
- **Deprecated** — superseded but kept for reference.
- **Obsolete** — no active callers, kept for history only.

## bin/ — Stable user-facing commands

| Path | Responsibility | Platform | Long-running | Ports | Safe concurrent | Status |
|------|---------------|----------|-------------|-------|----------------|--------|
| bin/omni-project-start.sh | Interactive TUI menu + subcommands | Laptop/Phone | No | — | Yes | Canonical |
| bin/uom-reverse-ssh.sh | Reverse SSH tunnel phone→laptop:31415 | Phone | Yes (loop) | 31415, 8022 | No — singleton via PID | Canonical |
| bin/uom-port-guardian.sh | Dynamic port/host sentinel | Laptop/Phone | Yes (loop) | — | No — singleton via lock | Wrapper → orchestrators/ |
| bin/uom-tmux-watchdog.sh | Tmux session watchdog | Laptop/Phone | Yes (loop) | — | No — singleton via PID | Wrapper → orchestrators/ |
| bin/uom-status.sh | Service status check | Laptop/Phone | No | 31415 | Yes | Canonical |
| bin/uom-resume.sh | Session resume assistant | Laptop | No | 31415 | Yes | Canonical |
| bin/uom-deploy-phone.sh | Deploy scripts to phone | Laptop | No | 31415 | Yes | Canonical |
| bin/uom-phone-provision.sh | Provision proot Debian + opencode on phone | Laptop | No | 31415 | Yes | Canonical |
| bin/uom-ssh-phone.sh | Drift-tolerant SSH wrapper (laptop→phone) | Laptop | No | 8022 | Yes | Canonical |
| bin/uom-qemu-phone | QEMU launcher + watchdog auto-start | Phone | No | 2222 | No — singleton via lock | Canonical |
| bin/uom-checkpoint.sh | Git stage+commit+update resume HEAD | Laptop | No | — | Yes | Canonical |
| bin/uom-statectl.sh | State control | Laptop/Phone | No | — | Yes | Canonical |

## scripts/ — Bounded operational tasks

| Path | Responsibility | Platform | Long-running | Ports | Safe concurrent | Status |
|------|---------------|----------|-------------|-------|----------------|--------|
| scripts/uom-qemu-watchdog.sh | QEMU guest health monitor + auto-repair (P1-P10) | Phone | Yes (loop) | — | No — singleton via lock | Canonical |
| scripts/uom-dryrun.sh | Offline test suite | Laptop/Phone | No | — | Yes | Canonical |
| scripts/uom-phone-bootstrap.sh | Phone bootstrap orchestrator | Phone | No | — | Yes | Canonical |
| scripts/uom-lib.sh | Shared library (QEMU, guest, network helpers) | Laptop/Phone | No (sourced) | — | Yes | Canonical |
| scripts/uom-widget-lib.sh | Widget wrapper library | Phone | No (sourced) | — | Yes | Canonical |

## orchestrators/ — Long-running coordinators

| Path | Responsibility | Platform | Long-running | Ports | Safe concurrent | Status |
|------|---------------|----------|-------------|-------|----------------|--------|
| orchestrators/uom-reconcile.sh | Full reconciliation (tmux, model, health) | Laptop/Phone | No | — | No — idempotent | Canonical |
| orchestrators/uom-watchdog.sh | Laptop reachability + phone takeover | Phone | Yes (loop) | 31415 | No — singleton | Canonical |
| orchestrators/uom-tmux-watchdog.sh | Tmux session watchdog (merged from guardian) | Laptop/Phone | Yes (loop) | — | No — singleton via PID | Canonical |
| orchestrators/uom-solo-orchestrator.sh | Phone-only fallback orchestrator | Phone | Yes (loop) | — | No — singleton | Canonical |
| orchestrators/uom-port-guardian.sh | Dynamic port/host sentinel | Laptop/Phone | Yes (loop) | — | No — singleton via lock | Canonical |

## tools/ — Reusable primitives (sourced, not executed)

| Path | Responsibility | Can run directly | Status |
|------|---------------|----------------|--------|
| tools/uom-ip-discover.sh | IP discovery primitives (5 methods) | No (sourced) | Canonical |
| tools/uom-model-rotate.sh | Free model rotation with rate-limit handling | Yes | Canonical |
| tools/uom-net-detect.sh | Network topology detection | No (sourced) | Canonical |
| tools/uom-orch-laptop.sh | Laptop orchestrator logic | Yes | Canonical |
| tools/uom-orch-phone.sh | Phone orchestrator logic | Yes | Canonical |
| tools/uom-orch-state.sh | State management logic (schema v1) | Yes | Legacy — prefer uom-state-lib.sh |
| tools/uom-port-watch.sh | Port watch primitives | No (sourced) | Canonical |
| tools/uom-state-lib.sh | State library (schema v2, compare-and-update) | No (sourced) | Canonical |

## Caller/Callee Map (Zen Loop subsystem)

```
uom-reconcile.sh (entry point)
  ├── install/bootstrap-termux.sh --apply
  ├── bin/uom-reverse-ssh.sh start
  ├── bin/uom-port-guardian.sh status/start
  ├── tools/uom-model-rotate.sh (model selection)
  ├── scripts/uom-generator.sh (via tmux send-keys)
  └── scripts/uom-verifier.sh (via tmux send-keys)

uom-qemu-phone (QEMU launcher)
  └── scripts/uom-qemu-watchdog.sh (auto-started after QEMU launch)

uom-watchdog.sh (phone-side)
  ├── tools/uom-state-lib.sh
  ├── tools/uom-ip-discover.sh (IP drift detection)
  └── orchestrators/uom-solo-orchestrator.sh (on takeover)

uom-port-guardian.sh (laptop-side)
  ├── tools/uom-port-watch.sh (primitives)
  └── bin/uom-ssh-phone.sh (phone discovery)

uom-ssh-phone.sh (laptop→phone)
  ├── tools/uom-ip-discover.sh (discovery chain)
  └── .uom-agent/phone.ip (phone announce)

omni-project-start.sh (menu)
  ├── tools/uom-state-lib.sh (mode switching)
  ├── orchestrators/uom-reconcile.sh (hybrid mode)
  └── bin/uom-ssh-phone.sh (phone SSH)

scripts/uom-llm-remote.sh (remote LLM)
  ├── tools/uom-model-rotate.sh (model selection)
  └── bin/uom-ssh-phone.sh (phone→laptop LLM)
```

## Deleted (2026-07-18 refactor)

| File | Reason |
|------|--------|
| bin/uom-hybrid.sh | Broken wrapper — exec target did not exist |
| bin/uom-tmux-guardian.sh | Merged into orchestrators/uom-tmux-watchdog.sh |
| bin/uom-fix-connectivity.sh | Security risk — overwrote ~/.ssh/config |
| scripts/uom-final-fix.sh | Deprecated legacy |
| UOM-DUAL-AGENT/setup/* | Obsolete deployment artifacts (design doc kept) |
