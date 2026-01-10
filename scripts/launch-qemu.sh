#!/bin/bash
set -e

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <boot.img> [qemu-args...]"
  echo ""
  echo "Arguments:"
  echo "  boot.img      Path to boot FIT image"
  echo "  qemu-args     Additional QEMU arguments (optional)"
  echo ""
  echo "Example:"
  echo "  $0 output/kernel-extended-devel-6.1.img"
  echo "  $0 output/kernel-extended-devel-6.1.img -nographic"
  exit 1
fi

BOOT_IMG="$1"
shift
EXTRA_ARGS=("$@")

if [[ ! -f "$BOOT_IMG" ]]; then
  echo "Error: Boot image not found: $BOOT_IMG"
  exit 1
fi

# Resolve absolute path
BOOT_IMG="$(cd "$(dirname "$BOOT_IMG")" && pwd)/$(basename "$BOOT_IMG")"

echo "==========================================================="
echo "Launching QEMU with kernel: $BOOT_IMG"
echo "==========================================================="
echo ""
echo "Boot arguments:"
echo "  - PL011 UART console on ttyAMA0"
echo "  - No initramfs (expects kernel to handle init)"
echo "  - Verbose boot (earlyprintk=pl011)"
echo ""
echo "Press Ctrl-A X to exit QEMU"
echo ""

# Launch QEMU
qemu-system-aarch64 \
  -M virt \
  -cpu cortex-a72 \
  -m 2048 \
  -kernel "$BOOT_IMG" \
  -append "console=ttyAMA0 earlycon=pl011,0x09000000 loglevel=8" \
  -serial mon:stdio \
  -nographic \
  "${EXTRA_ARGS[@]}"
