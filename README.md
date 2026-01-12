# Snapmaker U1 Custom Kernel Builder

Custom kernel builds for Snapmaker U1 3D Printer

## Overview

This project builds custom Linux kernels compatible with the Snapmaker U1 3D printer. 
Kernel is built from Rockchip's official sources with Snapmaker-specific device tree and configurations. 

All actions are performed through the `dev.sh` script. 
Try not to run any other scripts or commands directly because it shouldn't be necessary for normal workflows.

## Prerequisites

- Docker or Podman
- ~5GiB free disk space
- Linux host (it's containerized, but we haven't tested macOS or WSL)
- (Optional) QEMU with KVM support for testing kernels in virtual machines

## First time setup

Also use these commands with more arguments to update tools or kernel source later. 
Use `./dev.sh help` and `./dev.sh <command> help` for more information. 

```shell
./dev.sh prepare tools
./dev.sh prepare kernel
./dev.sh prepare proprietary
./dev.sh prepare rootfs       # Optional, only needed for running the kernel in virutal machines
```

## Build The Kernel

```shell
# Build production kernel
./dev.sh make kernel
# OR:
./dev.sh make kernel PROFILE=open

# Build a specific version of development kernel (for virtualization testing)
./dev.sh make kernel PROFILE=open-devel KVER=6.1
```

## Existing Build Profiles

### open

Intended for production use on Snapmaker U1 printer instead of stock kernel.

- Uses Snapmaker's stock kernel configuration as base
- Enables Rockchip-specific drivers for display and security features
- Adds support for being containerization and virtualization host
- Adds support for running as virtualized guest
- Adds networking and storage drivers

### open-devel

Intended for development, debugging, and testing on hardware and in virtual machine.

- All features from `open` profile
- Adds Kernel Debugging and development tools
- Disables DRM and security features necessary to run in virtual machine

Don't use `open-devel` profile in production because it disables important drivers. 
Always use `open-devel` profile when testing in virtualization environments. 

## Kernel Versions

Currently only 6.1. series works. 
In the future we'll be trying to go for 6.6 and possibly mainline but that's a long shot because of missing Rockchip drivers.

## Build System

### Make Targets

```shell
./dev.sh make help                              # Show all targets
./dev.sh make kernel PROFILE=open KVER=6.1      # Production build
./dev.sh make kernel PROFILE=open-devel KVER=6.1 # Development build
./dev.sh make clean                             # Remove build artifacts
```

### Testing In Virtualization

Currently only supports QEMU and requires Linux host with KVM and virtio support. 
Instructions for testing on Mac or Windows are very much welcome; please contribute! 

```shell
./dev.sh prepare rootfs download    # Download latest rootfs tarball
./dev.sh prepare rootfs image       # Create disk image from downloaded tarball
./dev.sh prepare rootfs modules     # Update kernel modules in existing rootfs
./dev.sh prepare rootfs v1.0.0      # Download specific version and create image
```

```shell
# Note: Use -devel profile for virtualization compatibility

# Auto-detect newest -devel kernel with default profile
./dev.sh run

# Auto-detect with specific profile
./dev.sh run qemu-gui

# Explicit kernel with default profile
./dev.sh run output/kernel-open-devel-6.1-20260111-abc1234-vmlinuz

# GUI profile (with virtio-gpu graphics)
./dev.sh run qemu-gui output/kernel-open-devel-*-vmlinuz
```

Press `Ctrl-A X` to exit QEMU (console profile) or `Ctrl-Alt-G` to release mouse grab (GUI profile).

## Build Scripts

These scripts are not intended to be run directly. Use `./dev.sh` as the main entry point.

### scripts/clone-rockchip-kernel.sh

Clones the Rockchip kernel source. Run this once before building and whenever you want to update the source.

```shell
./dev.sh prepare kernel 6.1
```

### scripts/build-kernel.sh

Main kernel build. Build and starts container to ensure consistent build environment.

```shell
./dev.sh make kernel PROFILE=open KVER=6.1
```

**Process:**

1. Patches kernel version
2. Copies device tree
3. Configures kernel with snapmaker-u1-stock.config
4. Applies profile-specific config fragments
5. Builds kernel, DTB, and modules
6. Patches proprietary modules
7. Creates FIT boot image

### scripts/kernel-config.sh

Centralized configuration (sourced by other scripts).

**Defines:**

- `KERNEL_PROFILES` - Associative array of config fragments
- `get_kernel_branch()` - Maps version to git branch
- `validate_profile()` - Validates profile names

### scripts/run-virt.sh

Runs built kernels in virtual machines for testing.
Optionally uses rootfs image to also test from userspace.

MUST use `-devel` kernel profile because standard profiles include Rockchip-specific features which can't be virtualized.

#### Virtualization Profiles

Two QEMU on Linux profiles are available (selected via profile argument to run command):

##### qemu-console (default)

No graphics, serial console only. 
Use when quickly testing if the new kernel boots. 

##### qemu-gui

GUI profile with graphics

##### Usage

```shell
# First build -devel kernel
./dev.sh make kernel PROFILE=open-devel

# Get and prepare rootfs for VM testing
./dev.sh prepare rootfs download
./dev.sh prepare rootfs image
./dev.sh prepare rootfs modules
```

At this point rootfs has been downloaded, converted to disk image, init patched to preload kernel modules from modules.img disk.

```shell
# Run qemu virtual machine with newest *-devel kernel from output/ directory
./dev.sh run

# Run with graphics enabled
./dev.sh run qemu-gui

# Run an alternative kernel
./dev.sh run output/kernel-open-devel-*-vmlinuz
```

###### Interactive Console Controls for QEMU

- **Console-only profile**
  - **Ctrl-A X** - Exit QEMU
  - **Ctrl-A C** - Switch to QEMU monitor console
- **GUI profile**
  - **Ctrl-Alt-G** - Release mouse/keyboard grab
  - **Ctrl-Alt-1** - Switch to virtual console
  - **Ctrl-Alt-2** - Switch to QEMU monitor

## Development

### Modifying Kernel Configurations

Create or edit profiles in `config/profile-*.config`:
Then add the profile to `scripts/kernel-config.sh`:

```shell
KERNEL_PROFILES=(open open-devel my-custom)
```

### Modifying Device Tree

Edit [config/snapmaker-u1-stock.dts](config/snapmaker-u1-stock.dts). Changes will be copied to the kernel tree during build.

### Debugging Builds

Use the `open-devel` profile for debug symbols, additional diagnostics, and virtualization compatibility:

```shell
./dev.sh make kernel PROFILE=open-devel KVER=6.1
```

Build artifacts remain in `tmp/kernel-*` on failure for inspection.

### Troubleshooting

#### Kernel source not found

```text
Error: Kernel source not found at rockchip-kernel
```

Solution: Clone the kernel source first

```shell
./dev.sh prepare kernel 6.1
```

#### Build failures

Check [tmp/kernel-$$](../tmp/) for build logs. The build directory persists on error.

#### Kernel doesn't boot in virtualization

Ensure you're using the `open-devel` profile (requires VirtIO drivers and has Rockchip DRM/security disabled):

```shell
./dev.sh make kernel PROFILE=open-devel KVER=6.1
./dev.sh run output/kernel-open-devel-6.1-*-vmlinuz
```
