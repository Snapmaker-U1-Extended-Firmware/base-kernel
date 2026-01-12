#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

is_help_requested() {
    [[ "${1:-}" == "help" || "${1:-}" == "--help" || "${1:-}" == "-h" || -z "${1:-}" ]]
}

setup_ccache_mount() {
    if [[ -n "${CI:-}" ]]; then
        mkdir -p "$PWD/tmp/ccache"
        echo "-v $PWD/tmp/ccache:/tmp/ccache"
    else
        echo "-v snapmaker-kernel-ccache:/tmp/ccache"
    fi
}

show_prepare_help() {
    cat <<'EOF'
Prepare build dependencies (runs outside container)

Usage:
  ./dev.sh prepare <command>

Commands:
  tools         Build firmware extraction tools
  proprietary   Download stock firmware and extract proprietary files
  kernel        Clone Rockchip kernel source [version]
  rootfs        Manage Debian rootfs for QEMU testing
    download [version]  Download rootfs tarball (default: latest)
    image               Create disk image from downloaded tarball
    modules             Update kernel modules in existing rootfs image
    [version]           Download version and create image (default: latest and create)

Examples:
  ./dev.sh prepare tools
  ./dev.sh prepare proprietary
  ./dev.sh prepare kernel 6.1         # Clone kernel version 6.1
  ./dev.sh prepare rootfs download        # Download latest release tarball
  ./dev.sh prepare rootfs download v1.0.0 # Download specific version
  ./dev.sh prepare rootfs image           # Create disk image from tarball
  ./dev.sh prepare rootfs modules         # Update modules in rootfs
  ./dev.sh prepare rootfs                 # Download latest and create image
  ./dev.sh prepare rootfs v1.0.0          # Download v1.0.0 and create image

EOF
}

show_main_help() {
    cat <<'EOF'
Snapmaker U1 Custom Kernel Builder - Development Environment

Usage:
  ./dev.sh prepare <command> [args]           Prepare build dependencies
  ./dev.sh make <target> [PROFILE=<profile>] [KVER=<version>]
  ./dev.sh run <kernel-image> [args]          Run kernel in virt/container

Commands:
  prepare       Prepare dependencies (tools, proprietary, kernel, rootfs)
  make          Build kernel using Makefile inside Docker container
  run           Run kernel in virtualization/container environment
  help          Show this help message

Examples:
  ./dev.sh prepare proprietary
  ./dev.sh prepare kernel 6.1
  ./dev.sh prepare rootfs

  ./dev.sh make kernel PROFILE=open KVER=6.1
  ./dev.sh make kernel PROFILE=open-devel KVER=6.1
  ./dev.sh make help

  # Run in virtualization (use -devel profile for compatibility)
  ./dev.sh run
  ./dev.sh run output/kernel-open-devel-6.1-20260111-abc1234-vmlinuz
  ./dev.sh run qemu-console output/kernel-open-devel-*-vmlinuz
  ./dev.sh run qemu-gui output/kernel-open-devel-*-vmlinuz

For detailed options:
  ./dev.sh prepare help
  ./dev.sh make help
  ./dev.sh run help

EOF
}

show_run_help() {
    cat <<'EOF'
Run kernel in various virtualization and containerization environments with optional rootfs

Usage:
  ./dev.sh run [profile] [vmlinuz] [args...]

Available Profiles:
  qemu-console         - Modern profile (virtio-net, virtio-blk)
  qemu-gui             - GUI profile (virtio-net, virtio-blk, virtio-gpu)

Arguments:
  profile       Virtualization profile to use, defaults to qemu-console
  vmlinuz       Path to kernel image, defaults to newest *-devel-*-vmlinuz
  args          Optional additional arguments passed to the virtualization method

Examples:
  # Auto-detect newest -devel kernel with default profile
  ./dev.sh run

  # Auto-detect newest kernel with specific profile
  ./dev.sh run qemu-gui

  # Explicit kernel path with default profile
  ./dev.sh run output/kernel-open-devel-6.1-20260111-abc1234-vmlinuz

  # Explicit profile and kernel
  ./dev.sh run qemu-gui output/kernel-open-devel-*-vmlinuz

Note: Always use '-devel' profile for QEMU compatibility
Hint: Ctrl-A X to exit QEMU, Ctrl-A C to switch to qemu console, Ctrl-Alt-G to release GUI grab

EOF
}

handle_prepare() {
    shift  # Remove 'prepare' from args
    local command="${1:-}"
    
    if is_help_requested "$command"; then
        show_prepare_help
        exit 0
    fi
    
    case "$command" in
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
        "")
            echo "Error: No prepare command specified" >&2
            echo "Run './dev.sh prepare help' for usage." >&2
            exit 1
            ;;
        *)
            echo "Error: Unknown prepare command: $command" >&2
            echo "Run './dev.sh prepare help' for usage." >&2
            exit 1
            ;;
    esac
}

handle_run() {
    shift  # Remove 'run' from args
    
    # Show help only if explicitly requested (not on empty args)
    if [[ "${1:-}" == "help" || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        show_run_help
        exit 0
    fi
    
    # Check if first arg is a profile name, actual profile validation is in run-virt.sh
    if [[ -n "${1:-}" && "$1" =~ ^qemu- ]]; then
        export QEMU_PROFILE="$1"
        shift
    fi
    
    exec ./scripts/run-virt.sh "$@"
}

handle_make() {
    local image_name="snapmaker-kernel-dev"
    local build_context=".github/dev"
    
    # Validate build context exists
    if [[ ! -d "$build_context" ]]; then
        echo "Error: Build context directory not found: $build_context" >&2
        exit 1
    fi
    
    # Build Docker image
    if ! docker build -t "$image_name" "$build_context"; then
        echo "Error: Docker build failed" >&2
        exit 1
    fi
    
    # Set TTY flag if running interactively
    local tty_flag=""
    [[ -t 0 ]] && tty_flag="-it"
    
    # Avoid passing PROFILE and VERSION which conflict with kernel build
    local -a env_flags=()
    [[ -n "${GIT_VERSION:-}" ]] && env_flags+=("-e" "GIT_VERSION")
    [[ -n "${OUTPUT_DIR:-}" ]] && env_flags+=("-e" "OUTPUT_DIR")
    
    # Setup ccache mount
    local ccache_mount
    ccache_mount="$(setup_ccache_mount)"
    
    # shellcheck disable=SC2086
    exec docker run --rm ${tty_flag} "${env_flags[@]}" --privileged \
        -w "$PWD" -v "$PWD:$PWD" \
        ${ccache_mount} \
        "$image_name" "$@"
}

main() {
    local command="${1:-}"
    
    if is_help_requested "$command"; then
        show_main_help
        exit 0
    fi
    
    case "$command" in
        prepare)
            handle_prepare "$@"
            ;;
        run)
            handle_run "$@"
            ;;
        make)
            handle_make "$@"
            ;;
        *)
            handle_make "$@"
            ;;
    esac
}

main "$@"

