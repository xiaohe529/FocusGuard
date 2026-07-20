#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_DIR=".build/FocusGuard.app"
DMG_NAME="FocusGuard"
VOL_NAME="FocusGuard"

# ---- ensure .app exists ----
if [ ! -d "$APP_DIR" ]; then
    echo "=== .app not found, building first ==="
    ./build-app.sh release
fi

# ---- build version ----
VERSION="${1:-1.0.0}"
DMG_FILE="${DMG_NAME}-v${VERSION}.dmg"

echo "=== Creating DMG: ${DMG_FILE} ==="

# ---- clean ----
rm -rf "${VOL_NAME}"
rm -f "${DMG_FILE}"

# ---- create temp volume ----
mkdir -p "${VOL_NAME}"
cp -R "${APP_DIR}" "${VOL_NAME}/FocusGuard.app"
ln -s /Applications "${VOL_NAME}/Applications"

# ---- make disk image ----
hdiutil create -volname "${VOL_NAME}" \
    -srcfolder "${VOL_NAME}" \
    -ov -format UDZO \
    "${DMG_FILE}" \
    -imagekey zlib-level=9

# ---- clean ----
rm -rf "${VOL_NAME}"

echo "=== Done: ${DMG_FILE} ==="
echo "Upload to GitHub/Gitee Releases, then share the download link."
