#!/bin/busybox ash
# UOM Dipper L0 — NCM T1 init
# Exact pmOS configfs NCM sequence + diagnostics. ABL is the only watchdog.
# No ACM. No software watchdog timer.
set -a

LOG=/tmp/uom-diag.log
KMSG=/dev/kmsg
CONFIGFS=/sys/kernel/config/usb_gadget
GADGET_DIR=$CONFIGFS/g1
HOST_IP=172.16.42.1
CLIENT_IP=172.16.42.2
TEST_ID="UOM-DIPPER-NCM-T1-$(date +%s 2>/dev/null || echo 0)"
NET_FN="ncm.usb0"
NET_FN_FALLBACK="rndis.usb0"

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

kmsg() {
	TS=$(cut -d. -f1 /proc/uptime 2>/dev/null || echo "?")
	echo "<6>[   ${TS}] [diag] $*" >"$KMSG" 2>/dev/null
	echo "[diag] $*" >>"$LOG" 2>/dev/null
}

die() {
	kmsg "FATAL: $*"
	kmsg "attempting reboot fallback chain"
	echo b >/proc/sysrq-trigger 2>/dev/null
	sleep 2
	echo o >/proc/sysrq-trigger 2>/dev/null
	sleep 2
	sync
	reboot -f 2>/dev/null
	sleep 5
	echo b >/proc/sysrq-trigger 2>/dev/null
	sleep 30
	while :; do :; done
}

clear_gadget() {
	[ -d "$GADGET_DIR" ] || return 0
	kmsg "clearing stale gadget g1"
	if [ -e "$GADGET_DIR/UDC" ] && [ -n "$(cat "$GADGET_DIR/UDC" 2>/dev/null)" ]; then
		echo "" >"$GADGET_DIR/UDC" 2>/dev/null || true
	fi
	rm -f "$GADGET_DIR/configs/c.1/$NET_FN" 2>/dev/null
	rm -f "$GADGET_DIR/configs/c.1/$NET_FN_FALLBACK" 2>/dev/null
	rmdir "$GADGET_DIR/configs/c.1/strings/0x409" 2>/dev/null || true
	rmdir "$GADGET_DIR/configs/c.1" 2>/dev/null || true
	rmdir "$GADGET_DIR/functions/$NET_FN" 2>/dev/null || true
	rmdir "$GADGET_DIR/functions/$NET_FN_FALLBACK" 2>/dev/null || true
	rmdir "$GADGET_DIR/strings/0x409" 2>/dev/null || true
	rmdir "$GADGET_DIR" 2>/dev/null || true
}

kmsg "=== UOM DIPPER L0 NCM T1 ==="
kmsg "Test-ID: $TEST_ID"

# busybox applets (stock pmOS does this)
if [ -x /bin/busybox ]; then
	/bin/busybox --install -s 2>/dev/null || true
fi
if [ -x /bin/busybox-extras ]; then
	/bin/busybox-extras --install -s 2>/dev/null || true
fi

# mounts — match pmOS mount_proc_sys_dev options
mount -t proc -o nodev,noexec,nosuid proc /proc 2>/dev/null || die "proc mount failed"
mount -t sysfs -o nodev,noexec,nosuid sysfs /sys 2>/dev/null || die "sysfs mount failed"
mount -t devtmpfs -o mode=0755,nosuid dev /dev 2>/dev/null || true
mount -t tmpfs -o nosuid,nodev,mode=0755 run /run 2>/dev/null || true
mkdir -p /dev/pts /run/uom-diag /tmp
mount -t devpts devpts /dev/pts 2>/dev/null || true
ln -sf /proc/self/fd /dev/fd 2>/dev/null || true

C=$(cat /proc/device-tree/compatible 2>/dev/null | tr '\0' ' ')
M=$(cat /proc/device-tree/model 2>/dev/null | tr '\0' ' ')
B=$(hexdump -v -e '4/1 "%02x "' /proc/device-tree/qcom,board-id 2>/dev/null) || B="unknown"
kmsg "compatible=$C"
kmsg "model=$M"
kmsg "board-id=$B"
case "$C" in
*xiaomi,dipper*) kmsg "DIPPER CONFIRMED" ;;
*) die "NOT DIPPER: $C" ;;
esac
kmsg "KERNEL CMDLINE: $(cat /proc/cmdline 2>/dev/null)"

