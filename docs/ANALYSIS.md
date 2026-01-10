# Snapmaker U1 Boot Partition Analysis

## Overview

This directory contains the extracted boot_b partition image and its components from the Snapmaker U1 device.

**Date extracted**: 2026-01-09 16:21:00 (based on FIT image timestamp)

## Boot Image Structure

The boot partition uses **U-Boot FIT (Flattened Image Tree)** format, confirmed by:
```
file boot_b.img
> Device Tree Blob version 17, size=1280
```

### FIT Image Components

The FIT image contains 3 components:

#### 1. Flat Device Tree (fdt)
- **Type**: Flat Device Tree
- **Size**: 143,777 bytes (140.41 KiB)
- **Compression**: Uncompressed
- **Architecture**: AArch64
- **Load Address**: 0xffffff00
- **Hash**: `b529c4c8d3986d2ecf6b868b2464c38443871ade8697a77e53dfa9282e38eb52` (SHA256)

**Board Identification**:
- **Model**: "Rockchip RK3562 EVB2 DDR4 V10 Board"
- **Compatible**: `"rockchip,rk3562-evb2-ddr4-v10", "rockchip,rk3562"`

**Note**: This DTB matches the one analyzed in `../research-u1-dtb-exploration/dts/boot.img__off00000800.dts`

#### 2. Kernel Image (kernel)
- **Type**: Kernel Image (Linux)
- **Size (compressed)**: 16,104,235 bytes (15.36 MiB)
- **Compression**: **LZ4**
- **Architecture**: AArch64
- **OS**: Linux
- **Load Address**: 0xffffff01
- **Entry Point**: 0xffffff01
- **Hash**: `3fb6d49b179544cefec63fb17bf772f2ac6342bbed722d4394271dc5449609da` (SHA256)

**Kernel Format**: Linux kernel ARM64 boot executable Image (verified via decompression header check)

**Note**: The kernel uses LZ4 compression. Standard Linux kernel builds produce uncompressed `Image` files which must be compressed with `lz4` before FIT packaging.

#### 3. Resource Image (resource)
- **Type**: Multi-File Image
- **Size**: 1,068,544 bytes (1.02 MiB)
- **Compression**: Uncompressed
- **Hash**: `e2d736ae504b865808ae0601f52a33a4b8017567edb6f92750f8c40d1341a499` (SHA256)

**Purpose**: Contains display resources (logos, boot panels, etc.). This should be preserved unchanged when building custom kernels to maintain display functionality.

### FIT Configuration

**Default Configuration**: `conf`
- **Kernel**: kernel
- **FDT**: fdt
- **No ramdisk/initramfs**: The FIT does not include an initrd component

## Extracted Files

- `boot_b.img` - Original boot partition dump (18 MiB)
- `fdt.dtb` - Extracted device tree blob (140 KiB)
- `fdt.dts` - Decompiled device tree source
- `kernel.lz4` - Extracted LZ4-compressed kernel image (15.36 MiB)
- `resource.img` - Extracted resource multi-file image (1.02 MiB)

## Build Requirements for Custom Kernels

To build a compatible replacement kernel, you need:

1. ✅ **Kernel source**: Linux 6.1.99 (as identified in `../research-u1-custom-os/u1-stock-kernel.config`)
2. ✅ **Stock config**: Available at `../research-u1-custom-os/u1-stock-kernel.config`
3. ✅ **Device tree**: Use `fdt.dtb` or build from `../research-u1-dtb-exploration/dts/boot.img__off00000800.dts`
4. ✅ **Toolchain**: aarch64 cross-compiler (GCC 10.3.1+)
5. ✅ **FIT tools**: `mkimage` from u-boot-tools package
6. ✅ **Compression**: `lz4` utility

### Build Process Summary

1. Build kernel: `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image`
2. Compress kernel: `lz4 -9 -f arch/arm64/boot/Image kernel.lz4`
3. Build DTB: `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dtbs`
4. Create FIT image source file (`.its`) with:
   - Load addresses: kernel=0xffffff01, fdt=0xffffff00
   - Compression: kernel=lz4, fdt=none
   - Include resource.img unchanged
5. Build FIT: `mkimage -f boot.its boot.img`

## Key Findings

- ✅ **No initramfs required**: The boot configuration boots directly from rootfs partition
- ✅ **LZ4 compression mandatory**: Kernel must be LZ4-compressed, not gzip or uncompressed
- ✅ **Resource image must be preserved**: Keep resource.img from original FIT to maintain display functionality
- ✅ **Load addresses are non-standard**: Using 0xffffff01/0xffffff00 instead of typical physical addresses
- ✅ **Board uses EVB2 DTB**: RK3562 EVB2 DDR4 V10 reference design

## Cross-References

- Stock kernel config: `../research-u1-custom-os/u1-stock-kernel.config`
- Device tree analysis: `../research-u1-dtb-exploration/docs/dts_analysis.md`
- Kernel build guide: `../research-u1-dtb-exploration/docs/rk3562_kernel_build_guide.md`
- A/B boot control: `../research-u1-custom-os/docs/controlling_AB_boot.md`
