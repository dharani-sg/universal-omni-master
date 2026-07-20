#!/bin/bash
# run-qemu-best.sh — Boot Alpine aarch64 VM via direct kernel with serial console
# Uses working configuration verified by audit

VM_DIR="$HOME/uom-vm"
cd "$VM_DIR" || { echo "Missing VM_DIR"; exit 1; }

LOG="$VM_DIR/logs/qemu-best-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$VM_DIR/logs"

echo "Starting QEMU aarch64 Alpine VM..."
echo "Serial log: $LOG"
echo "Attach tmux: tmux attach -t uom-vm"

exec qemu-system-aarch64 \
  -M virt -cpu cortex-a72 -m 512 -smp 2 \
  -accel tcg,thread=multi \
  -kernel ./vmlinuz-virt \
  -initrd ./initramfs-virt \
  -append "console=ttyAMA0,115200n8 earlycon=pl011,mmio,0x09000000 loglevel=8 panic=5" \
  -drive file=alpine-disk.qcow2,if=virtio,format=qcow2 \
  -device virtio-rng-pci \
  -netdev user,id=net0,hostfwd=tcp::8222-:22 \
  -device virtio-net-pci,netdev=net0 \
  -display none -monitor none -serial stdio \
  2>&1 | tee "$LOG"
