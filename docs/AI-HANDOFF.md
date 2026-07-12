# Universal Omni-Master — AI Fail-Safe Handoff (v0.12.0+)

## Current State (July 2026)
- Latest sealed tag: v0.12.0 (M12 Fish TUI complete)
- M13-A monolith bundler: v0.13.0-a2 (fixing 3 gate failures from a1)
- Total green tests: M12=14, M11-audit=7, M10=20, M1-M9=all pass
- Hardware: HP Pavilion 15-n010tx (Alpine musl/OpenRC, Void glibc/runit)
- SATA baseline: UDMA_CRC=5360 (stable, NOT a failure)

## Immutable Rules
- POSIX sh only (BusyBox-ash safe, zero bashisms, zero eval)
- Fish ONLY for TUI, run via fish --no-config
- Mutation guard: exit 126 when OMNI_SYSROOT is set
- Non-Btrfs = graceful skip (return 0)
- Root subvol = @root; snapshots = @snapshots
- Restore = staged RW clone + boot entry, NEVER btrfs set-default
- NEVER push if any gate fails
- NEVER rewrite existing tags
- NEVER use set -- to parse version strings (clobbers $@)

## Known Bug History (avoid repeating)
- set -- clobbers $@ in bin/omni-tui (traced conversation 15+)
- set -u at monolith top level crashes on library unbound vars
- BusyBox sed does not interpret \n in replacements
- BusyBox dmesg has no -w flag (use poll-diff)
- Heredoc truncation on long terminal pastes (use block-write)

## Gate Commands
- sh -n <file> (POSIX), fish --no-config --no-execute <file> (Fish)
- M12: fish scripts/test-m12-tui.fish
- M11: ./scripts/audit-m11.sh
- M13: ./scripts/test-m13-monolith.sh

## Recovery Prompt
Read docs/AI-HANDOFF.md then run:
  git status --short
  git log --oneline --decorate -10
  ls -1 scripts/test-*.sh
Report: (1) branch/commit/tag, (2) dirty files, (3) latest milestone,
(4) failing gates, (5) proposed minimal patch.
Never push unless all gates pass. Never rewrite tags. Never use eval.
