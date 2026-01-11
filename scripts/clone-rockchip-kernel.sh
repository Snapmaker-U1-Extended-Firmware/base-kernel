#!/bin/bash
set -e

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <kernel-version>"
  echo ""
  echo "Arguments:"
  echo "  kernel-version   Kernel version (6.1 or 6.6)"
  echo ""
  echo "Example:"
  echo "  $0 6.1"
  exit 1
fi

KERNEL_VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KERNEL_DIR="$REPO_ROOT/rockchip-kernel"

# Source kernel configuration
source "$SCRIPT_DIR/kernel-config.sh"

BRANCH=$(get_kernel_branch "$KERNEL_VERSION")

# Configure git to trust the kernel directory (fixes CI ownership issues)
git config --global --add safe.directory "$KERNEL_DIR" 2>/dev/null || true

if [[ -d "$KERNEL_DIR/.git" ]]; then
  echo ">> Kernel source already cloned at $KERNEL_DIR"
  cd "$KERNEL_DIR"
  echo ">> Fetching latest changes from branch: $BRANCH"
  git fetch origin "$BRANCH"
  git checkout "$BRANCH"
  git reset --hard "origin/$BRANCH"
  echo ">> Kernel source updated to latest $BRANCH"
else
  echo ">> Cloning Rockchip kernel (branch: $BRANCH)..."
  mkdir -p "$(dirname "$KERNEL_DIR")"
  git clone --depth=1 --single-branch --branch="$BRANCH" \
    https://github.com/rockchip-linux/kernel.git "$KERNEL_DIR"
  echo ">> Kernel source cloned successfully"
fi

echo ">> Kernel source ready at $KERNEL_DIR"
cd "$KERNEL_DIR"
echo ">> Current commit: $(git rev-parse --short HEAD)"
