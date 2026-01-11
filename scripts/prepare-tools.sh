#!/usr/bin/env bash
# Build firmware extraction tools

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================="
echo "Preparing extraction tools"
echo "========================================="

# Check if tools already built
if [[ -f "$ROOT_DIR/tools/upfile/upfile" ]] && [[ -f "$ROOT_DIR/tools/rk2918_tools/afptool" ]]; then
    echo ">> Extraction tools already built"
    exit 0
fi

# Build extraction tools
echo ">> Building extraction tools..."
make -C "$ROOT_DIR/tools/upfile" -j"$(nproc)"
make -C "$ROOT_DIR/tools/rk2918_tools" -j"$(nproc)"

echo ""
echo "========================================="
echo "Tools built successfully:"
echo "  - tools/upfile/upfile"
echo "  - tools/rk2918_tools/afptool"
echo "========================================="
