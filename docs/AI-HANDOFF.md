# Universal Omni-Master — AI Fail-Safe Handoff (v0.12.0)

## Current State (July 2026)
- Latest tag: v0.12.0 (M12 Fish TUI + M11.1 staged rollback)
- Total tests: 231/231 green
- Hardware: HP Pavilion 15-n010tx (Alpine musl/OpenRC primary, Void glibc/runit dual-boot)
- Known quirks: degraded SATA cable (baseline UDMA_CRC=5360 — NOT a failure), muxless AMD HAINAN dGPU, AC-only power

## Immutable Rules (NEVER violate)
- Core = POSIX `#!/bin/sh`, BusyBox-ash safe, zero bashisms, zero `eval`.
- Fish ONLY for TUI, always launched with `fish --no-config`.
- Mutation guard: any state change MUST return 126 when OMNI_SYSROOT is set.
- Btrfs non-Btrfs = graceful skip (return 0), never hard-fail.
- Root subvol convention = `@root`; snapshots container = `@snapshots`.
- Restore MUST use staged RW clone + boot entry, NEVER `btrfs subvolume set-default`.
- Restore/apply require typed target name + literal `APPLY` or `RESTORE` (double confirmation).
- NEVER push if any gate fails.
- NEVER rewrite or move existing tags.
- NEVER claim a command ran without showing terminal output.

## Gate Commands (run exactly)
- POSIX: `sh -n <file>`
- Fish: `fish --no-config --no-execute <file>`
- Full M12: `fish --no-config scripts/test-m12-tui.fish`
- M11 audit: `./scripts/audit-m11.sh`
- All regressions: run test-*.sh for m1-m11

## Current Blockers (update on every handoff)
- None — M12 gate v4 clean, v0.12.0 pushed, M11.1 hardened.

## Recovery Prompt for Any New Agent
Read docs/AI-HANDOFF.md then run:
git status --short
git log --oneline --decorate -10
ls -1 scripts/test-*.sh
Do NOT modify files yet. First report:
1. current branch/commit/latest tag
2. dirty files
3. latest COMPLETE milestone
4. which gates fail
5. proposed minimal patch
Never push or tag unless every listed gate passes. Never rewrite tags. Never use eval.
