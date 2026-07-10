#!/bin/sh
# freeze-profile.sh — capture live omni-detect output as a TOML hardware profile.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DETECT="$ROOT/bin/omni-detect"
PROFILES="$ROOT/config/profiles"

mkdir -p "$PROFILES"

# Capture live detection (JSON on stdout, logs on stderr)
JSON=$("$DETECT" 2>/dev/null)

# jq-free field extractor
jget() { printf '%s' "$JSON" | grep "\"$1\":" | head -n1 | sed 's/.*: "//; s/".*//' ; }

PROFILE_NAME="${1:-$(hostname)-$(date +%Y%m%d)}"
OUT="$PROFILES/$PROFILE_NAME.toml"

cat > "$OUT" << TOML
# Universal Omni-Master — Hardware Profile
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Host: $(hostname)

[hardware]
cpu_vendor      = "$(jget cpu_vendor)"
cpu_model       = "$(jget cpu_model)"
cpu_count       = $(jget cpu_count)
cpu_hybrid      = $(jget cpu_hybrid | sed 's/yes/true/; s/no/false/')
gpu_count       = $(jget gpu_count)
gpu_vendors     = "$(jget gpu_vendors)"
gpu_hybrid      = $(jget gpu_hybrid | sed 's/yes/true/; s/no/false/')
storage         = "$(jget storage)"
power_source    = "$(jget power_source)"

[software]
distro          = "$(jget distro)"
init            = "$(jget init)"
libc            = "$(jget libc)"
arch            = "$(jget arch)"
pkgmgr          = "$(jget pkgmgr)"
priv_helper     = "$(jget priv_helper)"
bootloader      = "$(jget bootloader)"
seat_model      = "$(jget seat_model)"

[policy]
ac_only_no_pm   = true
dgpu_default    = "unbound"
sata_ncq        = false
sata_link_speed = "3.0Gbps"
sata_crc_baseline = 5360

[policy.no_pm]
cpu_governor              = "performance"
snd_hda_intel_power_save  = 0
snd_hda_intel_controller  = "N"
wifi_power_save           = false
pcie_aspm                 = "off"
usb_autosuspend           = -1
TOML

echo "Profile written: $OUT"
cat "$OUT"