# modules: depmod so zstd .ko.zst resolve; then libcomposite (pmOS does this in mount_proc_sys_dev)
if command -v depmod >/dev/null 2>&1; then
	depmod -a 2>&1 | while read -r line; do kmsg "depmod: $line"; done
	kmsg "depmod exit done"
else
	kmsg "depmod NOT PRESENT"
fi
modprobe libcomposite 2>&1 | while read -r line; do kmsg "modprobe libcomposite: $line"; done
kmsg "MODPROBE libcomposite exit=$?"
kmsg "MODULES: $(wc -l </proc/modules 2>/dev/null || echo 0) loaded"
if grep -q libcomposite /proc/modules 2>/dev/null; then
	kmsg "libcomposite LOADED"
else
	kmsg "libcomposite NOT LOADED (may still be built-in or auto-load later)"
fi

# configfs — same options as stock pmOS
if ! mountpoint -q /sys/kernel/config 2>/dev/null; then
	mount -t configfs -o nodev,noexec,nosuid configfs /sys/kernel/config 2>&1 | while read -r line; do kmsg "configfs: $line"; done
	kmsg "CONFIGFS mount exit=$?"
else
	kmsg "CONFIGFS already mounted"
fi
if [ ! -d "$CONFIGFS" ]; then
	# wait briefly for libcomposite to register gadget class
	for i in 1 2 3 4 5; do
		[ -d "$CONFIGFS" ] && break
		sleep 1
	done
fi
[ -d "$CONFIGFS" ] || die "no configfs ($CONFIGFS missing)"

kmsg "UDC_CLASS: $(ls /sys/class/udc 2>/dev/null | xargs)"
UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
if [ -z "$UDC" ]; then
	kmsg "NO UDC at boot, waiting 15s"
	i=0
	while [ "$i" -lt 15 ]; do
		UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
		[ -n "$UDC" ] && break
		i=$((i + 1))
		sleep 1
	done
fi
kmsg "UDC: ${UDC:-NONE}"
[ -n "$UDC" ] || die "no UDC after 15s wait"

kmsg "=== EXACT PMOS NCM GADGET SEQUENCE ==="
clear_gadget

kmsg "STEP 2: mkdir g1"
mkdir "$GADGET_DIR" 2>&1 | while read -r line; do kmsg "mkdir g1: $line"; done
[ -d "$GADGET_DIR" ] || die "mkdir g1 failed"
echo "0x18D1" >"$GADGET_DIR/idVendor"
echo "0xD001" >"$GADGET_DIR/idProduct"

kmsg "STEP 3: strings/0x409"
mkdir -p "$GADGET_DIR/strings/0x409"
echo "UOM" >"$GADGET_DIR/strings/0x409/manufacturer"
echo "$TEST_ID" >"$GADGET_DIR/strings/0x409/serialnumber"
echo "Dipper L0 NCM T1" >"$GADGET_DIR/strings/0x409/product"

kmsg "STEP 4: create network function (auto-loads usb_f_ncm / usb_f_rndis)"
if mkdir "$GADGET_DIR/functions/$NET_FN" 2>/tmp/uom-fn.err; then
	kmsg "mkdir $NET_FN OK"
else
	kmsg "mkdir $NET_FN FAILED: $(cat /tmp/uom-fn.err 2>/dev/null)"
	kmsg "trying fallback $NET_FN_FALLBACK"
	if mkdir "$GADGET_DIR/functions/$NET_FN_FALLBACK" 2>/tmp/uom-fn.err; then
		NET_FN="$NET_FN_FALLBACK"
		kmsg "fallback $NET_FN OK"
	else
		kmsg "fallback FAILED: $(cat /tmp/uom-fn.err 2>/dev/null)"
		die "no network function (ncm+rndis)"
	fi
fi
kmsg "MODULES after function mkdir: $(wc -l </proc/modules 2>/dev/null || echo 0)"
grep -q usb_f_ncm /proc/modules 2>/dev/null && kmsg "usb_f_ncm LOADED" || kmsg "usb_f_ncm NOT LOADED"
grep -q usb_f_rndis /proc/modules 2>/dev/null && kmsg "usb_f_rndis LOADED" || kmsg "usb_f_rndis NOT LOADED"
grep -q u_ether /proc/modules 2>/dev/null && kmsg "u_ether LOADED" || kmsg "u_ether NOT LOADED"

kmsg "STEP 5: configs/c.1"
mkdir -p "$GADGET_DIR/configs/c.1/strings/0x409"
echo "USB network" >"$GADGET_DIR/configs/c.1/strings/0x409/configuration"

