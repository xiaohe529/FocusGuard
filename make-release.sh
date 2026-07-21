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

# pkgbuild uses the directory name as the install name, so copy to a
# temp dir with the correct name before packaging.
# COPYFILE_DISABLE prevents macOS from creating ._ (Apple Double) files.
# xattr -cr strips extended attributes that also trigger ._ creation.
rm -rf "${APP_NAME}.app"
COPYFILE_DISABLE=1 cp -R "$APP_DIR" "${APP_NAME}.app"
xattr -cr "${APP_NAME}.app" 2>/dev/null || true
find "${APP_NAME}.app" -name "._*" -delete 2>/dev/null || true
pkgbuild \
    --component "${APP_NAME}.app" \
    --install-location /Applications \
    --identifier com.focusguard.app \
    --version "$VERSION" \
    --ownership recommended \
    "$PKG_FILE"
rm -rf "${APP_NAME}.app"

echo "=== Done: $PKG_FILE ==="
echo "Upload to GitHub/Gitee Releases."
echo ""
echo "Users double-click the .pkg and follow the installer wizard."
echo "If warned: right-click → Open, or System Settings → Privacy & Security → Open Anyway."