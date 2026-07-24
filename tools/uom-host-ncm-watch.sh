#!/bin/sh
# Host-side observer for Dipper L0 NCM T1.
# Watches USB enumeration, brings up the NCM/RNDIS interface, pings the phone.
#
# Usage:
#   tools/uom-host-ncm-watch.sh          # watch forever (Ctrl-C)
#   tools/uom-host-ncm-watch.sh 180      # watch up to 180s then exit
set -u

TIMEOUT="${1:-0}"
PHONE_IP="${PHONE_IP:-172.16.42.1}"
HOST_IP="${HOST_IP:-172.16.42.2}"
LOG="${LOG:-/tmp/uom-host-ncm-watch.log}"
# Google gadget VID/PID used by T1 + stock pmOS
WANT_VID="${WANT_VID:-18d1}"
WANT_PID="${WANT_PID:-d001}"

ts() { date '+%H:%M:%S'; }
log() { echo "[$(ts)] $*" | tee -a "$LOG"; }

: >"$LOG"
log "=== UOM host NCM watch start (timeout=${TIMEOUT}s) ==="
log "expect VID:PID ${WANT_VID}:${WANT_PID}  phone=$PHONE_IP host=$HOST_IP"

START=$(date +%s)
SEEN_USB=0
SEEN_IF=0
IFACE=""

pick_iface() {
	# Prefer interfaces that appeared recently and look like USB net
	for c in /sys/class/net/*; do
		n=$(basename "$c")
		case "$n" in
		lo | eth0 | wlan* | docker* | br* | veth* | virbr* | tailscale* | tun* | tap*) continue ;;
		esac
		# usb / enx / enp*s*u* (usb) / rndis
		if echo "$n" | grep -Eq '^(usb|rndis|enx)'; then
			echo "$n"
			return 0
		fi
		# driver is cdc_ncm / rndis_host
		drv=$(readlink -f "$c/device/driver" 2>/dev/null || true)
		case "$drv" in
		*cdc_ncm* | *rndis_host* | *cdc_ether*)
			echo "$n"
			return 0
			;;
		esac
	done
	return 1
}

configure_iface() {
	_if="$1"
	log "configuring $_if -> $HOST_IP/24"
	# try ip, fall back to ifconfig
	if command -v ip >/dev/null 2>&1; then
		ip link set "$_if" up 2>/dev/null || true
		ip addr flush dev "$_if" 2>/dev/null || true
		ip addr add "$HOST_IP/24" dev "$_if" 2>/dev/null || true
	else
		ifconfig "$_if" "$HOST_IP" netmask 255.255.255.0 up 2>/dev/null || true
	fi
	# dhcp client optional (unudhcpd on phone)
	if command -v busybox >/dev/null 2>&1; then
		busybox udhcpc -i "$_if" -n -q -t 3 2>/dev/null || true
	fi
}

while :; do
	NOW=$(date +%s)
	if [ "$TIMEOUT" -gt 0 ] && [ $((NOW - START)) -ge "$TIMEOUT" ]; then
		log "timeout reached (${TIMEOUT}s)"
		break
	fi

	# USB gadget device?
	if lsusb 2>/dev/null | grep -qi "${WANT_VID}:${WANT_PID}"; then
		if [ "$SEEN_USB" -eq 0 ]; then
			SEEN_USB=1
			log "USB GADGET ENUMERATED: $(lsusb | grep -i "${WANT_VID}:${WANT_PID}")"
			dmesg 2>/dev/null | tail -20 | while read -r line; do log "dmesg: $line"; done
		fi
	fi

	# any new interesting USB?
	if lsusb 2>/dev/null | grep -Eiq '18d1|xiaomi|linux foundation.*gadget|cdc|ncm|rndis'; then
		log "usb: $(lsusb | grep -Ei '18d1|xiaomi|gadget|cdc|ncm|rndis' | tr '\n' ' ; ')"
	fi

	IFACE=$(pick_iface || true)
	if [ -n "$IFACE" ]; then
		if [ "$SEEN_IF" -eq 0 ] || [ "$IFACE" != "${LAST_IF:-}" ]; then
			SEEN_IF=1
			LAST_IF="$IFACE"
			log "NET IFACE: $IFACE"
			configure_iface "$IFACE"
			if command -v ip >/dev/null 2>&1; then
				log "addr: $(ip -4 addr show dev "$IFACE" 2>/dev/null | tr '\n' ' ')"
			fi
		fi
		if ping -c 1 -W 1 "$PHONE_IP" >/dev/null 2>&1; then
			log "PING OK $PHONE_IP via $IFACE — NCM/RNDIS PATH LIVE"
			log "try: ssh user@$PHONE_IP   or   ssh root@$PHONE_IP"
			# keep interface up; exit success if timeout mode, else continue
			if [ "$TIMEOUT" -gt 0 ]; then
				log "SUCCESS"
				exit 0
			fi
		fi
	fi

	sleep 1
done

log "summary: SEEN_USB=$SEEN_USB SEEN_IF=$SEEN_IF IFACE=${IFACE:-none}"
if [ "$SEEN_USB" -eq 1 ] && [ "$SEEN_IF" -eq 1 ]; then
	exit 0
fi
exit 1
