# UOM Concurrency and Service Ownership

Reference: HEAD f34b633, tag v0.31.0-2026-07-17. Date: 2026-07-17.

## Conflict Matrix

| Component A | Component B | Shared Resource | Conflict | Protection | Status |
|------------|------------|----------------|----------|-----------|--------|
| uom-reverse-ssh.sh (instance 1) | uom-reverse-ssh.sh (instance 2) | Tunnel port 31415 | Duplicate tunnel | pidfile in runtime/ + pgrep guard | Singleton OK |
| uom-port-guardian.sh (start) | uom-port-guardian.sh (start) | SSH config rewrite | Race on ssh config | tmux session guard | Singleton OK |
| uom-tmux-watchdog.sh | uom-tmux-guardian.sh | Tmux session management | Both restart same sessions | No cross-guard — potential conflict | Needs resolution |
| uom-generator.sh (loop) | uom-generator.sh (loop 2) | gen.lock, gen.pid, queue.json | Duplicate generation | Lock file with stale PID recovery | Singleton OK |
| uom-verifier.sh (loop) | uom-verifier.sh (loop 2) | ver.lock, ver.pid, verified/ | Duplicate verification | Lock file with stale PID recovery | Singleton OK |
| uom-generator.sh | uom-verifier.sh | .ready / .done markers | Race on file state | Atomic write + mv | Acceptable |
| uom-reconcile.sh (step 5) | uom-hybrid.sh | Guardian startup | Both start guardian | Idempotent — status check first | Safe |
| uom-reconcile.sh (step 3) | uom-reverse-ssh.sh (phone) | Tunnel port 31415 | Duplicate tunnel start | pgrep guard + status check | Safe |
| uom-watchdog.sh | uom-solo-orchestrator.sh | Phone orchestration | Overlapping responsibility | Different triggers (heartbeat vs timer) | Acceptable |
| Cleanup traps (generator) | Cleanup traps (verifier) | State dir | PID file removal | Each removes own pid only | Safe |
| pkill -f 'uom-reverse-ssh' | SSH session using same process | Own SSH session | Self-kill | pkill patterns exclude own PID | Needs hardening |
| Stale PID file after reboot | Same service restart | Old pid in file | False "already running" | Stale PID detection + kill -0 | Safe |

## Canonical Owner per Long-Running Service

| Service | Canonical Owner | Fallback Owner | Start Mechanism |
|---------|----------------|----------------|-----------------|
| Reverse tunnel (31415) | uom-reverse-ssh.sh (phone) | uom-hybrid.sh (laptop) | Termux:Boot, manual, hybrid |
| Port guardian | uom-port-guardian.sh | uom-hybrid.sh _ensure_guardian | Termux:Boot, bootstrap-termux |
| Tmux session monitor | uom-tmux-watchdog.sh | (none) | Termux:Boot, manual --daemon |
| Zen generator loop | uom-generator.sh | (none) | uom-reconcile.sh step 5 |
| Zen verifier loop | uom-verifier.sh | (none) | uom-reconcile.sh step 5 |
| Phone solo orchestration | uom-solo-orchestrator.sh | (none) | watchdog triggers on timeout |
| Laptop watchdog | uom-watchdog.sh | (none) | Termux:Boot, manual |

## Safe Singleton Implementation Pattern

Every long-running script uses one of:
1. **PID file** + `kill -0` stale check (uom-generator.sh, uom-verifier.sh)
2. **tmux session** existence check (uom-port-guardian.sh)
3. **pgrep** for process name (uom-reconcile.sh tunnel check)

### Stale PID Recovery
```sh
if [ -f "$PID_FILE" ]; then
    _old=$(cat "$PID_FILE")
    if [ -n "$_old" ] && kill -0 "$_old" 2>/dev/null; then
        exit 0  # already running
    fi
    rm -f "$PID_FILE"
fi
echo "$$" > "$PID_FILE"
```

### Atomic File Write
All generated output uses temporary file + mv:
```sh
_tmp="${TARGET}.tmp.$$"
printf '...' > "$_tmp" && mv "$_tmp" "$TARGET"
```

## Design Rules

1. One canonical owner per long-running service.
2. Manual launchers must detect when a service manager already owns a process.
3. Entry points must be idempotent.
4. Avoid broad process-name killing (pkill without PID exclusions).
5. Prefer PID files with `kill -0` validation.
6. Prefer atomic mkdir locks (POSIX) rather than requiring flock.
7. Include stale lock/pid handling.
8. Use host-specific state when state could be copied between laptop and phone.
9. Write generated files to temp file and atomically move into place only after verification.
10. Do not replace a valid generated target with failed or empty output.
11. Bound retries and use controlled backoff.
12. Prevent nested or duplicate Zen loops.
13. Keep logs separated by component and host when simultaneous execution is possible.
14. Ensure cleanup removes only state owned by the current process.
15. Preserve the 127.0.0.1 tunnel binding.
16. Preserve port 31415 as the only active standard.