kmsg "STEP 6: symlink function to config"
ln -s "$GADGET_DIR/functions/$NET_FN" "$GADGET_DIR/configs/c.1/" 2>&1 | while read -r line; do kmsg "ln: $line"; done
[ -e "$GADGET_DIR/configs/c.1/$NET_FN" ] || die "symlink $NET_FN failed"

kmsg "STEP 7: enable UDC (activates gadget)"
# clear any residual UDC first (pmOS setup_usb_configfs_udc)
if [ -e "$GADGET_DIR/UDC" ] && [ -n "$(cat "$GADGET_DIR/UDC" 2>/dev/null)" ]; then
	echo "" >"$GADGET_DIR/UDC" 2>/dev/null || true
fi
echo "$UDC" >"$GADGET_DIR/UDC" 2>/tmp/uom-udc.err
UDC_RC=$?
kmsg "UDC bind exit=$UDC_RC err=$(cat /tmp/uom-udc.err 2>/dev/null)"
kmsg "UDC now: $(cat "$GADGET_DIR/UDC" 2>/dev/null)"

IFNAME=$(cat "$GADGET_DIR/functions/$NET_FN/ifname" 2>/dev/null)
kmsg "NCM interface: ${IFNAME:-unknown} (fn=$NET_FN)"

if [ -n "$IFNAME" ]; then
	ifconfig "$IFNAME" "$HOST_IP" netmask 255.255.255.0 up 2>&1 | while read -r line; do kmsg "ifconfig: $line"; done
	kmsg "usb iface IP configured: $HOST_IP/24 on $IFNAME"
	touch /run/uom-diag/NCM_UP
	# stock pmOS starts unudhcpd so host gets CLIENT_IP automatically
	if command -v unudhcpd >/dev/null 2>&1; then
		unudhcpd -i "$IFNAME" -s "$HOST_IP" -c "$CLIENT_IP" &
		kmsg "unudhcpd started pid=$! ($HOST_IP -> $CLIENT_IP)"
	else
		kmsg "unudhcpd NOT PRESENT — host must static-config $CLIENT_IP"
	fi
else
	kmsg "NO ifname after UDC bind"
	ls -la "$GADGET_DIR/" 2>&1 | while read -r line; do kmsg "g1: $line"; done
	ls -la /sys/class/net/ 2>&1 | while read -r line; do kmsg "net: $line"; done
fi

kmsg "=== NCM SETUP COMPLETE ==="
kmsg "Waiting for host; ABL is the safety net (~51s idle / ~198s with USB)"
kmsg "HOST: expect usb0/enp* , dhcp or static $CLIENT_IP/24 , ping $HOST_IP"
kmsg "KEYS:"
kmsg "KEY_0_UPTIME=$(cut -d. -f1 /proc/uptime)"
kmsg "KEY_1_MODPROBE_LIBCOMPOSITE=$(grep -q libcomposite /proc/modules 2>/dev/null && echo PASS || echo FAIL)"
kmsg "KEY_2_USB_F_NCM=$(grep -q usb_f_ncm /proc/modules 2>/dev/null && echo PASS || echo FAIL)"
kmsg "KEY_2b_USB_F_RNDIS=$(grep -q usb_f_rndis /proc/modules 2>/dev/null && echo PASS || echo FAIL)"
kmsg "KEY_3_UDC=$UDC"
kmsg "KEY_3b_UDC_BOUND=$(cat "$GADGET_DIR/UDC" 2>/dev/null)"
kmsg "KEY_4_NET_FN=$NET_FN"
kmsg "KEY_4b_IFNAME=${IFNAME:-NONE}"
kmsg "KEY_5_IP=$HOST_IP"

i=0
while [ "$i" -lt 45 ]; do
	if ping -c 1 -W 1 "$CLIENT_IP" 2>/dev/null; then
		kmsg "HOST REACHABLE via ICMP at loop $i"
		touch /run/uom-diag/HOST_ACK
		break
	fi
	i=$((i + 1))
	sleep 1
done
if [ -f /run/uom-diag/HOST_ACK ]; then
	kmsg "KEY_6_NCM_HOST_REACHABLE=YES"
else
	kmsg "KEY_6_NCM_HOST_REACHABLE=NO"
fi
kmsg "DIAG COMPLETE"
sync
# stay alive so ABL/host can observe; do not force reboot
sleep 120
kmsg "idle window ended — soft reboot"
echo b >/proc/sysrq-trigger 2>/dev/null
sleep 3
reboot -f 2>/dev/null
while :; do :; done
