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
  proprietary   Download stock firmware and extract proprietary files
  kernel        Clone Rockchip kernel source
  help          Show this help

Examples:
  ./dev.sh prepare proprietary
  ./dev.sh prepare kernel

EOF
            exit 0
            ;;
        proprietary)
            exec ./scripts/prepare-proprietary.sh
            ;;
        kernel)
            shift
            exec ./scripts/prepare-kernel.sh "$@"
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
  ./dev.sh make <target> [PROFILE=<profile>] [KVER=<version>]
  ./dev.sh launch <args>
  ./dev.sh <command>

Commands:
  make          Run Makefile targets (kernel, qemu, clean)
  launch        Launch QEMU with built kernel
  help          Show this help message

Examples:
  ./dev.sh make help                           Show all make targets
  ./dev.sh make kernel PROFILE=extended-devel
  ./dev.sh make kernel PROFILE=basic KVER=6.1
  ./dev.sh launch output/kernel-extended-devel-6.1-20260110-abc123.img

For detailed build options:
  ./dev.sh make help

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
  ./dev.sh launch <boot.img> [qemu-args...]

Arguments:
  boot.img      Path to boot FIT image
  qemu-args     Additional QEMU arguments (optional)

Examples:
  ./dev.sh launch output/kernel-extended-devel-6.1-20260110-abc123.img
  ./dev.sh launch output/kernel-basic-6.1-20260110-abc123.img -nographic

The launcher configures QEMU with:
  - ARM64 virt machine with Cortex-A72
  - 2GB RAM
  - Serial console on ttyAMA0
  - Verbose kernel boot output

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
