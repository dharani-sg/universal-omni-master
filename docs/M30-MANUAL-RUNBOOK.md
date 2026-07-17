# M30 Manual Runbook — Termux Native Polish

## Quick Reference

| Situation | Command |
|---|---|
| Check current state | `jq . .uom-agent/state.json` |
| Check tunnel | `ssh -o ConnectTimeout=3 -p 31415 127.0.0.1 true && echo UP \|\| echo DOWN` |
| Check phone SSH | `ssh -o ConnectTimeout=3 -p 8022 u0_a608@127.0.0.1 echo ok` |
| Start reverse tunnel | `sh bin/uom-reverse-ssh.sh` |
| Start dashboard | `sh bin/omni-project-start.sh` |
| Start guardian | `sh bin/uom-tmux-guardian.sh` |
| Force phone-solo | `jq '.active_agent="phone-solo" \|.writer_role="phone" \|.takeover_count=1' .uom-agent/state.json > /tmp/s.json && mv /tmp/s.json .uom-agent/state.json` |
| Force dual mode | `jq '.active_agent="dual" \|.writer_role="laptop"' .uom-agent/state.json > /tmp/s.json && mv /tmp/s.json .uom-agent/state.json` |
| Run dry-run tests | `sh scripts/uom-dryrun.sh` |
| Check logs | `ls -la .uom-agent/logs/` |

## Architecture

```
LAPTOP (Alpine Linux)                    PHONE (Xiaomi Mi 8 / Termux)
┌─────────────────────────┐             ┌─────────────────────────┐
│  omni-project-start.sh  │             │  uom-reverse-ssh.sh     │
│  └─ TUI menu            │             │  └─ -R 31415:localhost:  │
│  └─ status / start /    │   SSH :8022 │     8022 → laptop       │
│     stop / health       │◄────────────│                         │
│                         │  Tunnel     │  uom-tmux-guardian.sh   │
│  uom-watchdog.sh        │  :31415     │  └─ auto-restart tmux   │
│  └─ heartbeat monitor   │────────────►│                         │
│  └─ tunnel liveness     │             │  uom-statectl.sh        │
│                         │             │  └─ state transitions   │
│  state.json (schema v2) │             │  └─ ownership epoch     │
│  └─ active_agent        │             │                         │
│  └─ ownership_epoch     │             │  state.json (replicated)│
│  └─ task_status         │             │                         │
└─────────────────────────┘             └─────────────────────────┘
```

## State Machine

### Modes

| Mode | Description | Task Writer |
|---|---|---|
| `dual` | Both laptop and phone active | laptop (with valid lease) |
| `phone-solo` | Phone only (laptop unreachable) | phone |
| `dual-pending` | Laptop returned, awaiting confirmation | none (both denied) |

### Transitions

```
dual ──(heartbeat stale + tunnel down + phone unreachable)──► phone-solo
phone-solo ──(laptop reachable + idle)──► dual-pending
phone-solo ──(laptop reachable + task in progress)──► dual-pending (with checkpoint)
dual-pending ──(laptop confirms via compare_and_update)──► dual
```

### Ownership Epoch

The `ownership_epoch` counter prevents split-brain. Each successful `compare_and_update` increments it. Operations that read-then-write must pass the current epoch; if it changed, the operation is rejected.

```
Initial: epoch=0
Laptop confirms dual: epoch=1 (compare_and_update with epoch=0)
Laptop confirms again: epoch=2 (compare_and_update with epoch=1)
```

## Manual Interventions

### Force Phone-Solo Mode

When the laptop is unreachable and the phone needs to work independently:

```sh
cd ~/src/universal-omni-master
jq '.active_agent="phone-solo" | .writer_role="phone" | .takeover_count=1 | .last_transition="manual-force" | .last_transition_at="'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"' \
  .uom-agent/state.json > /tmp/s.json && mv /tmp/s.json .uom-agent/state.json
```

### Force Dual Mode (Laptop Recovery)

When returning from phone-solo and the laptop is back:

```sh
cd ~/src/universal-omni-master
jq '.active_agent="dual" | .writer_role="laptop" | .lease_expires_epoch='"$(($(date -u +%s) + 86400))"' | .last_transition="manual-restore" | .last_transition_at="'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"' \
  .uom-agent/state.json > /tmp/s.json && mv /tmp/s.json .uom-agent/state.json
```

### Reset Stuck Task

If a task is stuck in `in_progress` after a crash:

```sh
cd ~/src/universal-omni-master
jq '.task_status="pending" | .current_task_id="RETRY-" + .current_task_id' \
  .uom-agent/state.json > /tmp/s.json && mv /tmp/s.json .uom-agent/state.json
```

### Clear Ownership Epoch (Nuclear Option)

Only use when split-brain is confirmed and both sides are confused:

