#!/usr/bin/env bash
# Clone Rockchip kernel source

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

KERNEL_VERSION="${1:-6.1}"
KERNEL_DIR="$ROOT_DIR/rockchip-kernel"

echo "========================================="
echo "Preparing Rockchip kernel $KERNEL_VERSION"
echo "========================================="

# Clone or update kernel source via Makefile
make -C "$ROOT_DIR" clone-kernel KVER="$KERNEL_VERSION"

echo ""
echo "========================================="
echo "Kernel source ready: $KERNEL_DIR"
echo "========================================="
