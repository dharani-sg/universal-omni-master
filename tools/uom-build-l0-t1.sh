#!/bin/sh
# Build Dipper L0 NCM T1 Android boot image.
# Replaces /init in stock pmOS initramfs with tools/init_l0_ncm_t1.sh,
# appends headless DTB to vmlinuz, packs with mkbootimg.
#
# Usage:
#   tools/uom-build-l0-t1.sh
#   ARTIFACT_VAULT=/path tools/uom-build-l0-t1.sh
#   OUT=/tmp/l0_t1_ncm_boot.img tools/uom-build-l0-t1.sh
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
INIT_SRC="${INIT_SRC:-$REPO_ROOT/tools/init_l0_ncm_t1.sh}"
VAULT="${ARTIFACT_VAULT:-/home/alpine/uom-artifact-vault/dipper-20260721}"
VMLINUZ="${VMLINUZ:-$VAULT/boot/vmlinuz}"
DTB="${DTB:-$VAULT/boot/sdm845-xiaomi-mi8-dipper-headless.dtb}"
# Prefer previously extracted stock initramfs tree; fall back to vault initramfs
STOCK_TREE="${STOCK_TREE:-/tmp/pmos-initfs-stock}"
STOCK_INITRAMFS="${STOCK_INITRAMFS:-$VAULT/boot/initramfs}"
WORK="${WORK:-/tmp/uom-t1-build}"
OUT="${OUT:-/tmp/l0_t1_ncm_boot.img}"
KERNEL_OUT="${KERNEL_OUT:-/tmp/uom-t1-kernel-with-dtb}"
RAMDISK_OUT="${RAMDISK_OUT:-/tmp/uom-t1-initramfs.zst}"

CMDLINE="${CMDLINE:-console=ttyMSM0,115200 androidboot.hardware=qcom earlycon=msm_geni_serial,0xa840000 panic=15 printk.time=1 loglevel=8 log_buf_len=1M}"

die() { echo "ERROR: $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing tool: $1"; }

need mkbootimg
need zstd
need cpio
need find

[ -f "$INIT_SRC" ] || die "init script not found: $INIT_SRC"
[ -f "$VMLINUZ" ] || die "vmlinuz not found: $VMLINUZ"
[ -f "$DTB" ] || die "dtb not found: $DTB"

echo "==> L0 T1 build"
echo "    init:    $INIT_SRC"
echo "    vmlinuz: $VMLINUZ"
echo "    dtb:     $DTB"
echo "    out:     $OUT"

# --- prepare work tree from stock initramfs ---
rm -rf "$WORK"
mkdir -p "$WORK"

if [ -d "$STOCK_TREE/usr" ] && [ -f "$STOCK_TREE/init_functions.sh" ]; then
	echo "==> cloning stock tree $STOCK_TREE"
	# copy preserving links; exclude prior init swap noise if any
	cp -a "$STOCK_TREE"/. "$WORK"/
elif [ -f "$STOCK_INITRAMFS" ]; then
	echo "==> extracting $STOCK_INITRAMFS"
	case "$STOCK_INITRAMFS" in
	*.zst | *.zstd)
		zstd -d -c "$STOCK_INITRAMFS" | (cd "$WORK" && cpio -idm)
		;;
	*)
		# try raw cpio, then zstd, then gzip
		if (cd "$WORK" && cpio -idm <"$STOCK_INITRAMFS") 2>/dev/null; then
			:
		elif zstd -d -c "$STOCK_INITRAMFS" 2>/dev/null | (cd "$WORK" && cpio -idm); then
			:
		elif gzip -dc "$STOCK_INITRAMFS" 2>/dev/null | (cd "$WORK" && cpio -idm); then
			:
		else
			die "cannot extract initramfs: $STOCK_INITRAMFS"
		fi
		;;
	esac
else
	die "no stock initramfs tree ($STOCK_TREE) or archive ($STOCK_INITRAMFS)"
fi

# ensure modules path present
MODDIR=$(find "$WORK" -type d -path '*/lib/modules/*' -name 'kernel' 2>/dev/null | head -1 || true)
if [ -z "$MODDIR" ]; then
	echo "WARN: no kernel modules tree under $WORK" >&2
else
	echo "==> modules: $MODDIR"
	ls "$MODDIR/drivers/usb/gadget/function/usb_f_ncm.ko"* 2>/dev/null || echo "WARN: usb_f_ncm.ko missing" >&2
fi

# --- swap /init ---
echo "==> installing T1 init"
cp "$INIT_SRC" "$WORK/init"
chmod 755 "$WORK/init"
# keep a copy for forensics inside the image
cp "$INIT_SRC" "$WORK/init_l0_ncm_t1.sh"
chmod 755 "$WORK/init_l0_ncm_t1.sh"

# --- pack ramdisk (zstd, newc) ---
echo "==> packing ramdisk -> $RAMDISK_OUT"
(cd "$WORK" && find . | cpio -o -H newc 2>/dev/null) | zstd -f -o "$RAMDISK_OUT"
# zstd -o may need -f force; older zstd uses -o differently
if [ ! -s "$RAMDISK_OUT" ]; then
	(cd "$WORK" && find . | cpio -o -H newc 2>/dev/null) | zstd >"$RAMDISK_OUT"
fi
[ -s "$RAMDISK_OUT" ] || die "ramdisk empty"

# --- kernel + DTB append (deviceinfo_append_dtb=true) ---
echo "==> kernel+dtb -> $KERNEL_OUT"
cat "$VMLINUZ" "$DTB" >"$KERNEL_OUT"
[ -s "$KERNEL_OUT" ] || die "kernel+dtb empty"

# --- mkbootimg (dipper / sdm845 offsets from deviceinfo) ---
echo "==> mkbootimg"
mkbootimg \
	--kernel "$KERNEL_OUT" \
	--ramdisk "$RAMDISK_OUT" \
	--base 0x00000000 \
	--kernel_offset 0x00008000 \
	--ramdisk_offset 0x01000000 \
	--second_offset 0x00f00000 \
	--tags_offset 0x00000100 \
	--pagesize 4096 \
	--cmdline "$CMDLINE" \
	--header_version 0 \
	-o "$OUT"

[ -s "$OUT" ] || die "output image empty: $OUT"

SHA=$(sha256sum "$OUT" | awk '{print $1}')
SIZE=$(wc -c <"$OUT" | tr -d ' ')
echo "==> DONE"
echo "    image:  $OUT"
echo "    size:   $SIZE bytes"
echo "    sha256: $SHA"
echo "    short:  ${SHA%????????????????????????????????????????}"
echo ""
echo "Boot with:"
echo "  adb reboot bootloader"
echo "  fastboot boot $OUT"
echo "  # host watch:"
echo "  tools/uom-host-ncm-watch.sh"
