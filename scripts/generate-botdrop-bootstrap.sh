#!/usr/bin/env bash
##
##  Generate BotDrop bootstrap archives using pre-built packages from
##  the Termux apt repository. Much faster than build-botdrop-bootstrap.sh
##  which compiles everything from source (~3h vs ~5min).
##
##  Usage:
##    ./scripts/generate-botdrop-bootstrap.sh [--architectures aarch64]
##

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# BotDrop additional packages to include in the bootstrap.
BOTDROP_PACKAGES=(
    "nodejs-lts"      # Node.js LTS runtime
    "npm"             # npm package manager
    "git"             # Git version control
    "openssh"         # SSH client and server
    "openssl"         # OpenSSL tools
    "termux-api"      # Termux:API interface
    "proot"           # proot for /tmp support via termux-chroot
    "expect"          # expect for automated password setup
    "android-tools"   # adb/fastboot for wireless ADB fallback
)

BOTDROP_APT_LINE='deb [trusted=yes] https://zhixianio.github.io/botdrop-packages/ stable main'

# Convert array to comma-separated list
BOTDROP_PACKAGES_CSV=$(IFS=,; echo "${BOTDROP_PACKAGES[*]}")

echo "========================================"
echo "  BotDrop Bootstrap Generator (fast mode)"
echo "========================================"
echo ""
echo "Additional packages to include:"
for pkg in "${BOTDROP_PACKAGES[@]}"; do
    echo "  - ${pkg}"
done
echo ""
echo "Using pre-built packages from Termux apt repo"
echo "========================================"

# Run generate-bootstraps.sh with BotDrop packages.
"${SCRIPT_DIR}/generate-bootstraps.sh" \
    --add "${BOTDROP_PACKAGES_CSV}" \
    "$@"

# Inject BotDrop APT source into generated bootstrap archives.
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/botdrop-bootstrap.XXXXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/etc/apt/sources.list.d"
printf '%s\n' "$BOTDROP_APT_LINE" > "$tmpdir/etc/apt/sources.list.d/botdrop.list"

shopt -s nullglob
for zip_path in bootstrap-*.zip; do
    echo "[*] Injecting botdrop source into $zip_path"
    (
        cd "$tmpdir"
        zip -q "$OLDPWD/$zip_path" "etc/apt/sources.list.d/botdrop.list"
    )
done
shopt -u nullglob

echo "✅ Injected botdrop.list into bootstrap archives"