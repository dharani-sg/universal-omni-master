#!/bin/busybox ash
set -a
LOG=/tmp/uom-diag.log
KMSG=/dev/kmsg
CONFIGFS=/sys/kernel/config/usb_gadget
GADGET_DIR=$CONFIGFS/g1
TEST_ID="UOM-DIPPER-NCM-T1-$(date +%s 2>/dev/null || echo 0)"
kmsg(){ TS=$(cut -d. -f1 /proc/uptime 2>/dev/null||echo "?"); echo "<6>[   ${TS}] [diag] $*" >"$KMSG" 2>/dev/null; echo "[diag] $*" >>"$LOG" 2>/dev/null; }
die(){
  kmsg "FATAL: $*"
  kmsg "attempting reboot fallback chain"
  echo b >/proc/sysrq-trigger 2>/dev/null; sleep 2
  echo o >/proc/sysrq-trigger 2>/dev/null; sleep 2
  sync; reboot -f 2>/dev/null; sleep 5
  echo b >/proc/sysrq-trigger 2>/dev/null; sleep 30
  while :; do :; done
}
kmsg "=== UOM DIPPER L0 NCM T1 ==="
kmsg "Test-ID: $TEST_ID"
mount -t proc none /proc 2>/dev/null||die "proc mount failed"
mount -t sysfs none /sys 2>/dev/null||die "sysfs mount failed"
mount -t devtmpfs none /dev 2>/dev/null||true
mkdir -p /dev/pts /run/uom-diag; mount -t devpts none /dev/pts 2>/dev/null||true
mount -t tmpfs run /run 2>/dev/null||true
C=$(cat /proc/device-tree/compatible 2>/dev/null|tr '^@' ' ')
M=$(cat /proc/device-tree/model 2>/dev/null|tr '^@' ' ')
B=$(hexdump -v -e '4/1 "%02x "' /proc/device-tree/qcom,board-id 2>/dev/null)||B="unknown"
kmsg "compatible=$C"
kmsg "model=$M"
kmsg "board-id=$B"
case "$C" in *xiaomi,dipper*) kmsg "DIPPER CONFIRMED" ;; *) die "NOT DIPPER: $C" ;; esac
kmsg "KERNEL CMDLINE: $(cat /proc/cmdline 2>/dev/null)"
modprobe libcomposite 2>&1 | kmsg
kmsg "MODPROBE libcomposite exit=$?"
kmsg "MODULES: $(cat /proc/modules 2>/dev/null|wc -l) loaded"
grep -q libcomposite /proc/modules 2>/dev/null && kmsg "libcomposite LOADED" || kmsg "libcomposite NOT LOADED"
mount -t configfs configfs /sys/kernel/config 2>&1 | kmsg
kmsg "CONFIGFS mount exit=$?"
if [ ! -d "$CONFIGFS" ]; then
  kmsg "FATAL: configfs dir missing"
  die "no configfs"
fi
kmsg "UDC_CLASS: $(ls /sys/class/udc 2>/dev/null|xargs)"
UDC=$(ls /sys/class/udc 2>/dev/null|head -1)
if [ -z "$UDC" ]; then
  kmsg "NO UDC at boot, waiting 15s"
  for i in $(seq 1 15); do
    UDC=$(ls /sys/class/udc 2>/dev/null|head -1); [ -n "$UDC" ] && break
    sleep 1
  done
