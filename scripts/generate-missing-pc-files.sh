#!/bin/bash
##
## Generate missing .pc (pkg-config) files for BotDrop bootstrap packages.
##
## The BotDrop bootstrap includes runtime libraries but not all .pc files.
## These are only needed when compiling native addons on-device (e.g. sharp).
## End users who install pre-built .debs do NOT need to run this script.
##
## Usage (on BotDrop device):
##   bash generate-missing-pc-files.sh
##

set -euo pipefail

PREFIX="${PREFIX:-/data/data/app.botdrop/files/usr}"
PC_DIR="$PREFIX/lib/pkgconfig"

created=0
skipped=0

create_pc() {
    local name="$1"
    local version="$2"
    local libs="$3"
    local extra_cflags="${4:-}"

    if [ -f "$PC_DIR/${name}.pc" ]; then
        skipped=$((skipped + 1))
        return
    fi

    cat > "$PC_DIR/${name}.pc" << PCEOF
prefix=${PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: ${name}
Description: ${name}
Version: ${version}
Libs: -L\${libdir} ${libs}
Cflags: -I\${includedir} ${extra_cflags}
PCEOF

    created=$((created + 1))
    echo "  Created: ${name}.pc"
}

echo "Generating missing .pc files in $PC_DIR"
echo ""

mkdir -p "$PC_DIR"

# Core system libraries (from bootstrap)
create_pc "zlib"            "1.3.1"    "-lz"
create_pc "libpng"          "1.6.54"   "-lpng16"
create_pc "libpng16"        "1.6.54"   "-lpng16"
create_pc "libexpat"        "2.6.4"    "-lexpat"
create_pc "expat"           "2.6.4"    "-lexpat"
create_pc "libffi"          "3.4.7"    "-lffi"
create_pc "libpcre2-8"      "10.47"    "-lpcre2-8"
create_pc "libzstd"         "1.5.6"    "-lzstd"
create_pc "liblzma"         "5.6.4"    "-llzma"
create_pc "libdeflate"      "1.23"     "-ldeflate"

# Brotli compression
create_pc "libbrotlicommon" "1.1.0"    "-lbrotlicommon"
create_pc "libbrotlidec"    "1.1.0"    "-lbrotlidec"
create_pc "libbrotlienc"    "1.1.0"    "-lbrotlienc"

# Freetype (uses libtool version in .pc, not project version)
# freetype 2.13.3 → pkg-config version 26.3.20
create_pc "freetype2"       "26.3.20"  "-lfreetype" "-I\${includedir}/freetype2"

# Fontconfig
create_pc "fontconfig"      "2.17.1"   "-lfontconfig"

# XML
create_pc "libxml-2.0"      "2.12.5"   "-lxml2"     "-I\${includedir}/libxml2"
create_pc "libarchive"      "3.8.5"    "-larchive"

# X11 libraries (for pango/cairo)
create_pc "x11"             "1.8.10"   "-lX11"
create_pc "xext"            "1.3.6"    "-lXext"
create_pc "xrender"         "0.9.12"   "-lXrender"
create_pc "x11-xcb"         "1.8.10"   "-lX11-xcb"
create_pc "xau"             "1.0.11"   "-lXau"
create_pc "xcb"             "1.16.1"   "-lxcb"
create_pc "xdmcp"           "1.1.5"    "-lXdmcp"
create_pc "xft"             "2.3.8"    "-lXft"
create_pc "xcb-render"      "1.16.1"   "-lxcb-render"
create_pc "xcb-shm"         "1.16.1"   "-lxcb-shm"
create_pc "xcb-xfixes"      "1.16.1"   "-lxcb-xfixes"
create_pc "xcb-shape"       "1.16.1"   "-lxcb-shape"

echo ""
echo "Done: $created created, $skipped already existed"
