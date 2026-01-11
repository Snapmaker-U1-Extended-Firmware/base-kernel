# Snapmaker U1 Custom Kernel Builder

Custom kernel builds for Snapmaker U1 3D Printer with support for containers, virtualization, and debugging.

## Overview

This project builds custom Linux kernels compatible with the Snapmaker U1 3D printer. The kernel is built from Rockchip's official sources with Snapmaker-specific device tree and configurations.

**Features:**

- Multiple build profiles (open, open-devel)
- Docker/container support (cgroups, namespaces, overlay fs)
- QEMU/KVM virtualization support
- Automated FIT image creation for U-Boot
- Stock firmware compatibility

## Prerequisites

**Required:**

- Docker or Podman
- ~3GiB free disk space
- Linux host (it's containerized, but I haven't tested Windows/Mac)

**First time setup:**

```shell
./dev.sh prepare proprietary
./dev.sh prepare kernel 6.1
./dev.sh prepare rootfs       # Optional: for QEMU testing
```

This downloads the stock U1 firmware (~200MB) and extracts:
- `tmp/proprietary/resource.img` - Boot resources (logo, etc.)

And clones the Rockchip kernel source to `rockchip-kernel/`.

## Quick Start

### Build Kernel

```shell
./dev.sh make kernel PROFILE=open-devel KVER=6.1
```

### Test in QEMU

```shell
./dev.sh launch output/kernel-open-devel-6.1-20260110-302aee0-u1-boot.img
```

Press `Ctrl-A X` to exit QEMU.

## Build Profiles

Two profiles are available:

### open

- Stock Snapmaker U1 configuration
- Docker/Podman support (namespaces, cgroups, veth, bridge, overlay fs)
- QEMU support (virtio drivers, PL011 serial, PL031 RTC)
- MACVLAN networking

### open-devel

- `open` + debugging and development tools
- CONFIG_DEBUG_INFO=y
- CONFIG_DEBUG_KERNEL=y
- CONFIG_DEBUG_FS=y

## Kernel Versions

- **6.1** (default) - rockchip-linux/kernel.git branch `develop-6.1`


## Build System

### Make Targets

```shell
./dev.sh make help                    # Show all targets
./dev.sh make kernel PROFILE=open KVER=6.1
./dev.sh make qemu PROFILE=open   # Build and launch QEMU
./dev.sh make clean                   # Remove build artifacts
```

## Build Scripts

### scripts/clone-rockchip-kernel.sh

Clones the Rockchip kernel source. Run this once before building.

**Usage:**

```shell
./dev.sh ./scripts/clone-rockchip-kernel.sh <kernel-version>
```

### scripts/build-kernel.sh

Main kernel build orchestrator.

**Usage:**

```shell
./dev.sh ./scripts/build-kernel.sh <kernel-version> <build-profile> <output.img>
```

**Process:**

1. Patches kernel version
2. Copies device tree
3. Configures kernel with snapmaker-u1-stock.config
4. Applies profile-specific config fragments
5. Builds kernel, DTB, and modules
6. Patches proprietary modules
7. Creates FIT boot image

### scripts/launch-qemu.sh

**EXPERIMENTAL:** Launches QEMU for kernel testing (limited functionality).

**Known Limitations:**

- The kernel is built specifically for Rockchip RK3562 hardware with Cortex-A53 CPUs
- Userspace binaries may crash due to CPU feature mismatches between real hardware and QEMU emulation
- QEMU testing is primarily useful for validating kernel boot and driver loading
- Full system testing requires actual Snapmaker U1 hardware

**Usage:**

```shell
# Interactive mode (run directly in your terminal):
./dev.sh launch output/kernel-open-devel-6.1-YYYYMMDD-hash-vmlinuz

# Or for quick alias:
./dev.sh launch output/kernel-open-devel-*-vmlinuz
```

**Features:**

- ARM64 Cortex-A53 emulation (4 cores, matching RK3562)
- QEMU virt machine
- 2GB RAM
- PL011 UART console on ttyAMA0
- Automatic rootfs detection (if prepared with `./dev.sh prepare rootfs`)
- VirtIO block device for rootfs (/dev/vda)

**Interactive Console Controls:**

- **Ctrl-A X** - Exit QEMU
- **Ctrl-A C** - Switch between serial console and QEMU monitor
- **Ctrl-A H** - Help for QEMU monitor commands

**Important:** This script must be run directly in your terminal for interactive console access.
The serial console will not work if launched through background processes or automation tools.

**Non-Interactive Mode:**

For automated testing or CI/CD, you can redirect serial output to a pty:

```shell
./dev.sh launch output/kernel-*-vmlinuz -serial pty -nographic
# QEMU will print: "char device redirected to /dev/pts/N (label serial0)"
# Connect with: tio /dev/pts/N
```

**Note:** The FIT image (`*-u1-boot.img`) is designed for U-Boot bootloader on the actual
hardware. For QEMU testing, always use the raw kernel image (`*-vmlinuz`).

### scripts/kernel-config.sh

Centralized configuration (sourced by other scripts).

**Defines:**

- `KERNEL_PROFILES` - Associative array of config fragments
- `get_kernel_branch()` - Maps version to git branch
- `validate_profile()` - Validates profile names

## Development

### Adding Config Options

Create or edit profile files in `config/profile-*.config`:

```shell
# config/profile-my-custom.config
# Additions to snapmaker-u1-stock.config

CONFIG_MY_OPTION=y
CONFIG_ANOTHER=m
```

Then add the profile to `scripts/kernel-config.sh`:

```shell
KERNEL_PROFILES=(open open-devel my-custom)
```

### Modifying Device Tree

Edit [config/snapmaker-u1-stock.dts](config/snapmaker-u1-stock.dts). Changes will be copied to the kernel tree during build.

### Debugging Builds

Use the `-devel` profile for debug symbols and additional diagnostics:

```shell
./dev.sh make kernel PROFILE=open-devel KVER=6.1
```

Build artifacts remain in `tmp/kernel-*` on failure for inspection.

## CI/CD

GitHub Actions builds all profiles on push to `main` and publishes kernel artifacts as releases with version tag `YYYYMMDD-{git-sha}`.

See [.github/workflows/build.yaml](.github/workflows/build.yaml) for the full workflow.

## Troubleshooting

### Kernel source not found

```text
Error: Kernel source not found at rockchip-kernel
Run: ./dev.sh ./scripts/clone-rockchip-kernel.sh 6.1
```

**Solution:** Clone the kernel source first.

### Build failures

Check [tmp/kernel-$$](../tmp/) for build logs. The build directory persists on error.

### QEMU doesn't boot

Ensure you're using the `open` or `open-devel` profile (requires virtio drivers).

## References

- [Rockchip Kernel Source](https://github.com/rockchip-linux/kernel)
- [Snapmaker U1 Documentation](https://wiki.snapmaker.com/en/snapmaker_u1)
- [U-Boot FIT Image Format](https://github.com/u-boot/u-boot/blob/master/doc/uImage.FIT/howto.txt)
