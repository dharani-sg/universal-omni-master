# UOM Script Catalog

Reference: HEAD f34b633, tag v0.31.0-2026-07-17 (b958510).
Catalog date: 2026-07-17.

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
| bin/uom-port-guardian.sh | Dynamic port/host sentinel | Laptop/Phone | Yes (loop) | — | No — singleton via lock | Canonical |
| bin/uom-tmux-watchdog.sh | Tmux session watchdog | Laptop/Phone | Yes (loop) | — | No — singleton via PID | Canonical |
| bin/uom-tmux-guardian.sh | Tmux guardian (lower-level) | Laptop/Phone | Yes (loop) | — | No — overlaps with watchdog | Deprecated |
| bin/uom-hybrid.sh | Hybrid auto-orchestrator | Laptop | Yes (loop) | 31415 | No — singleton | Canonical |
| bin/uom-status.sh | Service status check | Laptop/Phone | No | 31415 | Yes | Canonical |
| bin/uom-resume.sh | Session resume assistant | Laptop | No | 31415 | Yes | Canonical |
| bin/uom-deploy-phone.sh | Deploy scripts to phone | Laptop | No | 31415 | Yes | Canonical |
| bin/uom-phone-provision.sh | Provision proot Debian + opencode on phone | Laptop | No | 31415 | Yes | Canonical |
| bin/uom-fix-connectivity.sh | Connectivity repair | Laptop/Phone | No | 31415 | No — can conflict with tunnel | Canonical |
| bin/uom-orchestrator.sh | Orchestrator wrapper | Phone | No | 31415 | Yes | Canonical |
| bin/uom-statectl.sh | State control | Laptop/Phone | No | — | Yes | Canonical |
| bin/create_omni_status_alias.sh | Create status alias | Laptop/Phone | No | 31415 | Yes | Canonical |
| bin/omni-orchestrator.sh | Omni orchestrator runner | Laptop/Phone | No | — | Yes | Canonical |
| bin/omni-orchestrator-monitor.sh | Orchestrator monitor | Laptop/Phone | No | 31415 | Yes | Canonical |

## scripts/ — Bounded operational tasks

| Path | Responsibility | Platform | Long-running | Ports | Safe concurrent | Status |
|------|---------------|----------|-------------|-------|----------------|--------|
| scripts/uom-reconcile.sh | 6-step Zen Loop reconciler | Laptop/Phone | No | 31415 | No — idempotent but only one | Canonical |
| scripts/uom-generator.sh | Cloud code generator (opencode) | Laptop/Phone | Yes (loop) | — | No — singleton via gen.lock | Canonical |
| scripts/uom-verifier.sh | Syntax/policy verifier | Laptop/Phone | Yes (loop) | — | No — singleton via ver.lock | Canonical |
| scripts/uom-proot-setup.sh | Cloud env verifier | Laptop/Phone | No | — | No — one-shot setup | Canonical |
| scripts/uom-final-fix.sh | Legacy fix script (port 31415, provision) | Phone | Yes (loop) | 31415 | No — overlaps with watchdog + tunnel | Deprecated |
| scripts/uom-dryrun.sh | Offline test suite | Laptop/Phone | No | — | Yes | Canonical |

## orchestrators/ — Long-running coordinators

| Path | Responsibility | Platform | Long-running | Ports | Safe concurrent | Status |
|------|---------------|----------|-------------|-------|----------------|--------|
| orchestrators/uom-solo-orchestrator.sh | Phone-only fallback orchestrator | Phone | Yes (loop) | — | No — singleton | Canonical |
| orchestrators/uom-watchdog.sh | Laptop reachability monitor | Phone | Yes (loop) | 31415 | No — singleton | Canonical |

## tools/ — Reusable primitives (sourced, not executed)

| Path | Responsibility | Can run directly | Status |
|------|---------------|----------------|--------|
| tools/uom-ip-discover.sh | IP discovery primitives | No (sourced) | Canonical |
| tools/uom-net-detect.sh | Network topology detection | No (sourced) | Canonical |
| tools/uom-orch-laptop.sh | Laptop orchestrator logic | Yes | Canonical |
| tools/uom-orch-phone.sh | Phone orchestrator logic | Yes | Canonical |
| tools/uom-orch-state.sh | State management logic | Yes | Canonical |
| tools/uom-port-watch.sh | Port watch primitives | No (sourced) | Canonical |
| tools/uom-state-lib.sh | State library | No (sourced) | Canonical |

## UOM-DUAL-AGENT/ — Historical dual-agent deployment artifacts

| Path | Status | Relationship |
|------|--------|-------------|
| UOM-DUAL-AGENT/uom-ip-discover.sh | Canonical (upstream copy) | Identical to tools/uom-ip-discover.sh |
| UOM-DUAL-AGENT/uom-net-detect.sh | Canonical (upstream copy) | Identical to tools/uom-net-detect.sh |
| UOM-DUAL-AGENT/uom-orch-laptop.sh | Divergent copy | Differs from tools/uom-orch-laptop.sh |
| UOM-DUAL-AGENT/uom-orch-phone.sh | Divergent copy | Differs from tools/uom-orch-phone.sh |
| UOM-DUAL-AGENT/uom-orch-state.sh | Divergent copy | Differs from tools/uom-orch-state.sh |
| UOM-DUAL-AGENT/setup/ | Historical deployment scripts | Compatibility artifact |
| UOM-DUAL-AGENT/setup/www/ | Phone ad-hoc deployment files | Served as www content |
| UOM-DUAL-AGENT/setup/www-root/ | Phone one-shot installer | go is the entry point |

## Caller/Callee Map (Zen Loop subsystem)

```
uom-reconcile.sh (entry point)
  ├── install/bootstrap-termux.sh --apply
  ├── bin/uom-reverse-ssh.sh start
  ├── bin/uom-port-guardian.sh status/start
  ├── scripts/uom-generator.sh (via tmux send-keys)
  └── scripts/uom-verifier.sh (via tmux send-keys)

uom-generator.sh
  ├── opencode --model opencode/deepseek-v4-flash-free
  └── .uom-agent/queue.json (read/write)

uom-verifier.sh
  ├── sh -n (syntax check)
  ├── scripts/uom-dryrun.sh (optional)
  └── .uom-agent/queue.json (write)
```

## Duplicate Detection Summary

- tools/uom-ip-discover.sh = UOM-DUAL-AGENT/uom-ip-discover.sh (exact duplicate, 2 copies)
- tools/uom-net-detect.sh = UOM-DUAL-AGENT/uom-net-detect.sh (exact duplicate, 2 copies)
- tools/uom-orch-laptop.sh != UOM-DUAL-AGENT/uom-orch-laptop.sh (divergent copies)
- tools/uom-orch-phone.sh != UOM-DUAL-AGENT/uom-orch-phone.sh (divergent copies)
- tools/uom-orch-state.sh != UOM-DUAL-AGENT/uom-orch-state.sh (divergent copies)
- UOM-DUAL-AGENT/setup/www/b.sh = bootstrap.sh-based (partial duplicate)
- bin/uom-tmux-guardian.sh overlaps with bin/uom-tmux-watchdog.sh (semantic overlap)
