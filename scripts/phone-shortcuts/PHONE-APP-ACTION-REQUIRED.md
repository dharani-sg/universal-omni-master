# PHONE-APP-ACTION-REQUIRED.md

## Manual actions required before full phone-only operation

### 1. Install Termux:Widget (REQUIRED)
- **Source:** Google Play (MUST be same source as Termux — both Google Play builds)
- **Action:** Install Termux:Widget from Google Play, open once, add home-screen widget
- **Why:** Widget scripts in `~/.shortcuts/` only appear on the home screen after widget is added
- **Status:** NOT YET INSTALLED

### 2. Termux Battery Settings
- Settings → Apps → Termux → Battery → **Unrestricted**
- Allows Termux:Boot and QEMU to run in background without Android killing them

### 3. Termux Notifications
- Allow Termux to show notifications (for background task awareness)

### 4. Termux:Boot (Future Phase 12)
- Install Termux:Boot from Google Play (same source)
- Enables auto-start of QEMU + Zen on phone reboot
- NOT required for current Phase 9.5

### 5. GitHub Deploy Key (Future Phase 9.5C)
- Generate guest SSH key for GitHub push access
- Add as deploy key on GitHub repo
- Until authorized: read-only fetch OK (if repo is public)

## Widget Script Inventory

| Script | Type | Purpose |
|--------|------|---------|
| 00-UOM-Status | foreground | Quick status check |
| 20-UOM-Guest-Shell | foreground | SSH into Alpine guest |
| 30-UOM-Zen-Console | foreground | Zen Loop console in guest |
| 40-UOM-Host-Console | foreground | Host QEMU console |
| 50-UOM-Logs | foreground | View logs (tail) |
| 90-UOM-Stop | foreground | Clean shutdown (requires STOP confirmation) |
| tasks/10-UOM-Start | background | Start QEMU + verify guest |

## Status

- [x] Scripts written to `~/.shortcuts/`
- [ ] Termux:Widget installed from Google Play
- [ ] Widget added to home screen
- [ ] Widget taps verified working
- [ ] Battery set to Unrestricted