fi
kmsg "UDC: ${UDC:-NONE}"
[ -z "$UDC" ] && die "no UDC after 15s wait"
kmsg "=== EXACT PMOS NCM GADGET SEQUENCE ==="
kmsg "STEP 1: clear stale gadget"
[ -d "$GADGET_DIR" ] && { echo "" >"$GADGET_DIR/UDC" 2>/dev/null; rmdir "$GADGET_DIR" 2>/dev/null; }
kmsg "STEP 2: mkdir g1"
mkdir "$GADGET_DIR" 2>&1 | kmsg || { kmsg "gadget dir failed"; die "mkdir g1"; }
echo "0x18D1" >"$GADGET_DIR/idVendor" 2>&1 | kmsg
echo "0xD001" >"$GADGET_DIR/idProduct" 2>&1 | kmsg
kmsg "STEP 3: strings/0x409"
mkdir "$GADGET_DIR/strings/0x409" 2>/dev/null||true
echo "UOM" >"$GADGET_DIR/strings/0x409/manufacturer" 2>&1 | kmsg
echo "$TEST_ID" >"$GADGET_DIR/strings/0x409/serialnumber" 2>&1 | kmsg
echo "Dipper L0 NCM T1" >"$GADGET_DIR/strings/0x409/product" 2>&1 | kmsg
kmsg "STEP 4: create NCM function (auto-loads usb_f_ncm.ko)"
mkdir "$GADGET_DIR/functions/ncm.usb0" 2>&1 | kmsg
kmsg "mkdir ncm.usb0 exit=$?"
kmsg "MODULES after mkdir ncm: $(cat /proc/modules 2>/dev/null|wc -l)"
grep -q usb_f_ncm /proc/modules 2>/dev/null && kmsg "usb_f_ncm LOADED" || kmsg "usb_f_ncm NOT LOADED"
kmsg "STEP 5: configs/c.1"
mkdir "$GADGET_DIR/configs/c.1" 2>/dev/null||true
mkdir "$GADGET_DIR/configs/c.1/strings/0x409" 2>/dev/null||true
echo "USB network" >"$GADGET_DIR/configs/c.1/strings/0x409/configuration" 2>&1 | kmsg
kmsg "STEP 6: symlink function to config"
ln -s "$GADGET_DIR/functions/ncm.usb0" "$GADGET_DIR/configs/c.1/" 2>&1 | kmsg
kmsg "STEP 7: enable UDC (activates gadget)"
echo "$UDC" >"$GADGET_DIR/UDC" 2>&1 | kmsg
kmsg "UDC bind exit=$?"
kmsg "GADGET_TREE:"
ls -la "$GADGET_DIR/" 2>&1 | kmsg
ls -la "$GADGET_DIR/configs/c.1/" 2>&1 | kmsg
IFNAME=$(cat "$GADGET_DIR/functions/ncm.usb0/ifname" 2>/dev/null)
kmsg "NCM interface: ${IFNAME:-unknown}"
if [ -n "$IFNAME" ]; then
  ifconfig "$IFNAME" 172.16.42.1 netmask 255.255.255.0 up 2>&1 | kmsg
  kmsg "usb0 IP configured: 172.16.42.1/24"
  touch /run/uom-diag/NCM_UP
fi
kmsg "=== NCM SETUP COMPLETE ==="
kmsg "Now waiting for ABL watchdog to reclaim (~51s from boot)"
kmsg "If NCM works, host will see usb0 interface"
kmsg "HOST should: ip addr add 172.16.42.2/24 dev usb0 && ping 172.16.42.1"
kmsg "No software watchdog set — ABL is the safety net"
kmsg "KEYS:"
kmsg "KEY_0_UPTIME=$(cut -d. -f1 /proc/uptime)"
kmsg "KEY_1_MODPROBE_LIBCOMPOSITE=$(grep -q libcomposite /proc/modules 2>/dev/null&&echo PASS||echo FAIL)"
kmsg "KEY_2_MODPROBE_USB_F_NCM=$(grep -q usb_f_ncm /proc/modules 2>/dev/null&&echo PASS||echo FAIL)"
kmsg "KEY_3_UDC=${UDC}"
kmsg "KEY_4_NCM_IFNAME=${IFNAME:-NONE}"
kmsg "KEY_5_NCM_IP=$( [ -n \"$IFNAME\" ] && ifconfig $IFNAME 2>/dev/null|grep 'inet addr'|awk '{print \$2}'||echo NONE)"
kmsg "KEY_6_NCM_HOST_REACHABLE="
for i in $(seq 1 45); do
  ping -c 1 -W 1 172.16.42.2 2>/dev/null && { kmsg "HOST REACHABLE via ICMP at loop $i"; touch /run/uom-diag/HOST_ACK; break; }
  sleep 1
done
kmsg "KEY_6_NCM_HOST_REACHABLE=$( [ -f /run/uom-diag/HOST_ACK ]&&echo YES||echo NO)"
kmsg "DIAG COMPLETE"
sync; sleep 5
