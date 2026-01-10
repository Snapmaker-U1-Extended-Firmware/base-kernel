#!/bin/bash
# Kernel build configuration
# Source this file, don't execute it

KERNEL_GIT_URL="https://github.com/rockchip-linux/kernel.git"
KERNEL_DIR_NAME="rockchip-kernel"

ARCH="arm64"
CROSS_COMPILE="aarch64-linux-gnu-"

# Profile definitions
KERNEL_PROFILES=(basic basic-devel extended extended-devel)

# Get profile config file path
get_profile_config() {
  local profile="$1"
  local repo_root="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  echo "$repo_root/config/profile-$profile.config"
}

# Version-specific settings
get_kernel_branch() {
  case "$1" in
    6.1) echo "develop-6.1" ;;
    6.6) echo "develop-6.6" ;;
    *) echo "Error: Invalid kernel version $1. Supported: 6.1, 6.6" >&2; exit 1 ;;
  esac
}

# Validate profile
validate_profile() {
  local profile="$1"
  local valid=false
  for p in "${KERNEL_PROFILES[@]}"; do
    if [[ "$p" == "$profile" ]]; then
      valid=true
      break
    fi
  done
  
  if [[ "$valid" != "true" ]]; then
    echo "Error: Invalid build profile '$profile'" >&2
    echo "Available profiles: ${KERNEL_PROFILES[*]}" >&2
    exit 1
  fi
}
