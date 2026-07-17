#!/bin/sh
# security/uom-firewall.sh — nftables ruleset for UOM laptop
# Allows: SSH(22), reverse tunnel(31415), established, loopback
# Drops: all other inbound
# Run as root: doas sh security/uom-firewall.sh

set -u

_log() { printf '[uom-fw] %s\n' "$*"; }

if ! command -v nft >/dev/null 2>&1; then
    _log "nftables not found — install with: doas apk add nftables"
    exit 1
fi

_log "Flushing existing ruleset..."
doas nft flush ruleset

_log "Loading UOM firewall ruleset..."
doas nft -f - << 'RULES'
table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    iif lo accept
    ct state established,related accept
    tcp dport 22 accept
    tcp dport 31415 accept
    icmp type echo-request accept
    icmpv6 type { echo-request, nd-neighbor-solicit, nd-router-advert } accept
  }
  chain forward {
    type filter hook forward priority 0; policy drop;
  }
  chain output {
    type filter hook output priority 0; policy accept;
  }
}
RULES

_log "Firewall rules loaded:"
doas nft list ruleset

_log ""
_log "To make persistent: doas rc-update add nftables default"
_log "Config saved at /etc/nftables.d/uom.nft (if using include)"
