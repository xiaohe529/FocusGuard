#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_DIR=".build/FocusGuard.app"
APP_NAME="FocusGuard"

# ---- ensure .app exists ----
if [ ! -d "$APP_DIR" ]; then
    echo "=== .app not found, building first ==="
    ./build-app.sh release
fi

VERSION="${1:-1.0.0}"
ZIP_FILE="${APP_NAME}-v${VERSION}.zip"

# ---- make zip ----
rm -f "$ZIP_FILE"

cp -R "$APP_DIR" "${APP_NAME}.app"
zip -r -q "$ZIP_FILE" "${APP_NAME}.app"
rm -rf "${APP_NAME}.app"

echo "=== Done: $ZIP_FILE ==="
echo "Upload to GitHub/Gitee Releases."
