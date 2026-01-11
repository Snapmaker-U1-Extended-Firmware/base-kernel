#!/bin/bash
set -e

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <kernel-version> <build-profile> <output.img>"
  echo ""
  echo "Arguments:"
  echo "  kernel-version   Kernel version (6.1 or 6.6)"
  echo "  build-profile    Build profile (open, open-devel)"
  echo "  output.img       Output FIT image path"
  echo ""
  echo "Example:"
  echo "  $0 6.1 open-devel output/kernel-open-devel-6.1-20260110-abc123-u1-boot.img"
  exit 1
fi

KERNEL_VERSION="$1"
BUILD_PROFILE="$2"
OUTPUT_IMG="$3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source configuration
source "$SCRIPT_DIR/kernel-config.sh"

# Validate arguments
validate_profile "$BUILD_PROFILE"
KERNEL_BRANCH=$(get_kernel_branch "$KERNEL_VERSION")

# Kernel directories
KERNEL_DIR="$REPO_ROOT/rockchip-kernel"
KERNEL_CONFIG_DIR="$REPO_ROOT/config"
KERNEL_RESOURCE="$REPO_ROOT/tmp/proprietary/resource.img"
BOOT_ITS_TEMPLATE="$KERNEL_CONFIG_DIR/boot.its.template"

STOCK_CONFIG="$KERNEL_CONFIG_DIR/snapmaker-u1-stock.config"
STOCK_DTS="$KERNEL_CONFIG_DIR/snapmaker-u1-stock.dts"
DTS_NAME="rk3562-snapmaker-u1-stock.dts"
DTB_NAME="rk3562-snapmaker-u1-stock.dtb"

# Build directories
TMP_DIR="$REPO_ROOT/tmp"
BUILD_DIR="$TMP_DIR/kernel-$BUILD_PROFILE-$KERNEL_VERSION"
BOOT_BUILD_DIR="$BUILD_DIR/boot"

# Output paths
OUTPUT_IMG="$(cd "$(dirname "$OUTPUT_IMG")" 2>/dev/null && pwd || mkdir -p "$(dirname "$OUTPUT_IMG")" && cd "$(dirname "$OUTPUT_IMG")" && pwd)/$(basename "$OUTPUT_IMG")"

# Cleanup trap
cleanup() {
  if [[ -d "$BUILD_DIR" ]]; then
    echo ">> Cleaning up temporary build directory..."
    # Clean kernel repo modifications
    if [[ -d "$KERNEL_DIR/.git" ]]; then
      cd "$KERNEL_DIR"
      git checkout Makefile arch/arm64/boot/dts/rockchip/Makefile 2>/dev/null || true
      rm -f arch/arm64/boot/dts/rockchip/"$DTS_NAME"
    fi
    # Remove temp build directory
    rm -rf "$BUILD_DIR"
  fi
}

trap cleanup EXIT INT TERM

# Validate kernel source exists
if [[ ! -d "$KERNEL_DIR/.git" ]]; then
  echo "Error: Kernel source not found at $KERNEL_DIR"
  echo "Run: ./dev.sh ./scripts/clone-rockchip-kernel.sh $KERNEL_VERSION"
  exit 1
fi

echo ">> Building kernel $KERNEL_VERSION with profile $BUILD_PROFILE"
echo ">> Kernel source: $KERNEL_DIR"
echo ">> Build directory: $BUILD_DIR"

# Create build directory
mkdir -p "$BUILD_DIR"
mkdir -p "$BUILD_DIR/modules"
mkdir -p "$BOOT_BUILD_DIR"

# Copy DTS
echo ">> Copying device tree: $DTS_NAME"
cp "$STOCK_DTS" "$KERNEL_DIR/arch/arm64/boot/dts/rockchip/$DTS_NAME"
if ! grep -q "$DTB_NAME" "$KERNEL_DIR/arch/arm64/boot/dts/rockchip/Makefile"; then
  echo "dtb-\$(CONFIG_ARCH_ROCKCHIP) += $DTB_NAME" >> "$KERNEL_DIR/arch/arm64/boot/dts/rockchip/Makefile"
fi

# Configure kernel
echo ">> Configuring kernel for profile=$BUILD_PROFILE version=$KERNEL_VERSION"
cp "$STOCK_CONFIG" "$BUILD_DIR/.config"

# Run olddefconfig
make -C "$KERNEL_DIR" O="$BUILD_DIR" \
  ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
  olddefconfig

# Apply profile-specific config fragments
PROFILE_CONFIG_FILE="$(get_profile_config "$BUILD_PROFILE" "$REPO_ROOT")"
if [[ -f "$PROFILE_CONFIG_FILE" ]]; then
  echo ">> Applying config changes for $BUILD_PROFILE profile from $PROFILE_CONFIG_FILE"
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Parse CONFIG_NAME=value
    if [[ "$line" =~ ^CONFIG_([A-Z0-9_]+)=(.+)$ ]]; then
      config_name="${BASH_REMATCH[1]}"
      config_value="${BASH_REMATCH[2]}"
      
      case "$config_value" in
        y) "$KERNEL_DIR/scripts/config" --file "$BUILD_DIR/.config" --enable "$config_name" ;;
        m) "$KERNEL_DIR/scripts/config" --file "$BUILD_DIR/.config" --module "$config_name" ;;
        n) "$KERNEL_DIR/scripts/config" --file "$BUILD_DIR/.config" --disable "$config_name" ;;
        *) "$KERNEL_DIR/scripts/config" --file "$BUILD_DIR/.config" --set-str "$config_name" "$config_value" ;;
      esac
    fi
  done < "$PROFILE_CONFIG_FILE"
  
  # Run olddefconfig again to resolve dependencies
  make -C "$KERNEL_DIR" O="$BUILD_DIR" \
    ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
    olddefconfig
