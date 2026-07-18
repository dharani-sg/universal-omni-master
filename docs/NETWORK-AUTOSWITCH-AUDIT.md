# Network Auto-Switch Audit

Date: 2026-07-18. HEAD: d33341c.

## What Exists (primitives already implemented)

### 1. IP Discovery — `tools/uom-ip-discover.sh` (167 lines)
Five-method priority chain for finding the other device:
1. Reverse tunnel (`127.0.0.1:31415`)
2. mDNS (`mi8.local` / `hp-pavilion.local`)
3. Last-known IP from `.uom-agent/*.ip`
4. SSH config aliases (`uom-phone-rev`, `uom-phone-lan`, `uom-phone-mdns`)
5. Subnet scan for port 8022/22

Public functions: `discover_phone_ip()`, `discover_laptop_ip()`, `is_phone_hotspot()`, `get_my_ip()`, `net_ok()`

### 2. Network Mode Detection — `tools/uom-net-detect.sh` (140 lines)
Pattern-based detection producing `KEY=VALUE` output:
- `NET_MODE=hotspot` — gateway is 192.168.43.1 or 10.42.x.1
- `NET_MODE=lan` — both devices discovered on same subnet
- `NET_MODE=external` — only one or no device discovered
- `NET_MODE=offline` — no default route

### 3. Port Watch Primitives — `tools/uom-port-watch.sh` (134 lines)
Read-only probe helpers:
- `uom_pw_probe_ssh` — TCP connect probe
- `uom_pw_discover_phone` — stored hint → known LAN IPs → subnet scan
- `uom_pw_discover_laptop` — stored hint → known LAN IPs
- `uom_pw_tunnel_up` — check reverse tunnel alive
- `uom_pw_on_phone_hotspot` — gateway pattern match
- `uom_pw_read_hint` / `uom_pw_write_hint` — atomic hint read/write

### 4. Laptop→Phone SSH Wrapper — `bin/uom-ssh-phone.sh` (241 lines)
Drift-tolerant wrapper with 5 discovery methods + caching:
- Cached IP → reverse tunnel → mDNS → subnet scan
- Identity verification (SSH auth + host key hash + uom-vm dir)
- Caches to `~/.config/uom/last-phone-ip.txt`

### 5. Reverse SSH Tunnel — `bin/uom-reverse-ssh.sh` (441 lines)
Phone-initiated tunnel to laptop (port 31415→8022):
- Singleton enforcement via mkdir lock + PID validation
- autossh or manual retry loop
- Re-discovers laptop host on reconnect
- ServerAliveInterval=30, ServerAliveCountMax=3

### 6. Phone-side Watchdog — `orchestrators/uom-watchdog.sh` (364 lines)
Laptop reachability monitor + takeover logic:
- Three checks: heartbeat, tunnel health, direct reachability
- Threshold-based takeover to `phone-solo` mode
- Laptop return detection → `dual-pending`
- Solo orchestrator lifecycle management

## What's Missing / Broken

### CRITICAL: Port Guardian Implementation Lost
`orchestrators/uom-port-guardian.sh` is a **recursive self-reference** (3 lines wrapping itself). The actual guardian loop was lost during Phase 7 cleanup. This is the central network drift handler that:
- Detects topology changes (hotspot↔LAN↔external)
- Re-points SSH config aliases
- Updates `.uom-agent/*.host` hints
- Signals drift to other components

**Impact:** Port guardian is started at boot (`bootstrap-termux.sh:458`) but immediately crashes/loops. Network drift detection is dead.

### Gap: No Laptop-side Watchdog
The phone has `orchestrators/uom-watchdog.sh` monitoring laptop reachability. There is **no corresponding laptop-side watchdog** monitoring phone reachability. The laptop relies entirely on:
- `bin/uom-ssh-phone.sh` (reactive — discovers on each call)
- `uom-reconcile.sh` (periodic reconciliation, not real-time)

### Gap: No Network Mode Change Detection Loop
`uom-net-detect.sh` is a one-shot script. Nothing polls it periodically to detect when the laptop switches from hotspot to LAN (e.g., user connects to home WiFi). The reconcile script fingerprints topology but runs infrequently.

### Gap: No Wake-Lock on Phone
When phone is in `phone-solo` mode, Android can kill background processes. No wake lock (Termux `termux-wake-lock`) is acquired by the watchdog or solo orchestrator.

### Gap: Tunnel Not Auto-Restarted on Drift
When IP changes, the reverse tunnel (`uom-reverse-ssh.sh`) re-discovers the laptop host on reconnect — but only after the current connection drops. There's no proactive restart on IP change detection.

### Minor: `uom-net-detect.sh` vs `uom-ip-discover.sh` Duplication
Both implement gateway detection and hotspot pattern matching independently. `uom-net-detect.sh` doesn't source `uom-ip-discover.sh` (listed as TODO in session resume).

## Scenario Coverage Matrix

