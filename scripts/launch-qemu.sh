#!/bin/bash
set -e

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <kernel-image> [qemu-args...]"
  echo ""
  echo "Arguments:"
  echo "  kernel-image  Path to kernel vmlinuz, Image, or zImage file"
  echo "  qemu-args     Additional QEMU arguments (optional)"
  echo ""
  echo "Examples:"
  echo "  # Interactive mode (default):"
  echo "  $0 output/kernel-open-devel-6.1-20260110-abc123-vmlinuz"
  echo ""
  echo "  # With device tree blob:"
  echo "  $0 output/kernel-open-6.1-20260110-abc123-vmlinuz -dtb output/kernel-open-6.1-20260110-abc123-u1.dtb"
  echo ""
  echo "  # Non-interactive mode (for automation/testing):"
  echo "  $0 output/kernel-open-6.1-20260110-abc123-vmlinuz -serial pty -nographic"
  echo ""
  echo "Note: This script must be run directly in your terminal for interactive use."
  echo "      The serial console cannot be accessed when run through background processes."
  echo ""
  echo "Note: Use the vmlinuz file, NOT the -u1-boot.img FIT image."
  echo "      FIT images are for U-Boot bootloader, not for direct QEMU boot."
  exit 1
fi

KERNEL_IMG="$1"
shift
EXTRA_ARGS=("$@")

if [[ ! -f "$KERNEL_IMG" ]]; then
  echo "Error: Kernel image not found: $KERNEL_IMG"
  exit 1
fi

# Resolve absolute path
KERNEL_IMG="$(cd "$(dirname "$KERNEL_IMG")" && pwd)/$(basename "$KERNEL_IMG")"

# Check for rootfs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOTFS_IMG="$ROOT_DIR/tmp/base-debian-os/rootfs.img"

if [[ ! -f "$ROOTFS_IMG" ]]; then
  echo "Warning: Rootfs not found at $ROOTFS_IMG"
  echo "Prepare it with: ./dev.sh prepare rootfs"
  echo "Launching without rootfs..."
  echo ""
  ROOTFS_ARGS=()
else
  echo "Using rootfs: $ROOTFS_IMG"
  ROOTFS_ARGS=("-drive" "file=$ROOTFS_IMG,format=raw,if=none,id=hd0" "-device" "virtio-blk-device,drive=hd0")
fi

echo "==========================================================="
echo "Launching QEMU with kernel: $KERNEL_IMG"
if [[ -f "$ROOTFS_IMG" ]]; then
  echo "                   rootfs: $ROOTFS_IMG"
fi
echo "==========================================================="
echo ""
echo "Boot arguments:"
echo "  - PL011 UART console on ttyAMA0"
if [[ -f "$ROOTFS_IMG" ]]; then
  echo "  - Root filesystem on /dev/vda"
else
  echo "  - No rootfs (expects kernel to handle init)"
fi
echo "  - Verbose boot (earlyprintk=pl011)"
echo ""
echo "Interactive console controls:"
echo "  - Ctrl-A X    : Exit QEMU"
echo "  - Ctrl-A C    : Switch between serial console and QEMU monitor"
echo ""

# Launch QEMU
if [[ -f "$ROOTFS_IMG" ]]; then
  # More verbose kernel debugging to see what's failing
  KERNEL_CMDLINE="console=ttyAMA0 root=/dev/vda rw loglevel=9 debug"
else
  KERNEL_CMDLINE="console=ttyAMA0"
fi

# Use -serial mon:stdio to multiplex monitor and serial console
# This allows Ctrl-A C to switch between them
# Note: RK3562 uses ARM Cortex-A53 CPUs (quad-core)
exec qemu-system-aarch64 \
  -M virt \
  -cpu cortex-a53 \
  -smp 4 \
  -m 2048 \
  -kernel "$KERNEL_IMG" \
  -append "$KERNEL_CMDLINE" \
  -serial mon:stdio \
  -nographic \
  "${ROOTFS_ARGS[@]}" \
  "${EXTRA_ARGS[@]}"