```sh
cd ~/src/universal-omni-master
jq '.ownership_epoch=0 | .active_agent="dual" | .writer_role="laptop" | .lease_id="" | .lease_expires_epoch=0' \
  .uom-agent/state.json > /tmp/s.json && mv /tmp/s.json .uom-agent/state.json
```

## Recovery Procedures

### Abrupt Power Loss (Laptop)

1. Phone detects stale heartbeat → transitions to `phone-solo`
2. Phone processes tasks independently
3. Laptop boots back up
4. Run `sh bin/uom-resume.sh` on laptop
5. If phone shows `dual-pending`, laptop confirms with `compare_and_update`
6. State returns to `dual`

### Tunnel Down

1. Check tunnel: `ssh -o ConnectTimeout=3 -p 31415 127.0.0.1 true`
2. If down, start on phone: `sh bin/uom-reverse-ssh.sh`
3. If autossh not available, use the manual loop in `bin/uom-reverse-ssh.sh`
4. Watchdog will detect recovery and transition back to `dual`

### Phone Unreachable

1. Check phone SSH: `ssh -o ConnectTimeout=3 -p 8022 u0_a608@127.0.0.1 echo ok`
2. If unreachable, check WiFi/hotspot on phone
3. If phone is in `phone-solo`, laptop waits for reconnection
4. Once phone is reachable, state transitions through `dual-pending` → `dual`

### State File Corrupt

1. Detect: `jq empty .uom-agent/state.json` (will fail)
2. Backup: `cp .uom-agent/state.json .uom-agent/state.json.corrupt.$(date +%s)`
3. Reset: `sh -c '. tools/uom-state-lib.sh && uom_state_init'`
4. Verify: `jq . .uom-agent/state.json`

## Configuration Files

| File | Purpose |
|---|---|
| `.uom-agent/state.json` | Primary state (schema v2) |
| `.uom-agent/queue.json` | Task queue |
| `.uom-agent/done.json` | Completed tasks |
| `.uom-agent/runtime/*.heartbeat` | Agent heartbeats (epoch) |
| `.uom-agent/runtime/*.heartbeat.log` | Heartbeat history |
| `.uom-agent/logs/state-lib.log` | State library operations |
| `.uom-agent/logs/watchdog.log` | Watchdog decisions |
| `.uom-agent/opencode-install.json` | Bootstrap metadata |
| `install/secrets.env` | Secrets (never committed) |

## Ports

| Port | Protocol | Direction | Purpose |
|---|---|---|---|
| 8022 | SSH | Phone inbound | Phone sshd (Termux) |
| 31415 | SSH tunnel | Phone → Laptop | Reverse tunnel for laptop access |

## Troubleshooting

### "compare-and-update rejected: expected epoch=X, got=Y"

Another agent incremented the epoch between your read and write. Retry after reading the current state.

### "compare-and-update rejected: expected mode=X, got=Y"

The state mode changed since you last checked. The operation is stale. Re-evaluate before retrying.

### Watchdog keeps logging "Heartbeat stale"

Check that the laptop orchestrator is running: `ps aux | grep uom-orch-laptop`. If not, start it.

### Phone shows "dual-pending" permanently

The laptop hasn't confirmed the transition. On the laptop, run:
```sh
sh -c '. tools/uom-state-lib.sh && uom_state_init && uom_state_compare_and_update dual-pending $(jq -r .ownership_epoch .uom-agent/state.json) '"'"'.active_agent = "dual" | .writer_role = "laptop" | .lease_expires_epoch = 9999999999'"'"''
```

### Dry-run tests fail

Run `sh scripts/uom-dryrun.sh` and check for FAIL lines. Most issues are:
- Bare `/tmp` writes (use `${TMPDIR:-/tmp}` or `mktemp`)
- Missing `unset _UOM_STATE_LIB_LOADED` before re-sourcing state-lib
- Port mismatches (8022 for sshd, 31415 for tunnel)

## OpenCode Verify-First

The `install/bootstrap-termux.sh` script uses a check-first approach:

```sh
# Check mode (default): read-only, reports what would be done
sh install/bootstrap-termux.sh

# Apply mode: actually makes changes
sh install/bootstrap-termux.sh --apply

# With third-party OpenCode allowed
sh install/bootstrap-termux.sh --apply --allow-third-party-opencode
```

Installation priority:
1. Already installed (P0)
2. Termux package (P1)
3. npm opencode-ai (P2)
4. Third-party binary (P3, requires flag)
5. proot-distro (P4, requires flag)
6. Remote laptop fallback via SSH tunnel (P5)

## Guarded Push

Git push is gated behind `UOM_ALLOW_PUSH=1`:

```sh
# Push is silent no-op by default
git push origin main  # silently skipped

# Enable push
UOM_ALLOW_PUSH=1 git push origin main  # actually pushes
```