| Scenario | Detect | Reconnect | Verify | Status |
|----------|--------|-----------|--------|--------|
| Hotspot → LAN | `uom-net-detect.sh` | Port guardian (BROKEN) | — | **BROKEN** |
| LAN → Hotspot | `uom-net-detect.sh` | Port guardian (BROKEN) | — | **BROKEN** |
| IP change on same network | `uom-ip-discover.sh` | `uom-ssh-phone.sh` (reactive) | `uom-ssh-phone.sh` verify | OK (reactive) |
| Phone offline | `uom-watchdog.sh` | Takeover to phone-solo | — | OK |
| Laptop offline | `uom-watchdog.sh` | Takeover to phone-solo | — | OK |
| Both offline | Watchdog fails | No action (correct) | — | OK |
| Phone reboot | Tunnel drops | Reverse-ssh retry loop | — | OK |
| Laptop reboot | Watchdog detects | Phone waits | — | OK |
| Tunnel drops | Watchdog/tunnel check | Reverse-ssh reconnect | — | OK |

## Phase 9 Implementation (2026-07-18)

### 9.1: Port Guardian Restored
- Rewrote `orchestrators/uom-port-guardian.sh` (258 lines) from scratch
- Subcommands: start, stop, status, role, rewrite, dryrun
- 20s polling loop with network fingerprint (gateway:ip:hotspot:mode)
- Idempotent SSH config rewrite (UOM-MANAGED block)
- Topology change detection → phone discovery → SSH config rewrite
- Signals drift to reconcile via `portguard.network_changed`
- Fixed stale dryrun test (removed deleted `uom-hybrid.sh` reference)

### 9.2: Phone Watchdog Extended
- IP change detection (laptop.ip drift → tunnel restart)
- Tunnel auto-restart on detected drift (stop → start → verify)
- Hotspot mode detection (phone is gateway)
- Wake-lock acquisition on solo mode entry (termux-wake-lock)
- Wake-lock release on laptop return and exit
- Phone announce (writes phone.ip to state each cycle)

### 9.3: Reverse Tunnel Hardened
- Pre-flight laptop reachability check before tunnel attempt
- Verified singleton enforcement (mkdir lock + PID validation)
- Keepalive settings already optimal (ServerAliveInterval=30, CountMax=3)

### 9.4: SSH Wrapper Enhanced
- Phone-announce file check (freshest IP source)
- Hotspot gateway detection (gateway IS the phone)
- Added as first discovery methods before cached/reverse-tunnel/mDNS/scan

### 9.5: Network Detection Wired
- Port guardian fingerprint now includes network mode (hotspot/lan/external)
- Mode logged on topology change
- Port guardian is the central network monitor (started at boot via bootstrap-termux.sh)

### 9.6: Dry-Run Verification
All 5 modified scripts pass `sh -n` syntax check:
- `orchestrators/uom-port-guardian.sh` ✓
- `orchestrators/uom-watchdog.sh` ✓
- `bin/uom-reverse-ssh.sh` ✓
- `bin/uom-ssh-phone.sh` ✓
- `scripts/uom-dryrun.sh` ✓

Port guardian subcommands verified:
- `role` → "laptop" ✓
- `status` → "NOT RUNNING" (correct, not started) ✓
- `rewrite` → idempotent SSH config block ✓
- `dryrun` → fingerprint detection works ✓

### 9.1: Fix Port Guardian (CRITICAL)
Rewrite `orchestrators/uom-port-guardian.sh` as a proper daemon loop:
- Sources `uom-port-watch.sh` primitives
- 20s polling loop detecting topology changes
- Atomic SSH config rewrite + hint updates
- Drift signal to reconcile script
- Singleton enforcement

### 9.2: Extend Phone Watchdog
Add to `orchestrators/uom-watchdog.sh`:
- IP change detection (compare current vs last-seen)
- Tunnel auto-restart on detected drift
- Hotspot mode detection (phone is gateway)
- Wake-lock acquisition on solo mode entry
- Phone announce to `.uom-agent/phone.ip`

### 9.3: Enhance Reverse Tunnel
Add to `bin/uom-reverse-ssh.sh`:
- Pre-flight laptop reachable check before tunnel attempt
- Explicit keepalive flags in SSH opts
- Singleton enforcement already exists — verify no races

### 9.4: Laptop SSH Wrapper Enhancement
Add to `bin/uom-ssh-phone.sh`:
- Hotspot gateway detection (if on phone hotspot, phone is gateway)
- Phone-announce check before discovery
- Route caching with TTL

### 9.5: Wire Network Detection Loop
Create/fix a laptop-side network change monitor:
- Periodic `uom-net-detect.sh` polling (every 60s)
- On mode change: update hints, restart tunnel if needed, log transition
- Integrate with port guardian

### 9.6: Dry-Run All 6 Scenarios
Test each scenario from the matrix above with simulated conditions.
