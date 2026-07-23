#!/bin/busybox ash
set -a
LOG=/tmp/uom-diag.log
KMSG=/dev/kmsg
CONFIGFS=/sys/kernel/config/usb_gadget
GADGET_DIR=$CONFIGFS/g1
TEST_ID="UOM-DIPPER-NCM-$(date +%s 2>/dev/null || echo 0)"
say(){ echo "[diag] $*" > "$KMSG" 2>/dev/null||true; echo "[diag] $*" >> "$LOG" 2>/dev/null||true; }
die(){
  say "FATAL: $*"
  say "ATTEMPTING HARD REBOOT"
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
say "=== UOM DIPPER NCM v3 ==="
say "Test-ID: $TEST_ID"
mount -t proc none /proc 2>/dev/null||die "proc"
mount -t sysfs none /sys 2>/dev/null||die "sysfs"
mount -t devtmpfs none /dev 2>/dev/null||true
mkdir -p /dev/pts /run/uom-dipper-diag
mount -t devpts none /dev/pts 2>/dev/null||true
C=$(cat /proc/device-tree/compatible 2>/dev/null|tr '^@' ' ')
M=$(cat /proc/device-tree/model 2>/dev/null|tr '^@' ' ')
B=$(hexdump -v -e '4/1 "%02x "' /proc/device-tree/qcom,board-id 2>/dev/null)||B="unknown"
say "compatible=$C"
say "model=$M"
say "board-id=$B"
case "$C" in *xiaomi,dipper*) say "DIPPER CONFIRMED" ;; *) die "NOT DIPPER: $C" ;; esac
case "$M" in *headless*) say "HEADLESS CONFIRMED" ;; *) say "WARNING: may not be headless" ;; esac
# Watchdog: ABL is the hardware watchdog (~51s). No software timer needed.
[ -c /dev/watchdog0 ] && say "HW WATCHDOG AVAILABLE" || say "HW WATCHDOG UNAVAILABLE (ABL is sufficient)"
say "KERNEL CMDLINE: $(cat /proc/cmdline)"
say "OOPS_PANIC CHECK: $(cat /proc/cmdline | grep -o 'oops=panic' || echo 'NOT SET')"
depmod -a 2>&1 | say
modprobe libcomposite 2>&1 | say||say "libcomposite modprobe returned $?"
mount -t configfs none /sys/kernel/config 2>&1 | say||say "configfs mount returned $?"
if [ ! -d "$CONFIGFS" ]; then
  say "FATAL: $CONFIGFS does not exist — libcomposite did not register gadget class"
  die "no gadget class"
fi
UDC=""
for i in $(seq 1 30); do
  UDC=$(ls /sys/class/udc 2>/dev/null|head -1)
  [ -n "$UDC" ] && break
  sleep 1
done
if [ -z "$UDC" ]; then
  say "NO UDC FOUND — gadget bind impossible"
else
  say "UDC: $UDC"
  if [ -d "$GADGET_DIR" ]; then
    say "Removing stale gadget"
    echo "" >"$GADGET_DIR/UDC" 2>/dev/null
    rm -f "$GADGET_DIR/configs/c.1/ncm.usb0" 2>/dev/null
    rmdir "$GADGET_DIR/configs/c.1/strings/0x409" 2>/dev/null||true
    rmdir "$GADGET_DIR/configs/c.1" 2>/dev/null||true
    rmdir "$GADGET_DIR/functions/ncm.usb0" 2>/dev/null||true
    rmdir "$GADGET_DIR/strings/0x409" 2>/dev/null||true
    rmdir "$GADGET_DIR" 2>/dev/null||true
  fi
  mkdir "$GADGET_DIR" ||{ say "FATAL: cannot create gadget dir"; die "gadget dir"; }
  echo "0x18D1" >"$GADGET_DIR/idVendor" 2>&1 | say
  echo "0xD001" >"$GADGET_DIR/idProduct" 2>&1 | say
  mkdir "$GADGET_DIR/strings/0x409" 2>/dev/null||true
  echo "UOM" >"$GADGET_DIR/strings/0x409/manufacturer"
  echo "DipperNCM" >"$GADGET_DIR/strings/0x409/product" 2>/dev/null||true
  mkdir "$GADGET_DIR/configs/c.1" 2>/dev/null||true
  echo "NCM network" >"$GADGET_DIR/configs/c.1/strings/0x409/configuration" 2>/dev/null||true
  mkdir "$GADGET_DIR/functions/ncm.usb0" 2>/dev/null||true
  ln -s "$GADGET_DIR/functions/ncm.usb0" "$GADGET_DIR/configs/c.1" 2>/dev/null||say "symlink failed"
  echo "$UDC" >"$GADGET_DIR/UDC" 2>&1 | say||say "UDC bind returned $?"
fi
say "WAITING FOR NETWORK INTERFACE (30s)"
IFACE=""
for i in $(seq 1 30); do
  IFACE=$(ip link 2>/dev/null | grep -o 'usb[0-9]*' | head -1)
  [ -n "$IFACE" ] && break
  sleep 1
done
if [ -n "$IFACE" ]; then
  say "NCM INTERFACE: $IFACE"
  ifconfig "$IFACE" 192.168.2.2 netmask 255.255.255.0 up 2>&1 | say
  say "INTERFACE_CONFIGURED: $IFACE 192.168.2.2"
  touch /run/uom-dipper-diag/NCM_IFACE_UP
  echo "=== UOM DIPPER NCM ===" >/dev/kmsg
  echo "Test-ID: $TEST_ID" >/dev/kmsg
  echo "Interface: $IFACE, IP: 192.168.2.2" >/dev/kmsg
  echo "Compatible: $C" >/dev/kmsg
  echo "Model: $M" >/dev/kmsg
  echo "UDC: $UDC" >/dev/kmsg
  touch /run/uom-dipper-diag/HOST_READY
  for i in $(seq 1 60); do
    ping -c 1 -W 1 192.168.2.1 2>/dev/null && { touch /run/uom-dipper-diag/HOST_ACK; say "HOST REACHABLE via ICMP"; break; }
    sleep 1
  done
else
  say "NO NCM INTERFACE FOUND"
  ls -la /sys/class/net/ 2>&1 | say
  ls -la /sys/kernel/config/usb_gadget/g1/ 2>&1 | say
fi
if [ -f /run/uom-dipper-diag/HOST_ACK ]; then
  say "D5 PASS - host acknowledged"
  sleep 30
else
  say "D5 NOT PROVEN - no host ACK"
  sleep 10
fi
say "DIAG COMPLETE - REBOOTING"
sync
echo b >/proc/sysrq-trigger 2>/dev/null
sleep 3
reboot -f 2>/dev/null
sleep 5
echo b >/proc/sysrq-trigger 2>/dev/null
while :; do :; done
