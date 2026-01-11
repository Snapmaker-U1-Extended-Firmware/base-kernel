include vars.mk

# ================= Configuration =================

# Accept KVER as user-facing parameter, map to KERNEL_VERSION internally
KERNEL_VERSION := $(or $(KVER),6.1)
BUILD_PROFILE := $(or $(PROFILE),open)
OUTPUT_DIR ?= output

KERNEL_PROFILES := open open-devel

# Force override VERSION to prevent command-line pollution of kernel build
override VERSION :=

# Generate version tag (use GIT_VERSION from environment if provided, e.g., in CI)
BUILD_VERSION := $(or $(GIT_VERSION),$(shell date +%Y%m%d)-$(shell git rev-parse --short HEAD 2>/dev/null || echo 'local'))

# Output files
KERNEL_IMG := $(OUTPUT_DIR)/kernel-$(BUILD_PROFILE)-$(KERNEL_VERSION)-$(BUILD_VERSION)-u1-boot.img
KERNEL_VMLINUZ := $(OUTPUT_DIR)/kernel-$(BUILD_PROFILE)-$(KERNEL_VERSION)-$(BUILD_VERSION)-vmlinuz
KERNEL_DTB := $(OUTPUT_DIR)/kernel-$(BUILD_PROFILE)-$(KERNEL_VERSION)-$(BUILD_VERSION)-u1.dtb
KERNEL_CONFIG := $(OUTPUT_DIR)/kernel-$(BUILD_PROFILE)-$(KERNEL_VERSION)-$(BUILD_VERSION).config
KERNEL_MODULES := $(OUTPUT_DIR)/kernel-$(BUILD_PROFILE)-$(KERNEL_VERSION)-$(BUILD_VERSION)-modules.tar.gz

# ================= Help =================

.PHONY: help
help:
	@echo "Snapmaker U1 Custom Kernel Build System"
	@echo ""
	@echo "Usage:"
	@echo "  make kernel PROFILE=<profile> [KVER=<version>] [OUTPUT_DIR=<dir>]"
	@echo "  make clean"
	@echo ""
	@echo "Kernel Profiles:"
	@echo "  open       - Docker/Container + QEMU/KVM support"
	@echo "  open-devel - Open + debugging and development tools"
	@echo ""
	@echo "Variables:"
	@echo "  PROFILE        - Build profile (default: $(BUILD_PROFILE))"
	@echo "  KVER           - Kernel version: 6.1 or 6.6 (default: $(KERNEL_VERSION))"
	@echo "  OUTPUT_DIR     - Output directory (default: $(OUTPUT_DIR))"
	@echo ""
	@echo "Examples:"
	@echo "  make kernel PROFILE=open-devel"
	@echo "  make kernel PROFILE=open KVER=6.1"
	@echo ""
	@echo "Launch QEMU:"
	@echo "  make qemu PROFILE=open-devel [KVER=6.1]"

# ================= Kernel Build =================

.PHONY: clone-kernel
clone-kernel:
	@./scripts/clone-rockchip-kernel.sh $(KERNEL_VERSION)

# Kernel build should always run when requested
# Dependencies are complex (kernel sources, configs, etc.) so we use .PHONY
.PHONY: kernel
kernel: clone-kernel
	@echo "Building kernel $(KERNEL_VERSION) with profile $(BUILD_PROFILE)..."
ifeq ($(filter $(BUILD_PROFILE),$(KERNEL_PROFILES)),)
	@echo "Error: Invalid profile '$(BUILD_PROFILE)'"
	@echo "Available profiles: $(KERNEL_PROFILES)"
	@exit 1
endif
	@mkdir -p $(OUTPUT_DIR)
	@./scripts/build-kernel.sh $(KERNEL_VERSION) $(BUILD_PROFILE) $(KERNEL_IMG)

# ================= QEMU Launch =================

.PHONY: qemu
qemu: kernel
	@./scripts/launch-qemu.sh $(KERNEL_VMLINUZ)

# ================= Clean =================

.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(OUTPUT_DIR)
	@rm -rf tmp/kernel-*
	@rm -rf tmp/kernel-artifacts
	@echo "Clean complete."

.PHONY: clean-all
clean-all: clean
	@echo "Cleaning kernel source..."
	@rm -rf rockchip-kernel
	@echo "Clean all complete."

# ================= Info =================

.PHONY: version
version:
	@echo "$(VERSION)"

.PHONY: profiles
profiles:
	@echo "Available kernel profiles:"
	@echo "  $(KERNEL_PROFILES)"

# ================= Firmware Extraction =================

.PHONY: tools
tools: tools/rk2918_tools tools/upfile

tools/%: FORCE
	make -C $@

.PHONY: firmware
firmware: tmp/firmware/$(FIRMWARE_FILE)

tmp/firmware/$(FIRMWARE_FILE):
	@mkdir -p tmp/firmware
	wget -O $@.tmp "https://public.resource.snapmaker.com/firmware/U1/$(FIRMWARE_FILE)"
	echo "$(FIRMWARE_SHA256)  $@.tmp" | sha256sum -c --quiet
	mv $@.tmp $@

.PHONY: extract
extract: tmp/firmware/$(FIRMWARE_FILE) tools
	./scripts/extract_squashfs.sh $< tmp/extracted

.PHONY: extract-proprietary
extract-proprietary: tmp/firmware/$(FIRMWARE_FILE) tools
	./scripts/extract-proprietary.sh

.PHONY: FORCE
FORCE:
