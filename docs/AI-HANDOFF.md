# Universal Omni-Master — Durable AI Handoff (v0.26.0)

## Repository Identity
- Project root: ~/src/universal-omni-master
- Core language: POSIX #!/bin/sh (BusyBox ash-safe)
- TUI language: Fish 4.x only (--no-config)
- Reference host: Alpine Linux 3.24 (musl, OpenRC)
- Secondary host: Void Linux (glibc, runit)
- Hardware: HP Pavilion 15-n010tx (degraded SATA cable, UDMA_CRC baseline 5360)

## Immutable Rules
1. POSIX sh only. Zero bashisms. Zero eval. Zero set --.
2. Mutation guard: exit 126 when OMNI_SYSROOT set.
3. Never push on failing gate. Never rewrite tags.
4. Commit messages with $/{}/backticks use git commit -F file.
5. All file writes verified with sh -n + wc -l + tail -3.

## Sealed Milestones (M1-M26)
| Milestone | Tag | CLIs Added |
|---|---|---|
| M1-M6 | v0.1.0-v0.6.0 | detect, service, boot, gpu, storage, audit |
| M7-M12 | v0.7.2-v0.12.0 | deploy, healer, snapshot, tui |
| M13-M15 | v0.13.0-v0.15.0 | security, fleet (monolith, SSH, plugins) |
| M16-M20 | v0.16.0-v0.20.0 | state machine, adaptive UI, seed, manifests, livefeed |
| M21 | v0.21.0 | manager |
| M22 | v0.22.0 | (KVM testbed - library only) |
| M23-M23.1 | v0.23.0-v0.23.1 | saas |
| M24 | v0.24.1 | patcher |
| M25 | v0.25.0 | compliance |
| M26 | v0.26.0 | openclaw |

Total: 16 CLI tools, 260+ automated assertions.

## Bug History (DO NOT REPEAT)
1. set -- clobbers $@ (M12)
2. BusyBox sed \n mismatch
3. BusyBox dmesg no -w
4. _OMNI_ROOT= strip orphans guard clauses
5. Over-broad awk . pattern
6. Top-level return 1 = exit 1 in monolith
7. Heredoc truncation (17 incidents)
8. Unquoted AGE(s) metacharacters
9. Pipe-subshell background job orphaning
10. grep -c || printf 0 double-capture
11. if "$handler"; then swallows exit code
12. $$ in single-quoted heredocs
13. mkfifo + & process leaks
14. stty size overrides $COLUMNS
15. /dev/null is not a regular file ([ -f ] fails)
16. Mock PATH=$MOCKDIR vs $MOCKDIR/bin
17. Python re.subn \1 backreference in replacement

## Next Phase
M27: Termux Native Polish (haptic feedback, push notifications, portrait optimization)
M28+: Zero-trust networking, predictive healing, fleet AI orchestration

## Recovery Prompt
Read this file, then run:
  git status --short
  git log --oneline --decorate -10
  git tag --sort=-version:refname | head -20
Report: branch, commit, tags, dirty files, latest milestone, failing gates.
Never push unless all gates pass.
