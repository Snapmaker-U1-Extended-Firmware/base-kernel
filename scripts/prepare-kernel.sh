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

# Check if already cloned
if [[ -d "$KERNEL_DIR/.git" ]]; then
    echo ">> Kernel source already present at $KERNEL_DIR"
    exit 0
fi

# Clone using the existing script
"$SCRIPT_DIR/clone-rockchip-kernel.sh" "$KERNEL_VERSION"

echo ""
echo "========================================="
echo "Kernel source ready: $KERNEL_DIR"
echo "========================================="
