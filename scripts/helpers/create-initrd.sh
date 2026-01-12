#!/usr/bin/env bash
# Create initrd for module loading using busybox

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
ROOTFS_DIR="$ROOT_DIR/tmp/base-debian-os"
INITRD_PATH="$ROOTFS_DIR/initrd.cpio.gz"

# Create temporary directory for initrd contents
INITRD_DIR=$(mktemp -d)
trap 'rm -rf "$INITRD_DIR"' EXIT INT TERM

echo ">> Creating initrd directory structure..."
mkdir -p "$INITRD_DIR"/{bin,sbin,proc,sys,dev,newroot,mnt/modules}

# Download busybox binary for aarch64
BUSYBOX_URL="https://busybox.net/downloads/binaries/1.31.0-defconfig-multiarch-musl/busybox-armv8l"
BUSYBOX_CACHE="$ROOTFS_DIR/busybox-armv8l"
BUSYBOX_BIN="$INITRD_DIR/bin/busybox"

if [ -f "$BUSYBOX_CACHE" ]; then
    echo ">> Using cached busybox binary..."
    cp "$BUSYBOX_CACHE" "$BUSYBOX_BIN"
else
    echo ">> Downloading busybox binary from busybox.net..."
    if ! wget -q "$BUSYBOX_URL" -O "$BUSYBOX_CACHE"; then
        echo "Error: Failed to download busybox from $BUSYBOX_URL"
        exit 1
    fi
    cp "$BUSYBOX_CACHE" "$BUSYBOX_BIN"
fi

chmod +x "$BUSYBOX_BIN"

# Create symlinks for all needed commands
echo ">> Creating busybox symlinks..."
cd "$INITRD_DIR/bin"
for cmd in sh mount umount cp rm mkdir ls test blkid grep; do
    ln -sf busybox "$cmd"
done
cd "$ROOT_DIR"

# switch_root needs to be in /sbin
ln -sf ../bin/busybox "$INITRD_DIR/sbin/switch_root"

echo ">> Creating init script..."
cat > "$INITRD_DIR/init" << 'INITSCRIPT'
#!/bin/sh
# Initrd init script for module loading

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Mount real rootfs - try both vda and vdb to find the real rootfs
mkdir -p /newroot /mnt/test
echo ">> Finding root filesystem..."

ROOTFS_DEV=""
for dev in /dev/vda /dev/vdb; do
  if mount -o ro $dev /mnt/test 2>/dev/null; then
    # Check if this looks like a real rootfs (has init)
    if [ -e /mnt/test/sbin/init ] || [ -e /mnt/test/lib/systemd/systemd ] || [ -e /mnt/test/usr/lib/systemd/systemd ]; then
      echo ">> Found rootfs on $dev"
      ROOTFS_DEV=$dev
      umount /mnt/test
      break
    fi
    umount /mnt/test
  fi
done

if [ -z "$ROOTFS_DEV" ]; then
  echo "ERROR: Could not find valid rootfs on /dev/vda or /dev/vdb"
  exec /bin/sh
fi

echo ">> Mounting root filesystem from $ROOTFS_DEV..."
mount $ROOTFS_DEV /newroot

# Find and mount modules disk by label
echo ">> Looking for modules disk..."
MODULES_DEV=""
for dev in /dev/vda /dev/vdb; do
  if [ "$dev" != "$ROOTFS_DEV" ]; then
    # Check if this device has MODULES label
    if blkid $dev 2>/dev/null | grep -q 'LABEL="MODULES"'; then
      MODULES_DEV=$dev
      echo ">> Found modules disk on $dev"
      break
    fi
  fi
done

if [ -n "$MODULES_DEV" ]; then
  if mount $MODULES_DEV /mnt/modules 2>/dev/null; then
    echo ">> Modules disk found, updating kernel modules..."
    
    # Replace modules - remove old and copy new (preserve directory structure)
    rm -rf /newroot/lib/modules
    mkdir -p /newroot/lib
    cp -a /mnt/modules/lib/modules /newroot/lib/
    
    # Unmount modules disk
    umount /mnt/modules
    
    echo ">> Kernel modules updated"
  fi
else
  echo ">> No modules disk found, continuing with existing modules"
fi

# Unmount initrd filesystems (but NOT /newroot!)
umount /dev
umount /sys
umount /proc

# Switch to real rootfs and execute init
# Try common init paths
for init_path in /sbin/init /lib/systemd/systemd /usr/lib/systemd/systemd /bin/init; do
  if [ -x "/newroot$init_path" ]; then
    exec switch_root /newroot "$init_path"
  fi
done

echo "ERROR: No init found in rootfs!"
INITSCRIPT

chmod +x "$INITRD_DIR/init"

# Create initrd archive
echo ">> Packing initrd..."
cd "$INITRD_DIR"
find . | cpio -o -H newc | gzip > "$INITRD_PATH"

echo ">> Created initrd: $INITRD_PATH"
