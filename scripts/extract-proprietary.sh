#!/usr/bin/env bash
# Extract proprietary modules and resource.img from stock firmware

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
FIRMWARE_FILE="$ROOT_DIR/firmware/U1_1.0.0.158_20251230140122_upgrade.bin"
EXTRACT_DIR="$ROOT_DIR/tmp/extracted"
DEST_MODULES="$ROOT_DIR/kernel/dump-original-kernel/modules"
DEST_RESOURCE="$ROOT_DIR/kernel/dump-original-kernel/resource.img"

if [[ ! -f "$FIRMWARE_FILE" ]]; then
  echo "Error: Firmware file not found: $FIRMWARE_FILE"
  echo "Run: make firmware"
  exit 1
fi

echo ">> Extracting stock firmware to $EXTRACT_DIR..."
"$SCRIPT_DIR/extract_squashfs.sh" "$FIRMWARE_FILE" "$EXTRACT_DIR"

echo ">> Extracting boot.img from rk-unpacked..."
BOOT_IMG="$EXTRACT_DIR/rk-unpacked/boot.img"
if [[ ! -f "$BOOT_IMG" ]]; then
  echo "Error: boot.img not found at $BOOT_IMG"
  exit 1
fi

echo ">> Unpacking boot.img to extract resource.img and modules..."
BOOT_EXTRACT="$EXTRACT_DIR/boot"
mkdir -p "$BOOT_EXTRACT"
cd "$BOOT_EXTRACT"

# Extract boot FIT image components
dumpimage -T flat_dt -p 0 -o fdt.dtb "$BOOT_IMG"
dumpimage -T flat_dt -p 1 -o kernel.lz4 "$BOOT_IMG"
dumpimage -T flat_dt -p 2 -o resource.img "$BOOT_IMG"

echo ">> Extracting modules from rootfs..."
MODULES_SRC="$EXTRACT_DIR/rootfs/vendor/lib/modules"
if [[ ! -d "$MODULES_SRC" ]]; then
  echo "Error: Modules not found at $MODULES_SRC"
  exit 1
fi

echo ">> Installing proprietary files to kernel/dump-original-kernel/..."
mkdir -p "$DEST_MODULES"
cp "$BOOT_EXTRACT/resource.img" "$DEST_RESOURCE"
cp "$MODULES_SRC/chsc6540.ko" "$DEST_MODULES/"
cp "$MODULES_SRC/io_manager.ko" "$DEST_MODULES/"

echo ">> Done! Proprietary files extracted:"
echo "   - $DEST_RESOURCE"
echo "   - $DEST_MODULES/chsc6540.ko"
echo "   - $DEST_MODULES/io_manager.ko"
