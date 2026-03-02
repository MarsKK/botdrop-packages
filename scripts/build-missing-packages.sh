#!/bin/bash
##
## Build only the 32 NEW dependency packages that are missing from the BotDrop repo.
## These are the packages that were previously pulled from Termux official source
## but fail on BotDrop due to com.termux path hardcoding.
##
## Usage:
##   ./scripts/build-missing-packages.sh [arch] [output-dir]
##

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Only the 32 NEW packages, in dependency order
MISSING_PACKAGES=(
    # Tier 0: No dependencies
    "giflib"
    "libandroid-execinfo"
    "libandroid-shmem"
    "liblzo"
    "libpixman"
    "libaom"
    "libdav1d"
    "libnspr"
    "librav1e"

    # Tier 1: Simple dependencies
    "jbig2dec"
    "libidn"
    "libgraphite"
    "libde265"
    "libx265"
    "libjasper"

    # Tier 2: Mid dependencies
    "libtool"
    "libzip"
    "fribidi"
    "liblqr"
    "libgts"
    "djvulibre"
    "gdk-pixbuf"

    # Tier 3: Graphics
    "harfbuzz"
    "libnss"

    # Tier 4: Text/processing
    "ghostscript"
    "libraqm"
    "libraw"

    # Tier 5: High-level
    "libgd"
    "graphviz"

    # Tier 6: GPG
    "gpgme"
    "gpgmepp"

    # Tier 7: Extra
    "leptonica"
)

ARCH="${1:-aarch64}"
OUTPUT_DIR="${2:-./debs-output}"

echo "========================================"
echo "  BotDrop Missing Packages Builder"
echo "========================================"
echo ""
echo "Architecture:    $ARCH"
echo "Output directory: $OUTPUT_DIR"
echo "Package count:    ${#MISSING_PACKAGES[@]}"
echo ""
echo "========================================"

mkdir -p "$OUTPUT_DIR"

declare -a BUILT_PACKAGES=()
declare -a FAILED_PACKAGES=()
declare -a SKIPPED_PACKAGES=()

for pkg in "${MISSING_PACKAGES[@]}"; do
    echo ""
    echo "[$(date '+%H:%M:%S')] Building: $pkg"
    echo "----------------------------------------"

    cd "$REPO_ROOT"

    LOG_FILE="$OUTPUT_DIR/.build-${pkg}.log"
    if ./build-package.sh -a "$ARCH" "$pkg" 2>&1 | tee "$LOG_FILE"; then
        echo "  ✅ Build succeeded: $pkg"

        deb_count=0
        for deb_dir in output debs; do
            if [ -d "$deb_dir" ]; then
                while IFS= read -r -d '' deb_file; do
                    cp "$deb_file" "$OUTPUT_DIR/"
                    echo "     Copied: $(basename "$deb_file")"
                    deb_count=$((deb_count + 1))
                done < <(find "$deb_dir" -name "${pkg}_*.deb" -print0 2>/dev/null)

                # Collect subpackage .debs
                if [ -d "packages/${pkg}" ]; then
                    for subpkg in packages/${pkg}/*.subpackage.sh; do
                        [ -f "$subpkg" ] || continue
                        subpkg_name=$(basename "$subpkg" .subpackage.sh)
                        while IFS= read -r -d '' deb_file; do
                            cp "$deb_file" "$OUTPUT_DIR/"
                            echo "     Copied subpackage: $(basename "$deb_file")"
                            deb_count=$((deb_count + 1))
                        done < <(find "$deb_dir" -name "${subpkg_name}_*.deb" -print0 2>/dev/null)
                    done
                fi
            fi
        done

        if [ $deb_count -gt 0 ]; then
            BUILT_PACKAGES+=("$pkg")
        else
            echo "  ⚠️  No .deb found for $pkg"
            SKIPPED_PACKAGES+=("$pkg")
        fi
    else
        if grep -q "No build.sh script at package dir" "$LOG_FILE" 2>/dev/null; then
            echo "  ⚠️  Skipped: $pkg (no build.sh)"
            SKIPPED_PACKAGES+=("$pkg")
        else
            echo "  ❌ Build failed: $pkg"
            FAILED_PACKAGES+=("$pkg")
            tail -20 "$LOG_FILE" | sed 's/^/    /'
        fi
    fi
done

echo ""
echo "========================================"
echo "  Build Summary"
echo "========================================"
echo ""
echo "✅ Successfully built:  ${#BUILT_PACKAGES[@]} packages"
[ ${#BUILT_PACKAGES[@]} -gt 0 ] && printf '   - %s\n' "${BUILT_PACKAGES[@]}"
echo ""
[ ${#SKIPPED_PACKAGES[@]} -gt 0 ] && echo "⚠️  Skipped: ${#SKIPPED_PACKAGES[@]} packages" && printf '   - %s\n' "${SKIPPED_PACKAGES[@]}" && echo ""
[ ${#FAILED_PACKAGES[@]} -gt 0 ] && echo "❌ Failed: ${#FAILED_PACKAGES[@]} packages" && printf '   - %s\n' "${FAILED_PACKAGES[@]}" && echo ""

echo "📦 Total .deb files:    $(ls -1 "$OUTPUT_DIR"/*.deb 2>/dev/null | wc -l | tr -d ' ')"
echo "💾 Output directory:    $OUTPUT_DIR"
echo "========================================"

[ ${#FAILED_PACKAGES[@]} -gt 0 ] && exit 1
echo "✅ All packages built successfully!"
