#!/bin/bash
##
## Package a pre-built sharp.node binary as a .deb for BotDrop.
##
## Creates a fake @img/sharp-android-arm64 npm package that sharp's loader
## (lib/sharp.js) will find via require('@img/sharp-android-arm64').
##
## Usage:
##   ./scripts/package-sharp-addon.sh <sharp.node> [version] [output-dir]
##
## Arguments:
##   sharp.node   Path to the pre-built sharp native addon binary
##   version      Sharp version to match (default: 0.34.5)
##   output-dir   Directory for the output .deb (default: ./debs-output)
##
## Example:
##   # After building sharp.node on the BotDrop device:
##   adb pull /data/data/app.botdrop/files/usr/tmp/sharp-build/node_modules/sharp/build/Release/sharp-android-arm64.node ./sharp.node
##   ./scripts/package-sharp-addon.sh ./sharp.node 0.34.5 ./debs-output
##

set -euo pipefail

SHARP_NODE="${1:-}"
VERSION="${2:-0.34.5}"
OUTPUT_DIR="${3:-./debs-output}"
# Convert to absolute path so it works after cd
OUTPUT_DIR="$(mkdir -p "$OUTPUT_DIR" && cd "$OUTPUT_DIR" && pwd)"

if [[ -z "$SHARP_NODE" ]] || [[ ! -f "$SHARP_NODE" ]]; then
    echo "Usage: $0 <path-to-sharp.node> [version] [output-dir]"
    echo ""
    echo "  sharp.node: Pre-built native addon binary (required)"
    echo "  version:    Sharp version (default: 0.34.5)"
    echo "  output-dir: Output directory (default: ./debs-output)"
    exit 1
fi

ARCH="aarch64"
PKG_NAME="sharp-node-addon"
PREFIX="data/data/app.botdrop/files/usr"
MODULE_DIR="${PREFIX}/lib/node_modules/@img/sharp-android-arm64"

echo "========================================"
echo "  Sharp Node Addon Packager"
echo "========================================"
echo ""
echo "Input binary:  $SHARP_NODE"
echo "Version:       $VERSION"
echo "Architecture:  $ARCH"
echo "Output:        $OUTPUT_DIR"
echo ""

# Verify the input is a valid shared object
if file "$SHARP_NODE" | grep -q "ELF.*aarch64"; then
    echo "Binary: valid ELF aarch64"
elif file "$SHARP_NODE" | grep -q "ELF"; then
    echo "Warning: Binary is ELF but may not be aarch64"
else
    echo "Warning: Binary does not appear to be an ELF shared object"
fi
echo ""

# Create temporary build directory
BUILD_DIR=$(mktemp -d)
trap "rm -rf '$BUILD_DIR'" EXIT

echo "Building package structure..."

# Create the fake npm package directory
mkdir -p "$BUILD_DIR/$MODULE_DIR"

# Copy the native addon - sharp.js looks for @img/sharp-android-arm64/sharp.node
cp "$SHARP_NODE" "$BUILD_DIR/$MODULE_DIR/sharp.node"

# Create package.json for the fake npm package
cat > "$BUILD_DIR/$MODULE_DIR/package.json" << EOF
{
  "name": "@img/sharp-android-arm64",
  "version": "${VERSION}",
  "description": "Pre-built sharp native addon for Android aarch64 (BotDrop)",
  "main": "sharp.node",
  "os": ["android"],
  "cpu": ["arm64"],
  "license": "Apache-2.0"
}
EOF

# Create DEBIAN control directory
mkdir -p "$BUILD_DIR/DEBIAN"

# Calculate installed size (in KB)
INSTALLED_SIZE=$(du -sk "$BUILD_DIR/$MODULE_DIR" | cut -f1)

cat > "$BUILD_DIR/DEBIAN/control" << EOF
Package: ${PKG_NAME}
Version: ${VERSION}
Architecture: ${ARCH}
Maintainer: BotDrop <support@botdrop.app>
Installed-Size: ${INSTALLED_SIZE}
Depends: libvips, glib, libarchive
Description: Pre-built sharp native addon for Node.js on Android/aarch64
 Provides @img/sharp-android-arm64 so that 'npm install sharp --ignore-scripts'
 works without compiling from source. Requires libvips and its dependencies.
EOF

# Create data.tar.xz
echo "Creating data archive..."
(cd "$BUILD_DIR" && tar -cJf "$BUILD_DIR/data.tar.xz" --exclude='DEBIAN' "$PREFIX")

# Create control.tar.xz
echo "Creating control archive..."
(cd "$BUILD_DIR/DEBIAN" && tar -cJf "$BUILD_DIR/control.tar.xz" ./control)

# Create debian-binary
echo "2.0" > "$BUILD_DIR/debian-binary"

# Assemble the .deb
DEB_FILE="${PKG_NAME}_${VERSION}_${ARCH}.deb"
mkdir -p "$OUTPUT_DIR"

echo "Assembling .deb package..."
(cd "$BUILD_DIR" && ar cr "$OUTPUT_DIR/$DEB_FILE" debian-binary control.tar.xz data.tar.xz)

echo ""
echo "========================================"
echo "  Package Created Successfully"
echo "========================================"
echo ""
echo "Package: $OUTPUT_DIR/$DEB_FILE"
echo "Size:    $(du -h "$OUTPUT_DIR/$DEB_FILE" | cut -f1)"
echo ""
echo "Contents:"
echo "  $MODULE_DIR/"
echo "  +-- package.json"
echo "  +-- sharp.node"
echo ""
echo "Install with:"
echo "  apt install ./$DEB_FILE"
echo "  npm install sharp --ignore-scripts"
echo ""
echo "========================================"
