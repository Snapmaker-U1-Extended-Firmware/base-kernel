#!/bin/bash
set -euo pipefail

# Internal script - only called by dev.sh wrapper
# Do not run directly - use: ./dev.sh run [args...]

# Determine profile and kernel image from arguments
# If QEMU_PROFILE is set (by dev.sh), use it; otherwise default
PROFILE="${QEMU_PROFILE:-qemu-console}"

# Resolve directories once
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/output"
ROOTFS_DIR="$ROOT_DIR/tmp/base-debian-os"

# Auto-detect kernel image if not provided
if [[ $# -lt 1 ]] || [[ ! -f "$1" ]]; then
    # Try to find the newest -devel vmlinuz in output directory
    if [[ -d "$OUTPUT_DIR" ]]; then
        shopt -s nullglob
        files=("$OUTPUT_DIR"/*-devel-*-vmlinuz)
        shopt -u nullglob
        
        if [[ ${#files[@]} -gt 0 ]]; then
            KERNEL_IMG="${files[0]}"
            for file in "${files[@]}"; do
                [[ "$file" -nt "$KERNEL_IMG" ]] && KERNEL_IMG="$file"
            done
            echo "Auto-detected kernel: $KERNEL_IMG"
            echo ""
        else
            echo "Error: No kernel image found in $OUTPUT_DIR" >&2
            exit 1
        fi
    else
        echo "Error: No kernel image specified and output directory not found" >&2
        exit 1
    fi
else
    KERNEL_IMG="$1"
    shift
fi

EXTRA_ARGS=("$@")

if [[ ! -f "$KERNEL_IMG" ]]; then
    echo "Error: Kernel image not found: $KERNEL_IMG" >&2
    exit 1
fi

KERNEL_IMG="$(cd "$(dirname "$KERNEL_IMG")" && pwd)/$(basename "$KERNEL_IMG")"

ROOTFS_IMG="$ROOTFS_DIR/rootfs.img"
INITRD_IMG="$ROOTFS_DIR/initrd.cpio.gz"
MODULES_IMG="$ROOTFS_DIR/modules.img"

if [[ ! -f "$ROOTFS_IMG" ]]; then
    echo "Warning: Rootfs not found at $ROOTFS_IMG" >&2
    echo "Running without rootfs..." >&2
    echo ""
fi

echo "==========================================================="
echo "Running with kernel: $KERNEL_IMG"
[[ -f "$ROOTFS_IMG" ]] && echo "                  rootfs: $ROOTFS_IMG"
[[ -f "$INITRD_IMG" ]] && echo "                  initrd: $INITRD_IMG"
[[ -f "$MODULES_IMG" ]] && echo "                 modules: $MODULES_IMG"
echo "==========================================================="
echo ""

# ============================================================================
# QEMU-specific Launch Function
# ============================================================================

run_qemu() {
    local profile="$1"
    local console="$2"
    local use_gui="$3"
    
    local -a qemu_args=()
    local kernel_cmdline
    
    # Base VM configuration
    qemu_args+=("-M" "virt")
    qemu_args+=("-cpu" "cortex-a53")
    qemu_args+=("-smp" "4")
    qemu_args+=("-m" "2048")
    qemu_args+=("-kernel" "$KERNEL_IMG")
    
    # Network configuration
    qemu_args+=("-netdev" "user,id=net0,hostfwd=tcp::2222-:22")
    qemu_args+=("-device" "virtio-net-device,netdev=net0")
    
    # Storage configuration
    if [[ -f "$ROOTFS_IMG" ]]; then
        qemu_args+=("-drive" "file=$ROOTFS_IMG,format=raw,if=none,id=hd0")
        qemu_args+=("-device" "virtio-blk-device,drive=hd0")
        kernel_cmdline="$console root=/dev/vda rw"
    else
        kernel_cmdline="$console"
    fi
    
	# This init simplifies kernel module installation into existing rootfs after kernel modules are rebuilt
	# It mounts the modules.img partition and copies modules into /lib/modules in the rootfs
    if [[ -f "$INITRD_IMG" ]]; then
        qemu_args+=("-initrd" "$INITRD_IMG")
    fi
    
    if [[ -f "$MODULES_IMG" ]]; then
        qemu_args+=("-drive" "file=$MODULES_IMG,format=raw,if=none,id=modules")
        qemu_args+=("-device" "virtio-blk-device,drive=modules")
    fi
    
    # Kernel command line
    qemu_args+=("-append" "$kernel_cmdline")
    
    # Display configuration
    if [[ "$use_gui" == "true" ]]; then
        qemu_args+=("-device" "virtio-gpu-pci")
        qemu_args+=("-display" "gtk,gl=on,show-cursor=on")
        qemu_args+=("-device" "virtio-keyboard-device")
        qemu_args+=("-device" "virtio-mouse-device")
        qemu_args+=("-serial" "stdio")
    else
        qemu_args+=("-serial" "mon:stdio")
        qemu_args+=("-nographic")
    fi
    
    # Extra arguments from user
    qemu_args+=("${EXTRA_ARGS[@]}")
    
    echo "Profile: $profile (virtio-net, virtio-blk${use_gui:+, virtio-gpu})"
    echo ""
    
    exec qemu-system-aarch64 "${qemu_args[@]}"
}

case "$PROFILE" in
    qemu-console)
        run_qemu "$PROFILE" "console=ttyAMA0" "false"
        ;;
    qemu-gui)
        run_qemu "$PROFILE" "console=tty0 console=ttyAMA0" "true"
        ;;
    *)
        echo "Error: Unknown profile '$PROFILE'" >&2
        echo "Available profiles: qemu-console, qemu-gui" >&2
        exit 1
        ;;
esac
