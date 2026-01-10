# Snapmaker U1 Custom Kernel Builder

Custom kernel builds for Snapmaker U1 3D Printer with support for containers, virtualization, and debugging.

## Overview

This project builds custom Linux kernels compatible with the Snapmaker U1 3D printer. The kernel is built from Rockchip's official sources with Snapmaker-specific device tree and configurations.

**Features:**

- Multiple build profiles (basic, extended, with/without debugging)
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
```

This downloads the stock U1 firmware (~200MB) and extracts:
- `tmp/proprietary/resource.img` - Boot resources (logo, etc.)

And clones the Rockchip kernel source to `rockchip-kernel/`.

## Quick Start

### Build Kernel

```shell
./dev.sh make kernel PROFILE=extended-devel KVER=6.1
```

### Test in QEMU

```shell
./dev.sh launch output/kernel-extended-devel-6.1-20260110-302aee0.img
```

Press `Ctrl-A X` to exit QEMU.

## Build Profiles

Four profiles are available, each building on the previous:

### basic

- Minimal kernel for hardware boot
- Stock Snapmaker U1 configuration
- No additional features

### basic-devel

- `basic` + debugging support
- CONFIG_DEBUG_INFO=y
- CONFIG_DEBUG_KERNEL=y
- CONFIG_DEBUG_FS=y

### extended

- `basic` + container/virtualization support
- Docker/Podman support (namespaces, cgroups, veth, bridge, overlay fs)
- QEMU support (virtio drivers, PL011 serial, PL031 RTC)
- MACVLAN networking

### extended-devel

- `extended` + debugging support
- Full debugging + containers + virtualization

## Kernel Versions

- **6.1** (default) - rockchip-linux/kernel.git branch `develop-6.1`


## Build System

### Make Targets

```shell
./dev.sh make help                    # Show all targets
./dev.sh make kernel PROFILE=extended KVER=6.1
./dev.sh make qemu PROFILE=extended   # Build and launch QEMU
./dev.sh make clean                   # Remove build artifacts
```

### Direct Script Usage

Advanced users can call scripts directly:

```shell
./dev.sh ./scripts/build-kernel.sh 6.1 extended-devel output/kernel.img
./dev.sh ./scripts/launch-qemu.sh output/kernel.img
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

Launches QEMU with the built kernel.

**Usage:**

```shell
./dev.sh ./scripts/launch-qemu.sh <boot.img> [qemu-args...]
```

**Features:**

- ARM64 Cortex-A72 emulation
- 2GB RAM
- PL011 UART console
- Serial output to stdio

**Exit:** Press `Ctrl-A X`

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
KERNEL_PROFILES=(basic basic-devel extended extended-devel my-custom)
```

### Modifying Device Tree

Edit [config/snapmaker-u1-stock.dts](config/snapmaker-u1-stock.dts). Changes will be copied to the kernel tree during build.

### Debugging Builds

Use `-devel` profiles for debug symbols and additional diagnostics:

```shell
./dev.sh make kernel PROFILE=basic-devel KVER=6.1
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

Ensure you're using an `extended` or `extended-devel` profile (requires virtio drivers).

## References

- [Rockchip Kernel Source](https://github.com/rockchip-linux/kernel)
- [Snapmaker U1 Documentation](https://wiki.snapmaker.com/en/snapmaker_u1)
- [U-Boot FIT Image Format](https://github.com/u-boot/u-boot/blob/master/doc/uImage.FIT/howto.txt)
