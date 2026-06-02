#!/bin/sh
# Build a Termux-compatible .deb package for firewallctl.
#
# Usage:
#   ./scripts/make-deb.sh [VERSION]
#
# Requirements (build host):
#   - dpkg-deb  (apt install dpkg-dev)
#   - make / javac  (to build the dex jar if not already built)
#
# The produced .deb installs:
#   $PREFIX/bin/firewallctl            – wrapper script
#   $PREFIX/lib/firewallctl/firewallctl.dex.jar
# where $PREFIX = /data/data/com.termux/files/usr
#
# Termux's dpkg extracts relative to /, so paths inside the archive's data.tar
# must be the FULL absolute path (e.g. ./data/data/com.termux/files/usr/bin/…).
# Using ./usr/… would try to write into the read-only system /usr.
#
# Install on device:
#   adb push build/firewallctl_*.deb /data/local/tmp/
#   adb shell su -c 'dpkg -i /data/local/tmp/firewallctl_*.deb'
# Then run:
#   su -c 'firewallctl list-policies'

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DEX_JAR="$BUILD_DIR/firewallctl.dex.jar"

VERSION="${1:-${VERSION:-1.0.0}}"
PKG_NAME="firewallctl"
ARCH="all"
# Termux prefix (hardcoded in the Termux dpkg rootdir chain).
TERMUX_PREFIX="/data/data/com.termux/files/usr"

DEB_STAGING="$BUILD_DIR/deb-staging"
PKG_STAGE="$DEB_STAGING/${PKG_NAME}_${VERSION}_${ARCH}"
DEB_OUT="$BUILD_DIR/${PKG_NAME}_${VERSION}_${ARCH}.deb"

# Path inside the staging dir that mirrors the on-device prefix.
# Termux dpkg extracts to /, so files must live at their absolute target path.
STAGE_PREFIX="$PKG_STAGE$TERMUX_PREFIX"

# ---------------------------------------------------------------------------
# 0. Prerequisites
# ---------------------------------------------------------------------------
if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "error: dpkg-deb not found — install it with: sudo apt install dpkg-dev" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 1. Build dex jar if needed
# ---------------------------------------------------------------------------
if [ ! -f "$DEX_JAR" ]; then
    echo ">>> dex jar not found, running make …"
    make -C "$PROJECT_DIR"
fi

# ---------------------------------------------------------------------------
# 2. Stage files
# ---------------------------------------------------------------------------
rm -rf "$PKG_STAGE"
mkdir -p "$PKG_STAGE/DEBIAN"
mkdir -p "$STAGE_PREFIX/bin"
mkdir -p "$STAGE_PREFIX/lib/$PKG_NAME"

# Dex jar
cp "$DEX_JAR" "$STAGE_PREFIX/lib/$PKG_NAME/firewallctl.dex.jar"

# Wrapper script — references the installed jar at the Termux prefix path.
WRAPPER="$STAGE_PREFIX/bin/firewallctl"
cat > "$WRAPPER" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
# firewallctl – per-app Android firewall CLI via NetworkPolicyManager.
# Must be run as root (su -c firewallctl ...).
export CLASSPATH="${TERMUX_PREFIX}/lib/${PKG_NAME}/firewallctl.dex.jar"
exec app_process /system/bin --nice-name=firewallctl app.firewallctl.Main "\$@"
EOF
chmod 0755 "$WRAPPER"

# ---------------------------------------------------------------------------
# 3. DEBIAN/control
# ---------------------------------------------------------------------------
INSTALLED_KB="$(du -sk "$STAGE_PREFIX" | cut -f1)"

cat > "$PKG_STAGE/DEBIAN/control" <<EOF
Package: $PKG_NAME
Version: $VERSION
Architecture: $ARCH
Maintainer: firewallctl
Installed-Size: $INSTALLED_KB
Description: Per-app Android firewall CLI via NetworkPolicyManager
 Controls per-UID network-policy flags (allow/block Wi-Fi, mobile data,
 background traffic, VPN) by calling INetworkPolicyManager.setUidPolicy()
 via app_process as root. Changes are reflected immediately in the
 LineageOS / AOSP Settings UI (Apps > App > Mobile data usage).
 .
 Requires root. Tested on LineageOS 20+.
EOF

# ---------------------------------------------------------------------------
# 4. Build .deb
# ---------------------------------------------------------------------------
dpkg-deb --root-owner-group --build "$PKG_STAGE" "$DEB_OUT"

echo ""
echo "Built: $DEB_OUT"
echo ""
echo "Deploy:"
echo "  adb push $DEB_OUT /data/local/tmp/"
echo "  adb shell su -c 'dpkg -i /data/local/tmp/${PKG_NAME}_${VERSION}_${ARCH}.deb'"
echo ""
echo "Then on the device:"
echo "  su -c 'firewallctl list-policies'"
echo "  su -c 'firewallctl get com.android.chrome'"
echo "  su -c 'firewallctl set com.android.chrome +REJECT_ALL'"
