#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_DIR=".build/FocusGuard_build.app"
APP_NAME="FocusGuard"

# ---- ensure .app exists ----
if [ ! -d "$APP_DIR" ]; then
    echo "=== .app not found, building first ==="
    ./build-app.sh release
fi

VERSION="${1:-1.0.0}"
PKG_FILE="${APP_NAME}-v${VERSION}.pkg"

echo "=== Creating pkg installer: ${PKG_FILE} ==="

rm -f "$PKG_FILE"

pkgbuild \
    --component "$APP_DIR" \
    --install-location /Applications \
    --identifier com.focusguard.app \
    --version "$VERSION" \
    "$PKG_FILE"

echo "=== Done: $PKG_FILE ==="
echo "Upload to GitHub/Gitee Releases."
echo ""
echo "Users double-click the .pkg and follow the installer wizard."
echo "If warned: right-click → Open, or System Settings → Privacy & Security → Open Anyway."
