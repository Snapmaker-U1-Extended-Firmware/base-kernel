#!/bin/bash

set -e

# Handle prepare command (runs outside container)
if [[ "$1" == "prepare" ]]; then
    shift
    case "$1" in
        help|--help|-h|"")
            cat <<EOF
Prepare build dependencies (runs outside container)

Usage:
  ./dev.sh prepare <command>

Commands:
  tools         Build firmware extraction tools
  proprietary   Download stock firmware and extract proprietary files
  kernel        Clone Rockchip kernel source [version]
  rootfs        Download and prepare Debian rootfs for QEMU [version]
  help          Show this help

Examples:
  ./dev.sh prepare tools
  ./dev.sh prepare proprietary
  ./dev.sh prepare kernel 6.1      # Clone kernel version 6.1
  ./dev.sh prepare rootfs          # Download latest release
  ./dev.sh prepare rootfs v1.0.0   # Download specific release

EOF
            exit 0
            ;;
        tools)
            exec ./scripts/prepare-tools.sh
            ;;
        proprietary)
            exec ./scripts/prepare-proprietary.sh
            ;;
        kernel)
            shift
            exec ./scripts/prepare-kernel.sh "$@"
            ;;
        rootfs)
            shift
            exec ./scripts/prepare-rootfs.sh "$@"
            ;;
        *)
            echo "Unknown prepare command: $1"
            echo "Run './dev.sh prepare help' for usage."
            exit 1
            ;;
    esac
fi

# Show top-level help if requested
if [[ "$1" == "help" || "$1" == "--help" || "$1" == "-h" || -z "$1" ]]; then
    cat <<EOF
Snapmaker U1 Custom Kernel Builder - Development Environment

Usage:
  ./dev.sh prepare <command> [args]           Prepare build dependencies
  ./dev.sh make <target> [PROFILE=<profile>] [KVER=<version>]
  ./dev.sh launch <kernel-image> [qemu-args]  Launch QEMU

Commands:
  prepare       Prepare dependencies (tools, proprietary, kernel, rootfs)
  make          Run Makefile targets (kernel, qemu, clean)
  launch        Launch QEMU with built kernel
  help          Show this help message

Examples:
  # Prepare dependencies
  ./dev.sh prepare proprietary
  ./dev.sh prepare kernel 6.1
  ./dev.sh prepare rootfs

  # Build kernel
  ./dev.sh make kernel PROFILE=open-devel KVER=6.1
  ./dev.sh make kernel PROFILE=open KVER=6.1
  ./dev.sh make help

  # Test in QEMU (use -devel profile for QEMU compatibility)
  ./dev.sh launch output/kernel-open-devel-6.1-20260111-abc1234-vmlinuz

For detailed options:
  ./dev.sh prepare help
  ./dev.sh make help
  ./dev.sh launch help

EOF
    exit 0
fi

# Handle launch command locally (not in container)
if [[ "$1" == "launch" ]]; then
    shift
    # Show help if requested
    if [[ "$1" == "help" || "$1" == "--help" || "$1" == "-h" || -z "$1" ]]; then
        cat <<EOF
Launch QEMU with built kernel

Usage:
  ./dev.sh launch <vmlinuz> [qemu-args...]

Arguments:
  vmlinuz       Path to kernel image (use *-vmlinuz, not *-u1-boot.img)
  qemu-args     Additional QEMU arguments (optional)

Examples:
  ./dev.sh launch output/kernel-open-devel-6.1-20260111-abc1234-vmlinuz
  ./dev.sh launch output/kernel-open-devel-6.1-20260111-abc1234-vmlinuz -nographic

The launcher configures QEMU with:
  - ARM64 virt machine with Cortex-A72
  - 2GB RAM
  - Serial console on ttyAMA0
  - Verbose kernel boot output

Note: Use the 'open-devel' profile for QEMU compatibility (includes VirtIO
      drivers and disables Rockchip DRM/security features requiring TrustZone)

Press Ctrl-A X to exit QEMU

EOF
        exit 0
    fi
    exec ./scripts/launch-qemu.sh "$@"
fi

IMAGE_NAME="snapmaker-kernel-dev"
BUILD_CONTEXT=".github/dev"

if ! docker build -t "$IMAGE_NAME" "$BUILD_CONTEXT"; then
    echo "[!] Docker build failed."
    exit 1
fi

TTY_FLAG=""
[[ -t 0 ]] && TTY_FLAG="-it"

# Pass through environment variables (avoid PROFILE and VERSION which conflict with kernel build)
ENV_FLAGS="-e GIT_VERSION -e OUTPUT_DIR"

# Use tmp/ccache in CI, named volume locally
if [[ -n "$CI" ]]; then
  mkdir -p "$PWD/tmp/ccache"
  CCACHE_MOUNT="-v $PWD/tmp/ccache:/tmp/ccache"
else
  CCACHE_MOUNT="-v snapmaker-kernel-ccache:/tmp/ccache"
fi

exec docker run --rm $TTY_FLAG $ENV_FLAGS --privileged \
  -w "$PWD" -v "$PWD:$PWD" \
  $CCACHE_MOUNT \
  "$IMAGE_NAME" "$@"
