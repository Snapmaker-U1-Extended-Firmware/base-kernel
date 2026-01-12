#!/usr/bin/env bash
# Download and prepare rootfs for QEMU testing

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

ROOTFS_DIR="$ROOT_DIR/tmp/base-debian-os"
GITHUB_REPO="Snapmaker-U1-Extended-Firmware/base-debian-os"
IMG_SYMLINK="$ROOTFS_DIR/rootfs.img"

show_usage() {
  echo "Usage: $0 [command] [version]"
  echo ""
  echo "Commands:"
  echo "  download [version]  Download rootfs tarball (default: latest)"
  echo "  image               Create disk image from downloaded tarball"
  echo "  modules             Update kernel modules in existing rootfs image"
  echo "  (no command)        Download and create image (default behavior)"
  echo ""
  echo "Examples:"
  echo "  $0 download           # Download latest"
  echo "  $0 download v1.0.0    # Download specific version"
  echo "  $0 image              # Create disk image from tarball"
  echo "  $0 modules            # Update modules in rootfs"
  echo "  $0                    # Download latest and create image"
  exit 0
}

# Download rootfs tarball from GitHub releases
download_rootfs() {
  local release_version="$1"
  local release_tag
  local release_info
  local asset_url
  local asset_name
  local tgz_path
  
  mkdir -p "$ROOTFS_DIR"
  
  # Determine release to download
  if [[ "$release_version" == "latest" ]]; then
    echo ">> Fetching latest release info from GitHub..." >&2
    release_info=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest")
    release_tag=$(echo "$release_info" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
    
    if [[ -z "$release_tag" ]]; then
      echo "Error: Failed to fetch latest release" >&2
      return 1
    fi
    
    echo ">> Latest release: $release_tag" >&2
  else
    release_tag="$release_version"
    echo ">> Using release: $release_tag" >&2
    release_info=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/tags/$release_tag")
  fi
  
  # Find .tgz asset URL
  echo ">> Fetching release assets..." >&2
  asset_url=$(echo "$release_info" | grep -o '"browser_download_url": *"[^"]*\.tgz"' | head -1 | cut -d'"' -f4)
  
  if [[ -z "$asset_url" ]]; then
    echo "Error: No .tgz asset found for release $release_tag" >&2
    return 1
  fi
  
  asset_name=$(basename "$asset_url")
  tgz_path="$ROOTFS_DIR/$asset_name"
  
  # Download tarball if needed
  if [[ ! -f "$tgz_path" ]]; then
    echo ">> Downloading rootfs tarball from $asset_url..." >&2
    if command -v wget &> /dev/null; then
      wget -O "$tgz_path.tmp" "$asset_url"
    elif command -v curl &> /dev/null; then
      curl -L -o "$tgz_path.tmp" "$asset_url"
    else
      echo "Error: Neither wget nor curl found" >&2
      return 1
    fi
    mv "$tgz_path.tmp" "$tgz_path"
    echo ">> Downloaded: $tgz_path" >&2
  else
    echo ">> Using cached tarball: $tgz_path" >&2
  fi
  
  # Export for use by create function
  echo "$tgz_path"
  return 0
}

# Create rootfs disk image from tarball
create_rootfs_image() {
  local tgz_path="$1"
  local extract_dir="$ROOTFS_DIR/extract"
  
  if [[ ! -f "$tgz_path" ]]; then
    echo "Error: Tarball not found: $tgz_path"
    return 1
  fi
  
  # Derive image name from tarball (e.g., base-debian-os-v1.0.0.tgz -> base-debian-os-v1.0.0.img)
  local tgz_basename
  tgz_basename=$(basename "$tgz_path" .tgz)
  local img_path="$ROOTFS_DIR/${tgz_basename}.img"
  
  if [[ -f "$img_path" ]]; then
    echo ">> Disk image already exists: $img_path"
  else
    echo ">> Creating disk image (4GB): $img_path"
    dd if=/dev/zero of="$img_path.tmp" bs=1M count=4096 status=progress
    
    # Extract tarball to temporary directory
    echo ">> Extracting rootfs tarball..."
    mkdir -p "$extract_dir"
    tar --warning=no-file-ignored --exclude='./dev/*' -xzf "$tgz_path" -C "$extract_dir"
    
    # Create basic /dev structure
    mkdir -p "$extract_dir/dev"
    
    # Allow root login without password
    echo ">> Configuring passwordless root login..."
    sed -i "s|^root:[^:]*:|root::|" "$extract_dir/etc/shadow"
    
    # Enable nullok in PAM to allow empty passwords
    if [[ -f "$extract_dir/etc/pam.d/common-auth" ]]; then
      sed -i 's/\(pam_unix\.so\)/\1 nullok/' "$extract_dir/etc/pam.d/common-auth"
    fi
    
    # Configure network with DHCP
    echo ">> Configuring DHCP for eth0..."
    mkdir -p "$extract_dir/etc/systemd/network"
    cat > "$extract_dir/etc/systemd/network/20-eth0.network" << 'EOF'
[Match]
Name=eth0

[Network]
DHCP=yes
EOF
    
    # Format with ext4 and populate from directory
    echo ">> Formatting with ext4 and populating from extracted files..."
    mkfs.ext4 -F -d "$extract_dir" "$img_path.tmp"
    
    # Clean up extraction directory
    echo ">> Cleaning up temporary files..."
    rm -rf "$extract_dir"
    
    # Move to final location
    mv "$img_path.tmp" "$img_path"
    
    echo ">> Created disk image: $img_path"
  fi
  
  # Create/update symlink
  echo ">> Creating symlink: rootfs.img -> ${tgz_basename}.img"
  ln -sf "${tgz_basename}.img" "$IMG_SYMLINK"
  
  return 0
}

# Create modules disk image from kernel modules tarball
update_rootfs_modules() {
  # Find newest modules tarball in output directory
  local output_dir="$ROOT_DIR/output"
  if [[ ! -d "$output_dir" ]]; then
    echo "Error: Output directory not found: $output_dir"
    echo "Build kernel modules first"
    return 1
  fi
  
  # Find newest -devel-*-modules.tar.gz
  shopt -s nullglob
  local modules_tarballs=("$output_dir"/*-devel-*-modules.tar.gz)
  shopt -u nullglob
  
  if [[ ${#modules_tarballs[@]} -eq 0 ]]; then
    echo "Error: No kernel modules tarball found in $output_dir"
    echo "Build kernel first: ./dev.sh make kernel PROFILE=open-devel"
    return 1
  fi
  
  # Find the newest one
  local modules_tar="${modules_tarballs[0]}"
  for tar in "${modules_tarballs[@]}"; do
    [[ "$tar" -nt "$modules_tar" ]] && modules_tar="$tar"
  done
  
  echo ">> Using modules from: $modules_tar"
  
  # Derive image name from modules tarball
  local modules_basename
  modules_basename=$(basename "$modules_tar" .tar.gz)
  local modules_img_path="$ROOTFS_DIR/${modules_basename}.img"
  local modules_symlink="$ROOTFS_DIR/modules.img"
  
  if [[ -f "$modules_img_path" ]]; then
    echo ">> Modules disk image already exists: $modules_img_path"
  else
    # Extract modules tarball to temporary directory
    local extract_dir="$ROOTFS_DIR/extract-modules"
    echo ">> Extracting modules tarball..."
    mkdir -p "$extract_dir"
    tar -xzf "$modules_tar" -C "$extract_dir"
    
    # Create modules disk image (512MB should be plenty for modules)
    echo ">> Creating modules disk image (512MB): $modules_img_path"
    dd if=/dev/zero of="$modules_img_path.tmp" bs=1M count=512 status=progress
    
    # Format with ext4 and MODULES label, populate from directory
    echo ">> Formatting with ext4 (label: MODULES) and populating..."
    mkfs.ext4 -F -L MODULES -d "$extract_dir" "$modules_img_path.tmp"
    
    # Clean up extraction directory
    echo ">> Cleaning up temporary files..."
    rm -rf "$extract_dir"
    
    # Move to final location
    mv "$modules_img_path.tmp" "$modules_img_path"
    
    echo ">> Created modules disk image: $modules_img_path"
  fi
  
  # Create/update symlink
  echo ">> Creating symlink: modules.img -> ${modules_basename}.img"
  ln -sf "${modules_basename}.img" "$modules_symlink"
  
  echo ">> Modules disk ready for virtualization"
  return 0
}

# Main execution
main() {
  local command="${1:-}"
  
  # Handle help
  if [[ "$command" == "help" || "$command" == "--help" || "$command" == "-h" ]]; then
    show_usage
  fi
  
  # Parse command
  case "$command" in
    download)
      shift
      local version="${1:-latest}"
      echo "========================================="
      echo "Downloading rootfs tarball"
      echo "========================================="
      
      tgz_path=$(download_rootfs "$version")
      if [[ $? -ne 0 || -z "$tgz_path" ]]; then
        echo "Error: Failed to download rootfs"
        exit 1
      fi
      
      echo ""
      echo "========================================="
      echo "Download complete: $tgz_path"
      echo "========================================="
      ;;
      
    image)
      echo "========================================="
      echo "Creating rootfs disk image"
      echo "========================================="
      
      # Find most recent tarball
      shopt -s nullglob
      local tarballs=("$ROOTFS_DIR"/*.tgz)
      shopt -u nullglob
      
      if [[ ${#tarballs[@]} -eq 0 ]]; then
        echo "Error: No rootfs tarball found in $ROOTFS_DIR"
        echo "Download one first: $0 download"
        exit 1
      fi
      
      # Find newest tarball
      local tgz_path="${tarballs[0]}"
      for tar in "${tarballs[@]}"; do
        [[ "$tar" -nt "$tgz_path" ]] && tgz_path="$tar"
      done
      
      echo ">> Using tarball: $tgz_path"
      
      if ! create_rootfs_image "$tgz_path"; then
        echo "Error: Failed to create rootfs image"
        exit 1
      fi
      
      echo ""
      echo "========================================="
      echo "Image created successfully"
      echo "========================================="
      ;;
      
    modules)
      echo "========================================="
      echo "Updating kernel modules in rootfs"
      echo "========================================="
      
      if ! update_rootfs_modules; then
        echo "Error: Failed to update modules"
        exit 1
      fi
      
      echo ""
      echo "========================================="
      echo "Modules updated successfully"
      echo "========================================="
      ;;
      
    "")
      # Default: download and create image (backwards compatibility)
      local version="${2:-latest}"
      echo "========================================="
      echo "Preparing rootfs for QEMU"
      echo "========================================="
      
      # Download rootfs tarball
      tgz_path=$(download_rootfs "$version")
      if [[ $? -ne 0 || -z "$tgz_path" ]]; then
        echo "Error: Failed to download rootfs"
        exit 1
      fi
      
      # Create disk image
      if ! create_rootfs_image "$tgz_path"; then
        echo "Error: Failed to create rootfs image"
        exit 1
      fi
      
      echo ""
      echo "========================================="
      echo "Rootfs prepared successfully:"
      echo "  Tarball: $tgz_path"
      echo "  Image:   $IMG_SYMLINK"
      echo ""
      echo "Use with QEMU: ./dev.sh run <kernel.img>"
      echo "========================================="
      ;;
      
    *)
      # Assume it's a version string for backwards compatibility
      local version="$command"
      echo "========================================="
      echo "Preparing rootfs for QEMU"
      echo "========================================="
      
      # Download rootfs tarball
      tgz_path=$(download_rootfs "$version")
      if [[ $? -ne 0 || -z "$tgz_path" ]]; then
        echo "Error: Failed to download rootfs"
        exit 1
      fi
      
      # Create disk image
      if ! create_rootfs_image "$tgz_path"; then
        echo "Error: Failed to create rootfs image"
        exit 1
      fi
      
      echo ""
      echo "========================================="
      echo "Rootfs prepared successfully:"
      echo "  Tarball: $tgz_path"
      echo "  Image:   $IMG_SYMLINK"
      echo ""
      echo "Use with QEMU: ./dev.sh run <kernel.img>"
      echo "========================================="
      ;;
  esac
}

main "$@"
