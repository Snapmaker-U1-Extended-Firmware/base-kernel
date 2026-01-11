#!/usr/bin/env bash
# Download and prepare rootfs for QEMU testing

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

RELEASE_VERSION="${1:-latest}"
ROOTFS_DIR="$ROOT_DIR/tmp/base-debian-os"
GITHUB_REPO="Snapmaker-U1-Extended-Firmware/base-debian-os"

echo "========================================="
echo "Preparing rootfs for QEMU"
echo "========================================="

# Create directory
mkdir -p "$ROOTFS_DIR"

# Determine release to download
if [[ "$RELEASE_VERSION" == "latest" ]]; then
    echo ">> Fetching latest release info from GitHub..."
    RELEASE_INFO=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest")
    RELEASE_TAG=$(echo "$RELEASE_INFO" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
    
    if [[ -z "$RELEASE_TAG" ]]; then
        echo "Error: Failed to fetch latest release"
        exit 1
    fi
    
    echo ">> Latest release: $RELEASE_TAG"
else
    RELEASE_TAG="$RELEASE_VERSION"
    echo ">> Using release: $RELEASE_TAG"
fi

# Find .tgz asset URL
echo ">> Fetching release assets..."
if [[ "$RELEASE_VERSION" == "latest" ]]; then
    ASSET_URL=$(echo "$RELEASE_INFO" | grep -o '"browser_download_url": *"[^"]*\.tgz"' | head -1 | cut -d'"' -f4)
else
    RELEASE_INFO=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/tags/$RELEASE_TAG")
    ASSET_URL=$(echo "$RELEASE_INFO" | grep -o '"browser_download_url": *"[^"]*\.tgz"' | head -1 | cut -d'"' -f4)
fi

if [[ -z "$ASSET_URL" ]]; then
    echo "Error: No .tgz asset found for release $RELEASE_TAG"
    exit 1
fi

ASSET_NAME=$(basename "$ASSET_URL")
TGZ_PATH="$ROOTFS_DIR/$ASSET_NAME"
IMG_PATH="$ROOTFS_DIR/rootfs.img"

# Check if already prepared
if [[ -f "$IMG_PATH" ]]; then
    echo ">> Rootfs image already exists: $IMG_PATH"
    exit 0
fi

# Download tarball if needed
if [[ ! -f "$TGZ_PATH" ]]; then
    echo ">> Downloading rootfs tarball from $ASSET_URL..."
    if command -v wget &> /dev/null; then
        wget -O "$TGZ_PATH.tmp" "$ASSET_URL"
    elif command -v curl &> /dev/null; then
        curl -L -o "$TGZ_PATH.tmp" "$ASSET_URL"
    else
        echo "Error: Neither wget nor curl found"
        exit 1
    fi
    mv "$TGZ_PATH.tmp" "$TGZ_PATH"
    echo ">> Downloaded: $TGZ_PATH"
else
    echo ">> Using cached tarball: $TGZ_PATH"
fi

# Create disk image (4GB)
echo ">> Creating disk image (4GB)..."
dd if=/dev/zero of="$IMG_PATH.tmp" bs=1M count=4096 status=progress

# Extract tarball to temporary directory
EXTRACT_DIR="$ROOTFS_DIR/extract"
echo ">> Extracting rootfs tarball..."
mkdir -p "$EXTRACT_DIR"
tar --warning=no-file-ignored --exclude='./dev/*' -xzf "$TGZ_PATH" -C "$EXTRACT_DIR"

# Create basic /dev structure
mkdir -p "$EXTRACT_DIR/dev"

# Format with ext4 and populate from directory
echo ">> Formatting with ext4 and populating from extracted files..."
mkfs.ext4 -F -d "$EXTRACT_DIR" "$IMG_PATH.tmp"

# Clean up extraction directory
echo ">> Cleaning up temporary files..."
rm -rf "$EXTRACT_DIR"

# Move to final location
mv "$IMG_PATH.tmp" "$IMG_PATH"

echo ""
echo "========================================="
echo "Rootfs prepared successfully:"
echo "  Release:    $RELEASE_TAG"
echo "  Tarball:    $TGZ_PATH"
echo "  Disk Image: $IMG_PATH (4GB ext4)"
echo ""
echo "Use with QEMU: ./dev.sh launch <kernel.img>"
echo "========================================="
