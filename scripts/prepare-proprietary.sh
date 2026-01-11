#!/usr/bin/env bash
# Download stock firmware and extract proprietary files
# Based on SnapmakerU1-Extended-Firmware extraction process

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

FIRMWARE_FILE="U1_1.0.0.158_20251230140122_upgrade.bin"
FIRMWARE_SHA256="e1079ed43d41fff7411770d7bbc3857068bd4b1d3570babf07754e2dd9cbfc2e"
FIRMWARE_URL="https://public.resource.snapmaker.com/firmware/U1/$FIRMWARE_FILE"

FIRMWARE_PATH="$ROOT_DIR/tmp/firmware/$FIRMWARE_FILE"
EXTRACT_DIR="$ROOT_DIR/tmp/extracted"
DEST_RESOURCE="$ROOT_DIR/tmp/proprietary/resource.img"

echo "========================================="
echo "Preparing proprietary files"
echo "========================================="

# Check if already extracted
if [[ -f "$DEST_RESOURCE" ]]; then
    echo ">> Proprietary files already present. Skipping extraction."
    exit 0
fi

# Download firmware if needed
if [[ ! -f "$FIRMWARE_PATH" ]]; then
    echo ">> Downloading stock firmware..."
    mkdir -p "$(dirname "$FIRMWARE_PATH")"
    if command -v wget &> /dev/null; then
        wget -O "$FIRMWARE_PATH.tmp" "$FIRMWARE_URL"
    elif command -v curl &> /dev/null; then
        curl -L -o "$FIRMWARE_PATH.tmp" "$FIRMWARE_URL"
    else
        echo "Error: Neither wget nor curl found. Cannot download firmware."
        exit 1
    fi
    
    echo ">> Verifying firmware checksum..."
    echo "$FIRMWARE_SHA256  $FIRMWARE_PATH.tmp" | sha256sum -c --quiet
    mv "$FIRMWARE_PATH.tmp" "$FIRMWARE_PATH"
    echo ">> Firmware downloaded: $FIRMWARE_PATH"
else
    echo ">> Using cached firmware: $FIRMWARE_PATH"
fi

# Ensure extraction tools are built
"$SCRIPT_DIR/prepare-tools.sh"

# Unpack firmware to get boot.img
echo ">> Unpacking firmware to extract boot.img..."
"$SCRIPT_DIR/helpers/unpack_firmware.sh" "$FIRMWARE_PATH" "$EXTRACT_DIR"

# Extract boot.img components
echo ">> Extracting resource.img from boot.img..."
BOOT_IMG="$EXTRACT_DIR/rk-unpacked/boot.img"
if [[ ! -f "$BOOT_IMG" ]]; then
    echo "Error: boot.img not found at $BOOT_IMG"
    exit 1
fi

# Install proprietary files
echo ">> Extracting resource.img..."
mkdir -p "$(dirname "$DEST_RESOURCE")"
dumpimage -T flat_dt -p 2 -o "$DEST_RESOURCE" "$BOOT_IMG"

echo ""
echo "========================================="
echo "Proprietary files extracted:"
echo "  - $DEST_RESOURCE"
echo ""
echo "Note: These files are in tmp/ and excluded from git"
echo "========================================="