fi

# Build kernel
echo ">> Building kernel (this may take several minutes)..."
make -C "$KERNEL_DIR" O="$BUILD_DIR" \
  ARCH="$ARCH" CROSS_COMPILE="ccache $CROSS_COMPILE" \
  KBUILD_BUILD_USER="$BUILD_PROFILE-build" \
  -j"$(nproc)" \
  Image rockchip/"$DTB_NAME" modules

# Install all kernel modules
echo ">> Installing kernel modules..."
MODULES_STAGING="$BUILD_DIR/modules_install"
rm -rf "$MODULES_STAGING"
make -C "$KERNEL_DIR" O="$BUILD_DIR" \
  ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
  INSTALL_MOD_PATH="$MODULES_STAGING" \
  INSTALL_MOD_STRIP=1 \
  modules_install

# Patch proprietary modules
echo ">> Running depmod..."
VERSION=$(grep '^VERSION = ' "$KERNEL_DIR/Makefile" | head -1 | awk '{print $3}')
PATCHLEVEL=$(grep '^PATCHLEVEL = ' "$KERNEL_DIR/Makefile" | head -1 | awk '{print $3}')
SUBLEVEL=$(grep '^SUBLEVEL = ' "$KERNEL_DIR/Makefile" | head -1 | awk '{print $3}')
KVER="$VERSION.$PATCHLEVEL.$SUBLEVEL"

depmod -b "$MODULES_STAGING" "$KVER"

echo ">> Modules installed to $MODULES_STAGING/lib/modules/$KVER/"

# Create boot FIT image
echo ">> Creating boot FIT image..."

# Compress kernel with LZ4
echo ">> Compressing kernel with LZ4..."
lz4 -9 -f "$BUILD_DIR/arch/arm64/boot/Image" "$BOOT_BUILD_DIR/kernel.lz4"

# Generate boot.its from template
echo ">> Generating boot.its..."
sed -e "s|DTB_PATH|$BUILD_DIR/arch/arm64/boot/dts/rockchip/$DTB_NAME|g" \
    -e "s|KERNEL_LZ4_PATH|$BOOT_BUILD_DIR/kernel.lz4|g" \
    -e "s|RESOURCE_PATH|$KERNEL_RESOURCE|g" \
    "$BOOT_ITS_TEMPLATE" > "$BOOT_BUILD_DIR/boot.its"

# Build FIT image
echo ">> Building FIT image with mkimage..."
mkimage -E -p 0x800 -B 0x100 -f "$BOOT_BUILD_DIR/boot.its" "$OUTPUT_IMG"

# Export kernel Image and config alongside boot image
OUTPUT_DIR="$(dirname "$OUTPUT_IMG")"
# .img gets full name with -u1-boot suffix
OUTPUT_BASE_IMG="$(basename "$OUTPUT_IMG" .img)"
# Other artifacts: strip -u1-boot suffix for cleaner names
OUTPUT_BASE="${OUTPUT_BASE_IMG%-u1-boot}"
# .dtb gets -u1 suffix only
OUTPUT_BASE_DTB="${OUTPUT_BASE}-u1"

cp "$BUILD_DIR/arch/arm64/boot/Image" "$OUTPUT_DIR/${OUTPUT_BASE}-vmlinuz"
cp "$BUILD_DIR/.config" "$OUTPUT_DIR/${OUTPUT_BASE}.config"
cp "$BUILD_DIR/arch/arm64/boot/dts/rockchip/$DTB_NAME" "$OUTPUT_DIR/${OUTPUT_BASE_DTB}.dtb"

# Export modules as compressed tarball
echo ">> Packaging modules..."
tar -czf "$OUTPUT_DIR/${OUTPUT_BASE}-modules.tar.gz" -C "$MODULES_STAGING" .

# Export kernel artifacts to tmp for convenience
ARTIFACTS_STAGING="$TMP_DIR/kernel-artifacts"
echo ">> Exporting kernel artifacts to $ARTIFACTS_STAGING..."
rm -rf "$ARTIFACTS_STAGING"
mkdir -p "$ARTIFACTS_STAGING"
cp "$BUILD_DIR/arch/arm64/boot/Image" "$ARTIFACTS_STAGING/Image"
cp "$BUILD_DIR/arch/arm64/boot/dts/rockchip/$DTB_NAME" "$ARTIFACTS_STAGING/$DTB_NAME"
cp -r "$MODULES_STAGING/lib" "$ARTIFACTS_STAGING/"

# Display results
BOOT_SIZE=$(du -h "$OUTPUT_IMG" | cut -f1)
VMLINUZ_SIZE=$(du -h "$OUTPUT_DIR/${OUTPUT_BASE}-vmlinuz" | cut -f1)
CONFIG_SIZE=$(du -h "$OUTPUT_DIR/${OUTPUT_BASE}.config" | cut -f1)
DTB_SIZE=$(du -h "$OUTPUT_DIR/${OUTPUT_BASE_DTB}.dtb" | cut -f1)
echo ""
echo "==========================================================="
echo "Build complete! Artifacts:"
echo "  Boot Image:    $OUTPUT_IMG ($BOOT_SIZE)"
echo "  Kernel Image:  $OUTPUT_DIR/${OUTPUT_BASE}-vmlinuz ($VMLINUZ_SIZE)"
echo "  Device Tree:   $OUTPUT_DIR/${OUTPUT_BASE_DTB}.dtb ($DTB_SIZE)"
echo "  Config File:   $OUTPUT_DIR/${OUTPUT_BASE}.config ($CONFIG_SIZE)"
echo "==========================================================="
