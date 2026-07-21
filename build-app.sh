#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-debug}"
if [ "$CONFIG" = "release" ]; then
    BUILD_CONFIG="release"
    SWIFT_FLAGS="-c release"
else
    BUILD_CONFIG="debug"
    SWIFT_FLAGS=""
fi

echo "=== Building FocusGuard + Helper ($BUILD_CONFIG) ==="
swift build $SWIFT_FLAGS

BUNDLE_DIR=".build/FocusGuard_build.app"
BIN_SRC=".build/arm64-apple-macosx/$BUILD_CONFIG/FocusGuard"
HELPER_SRC=".build/arm64-apple-macosx/$BUILD_CONFIG/FocusGuardHelper"

echo "=== Assembling .app bundle ==="
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"
mkdir -p "$BUNDLE_DIR/Contents/Helpers"

cp "$BIN_SRC"    "$BUNDLE_DIR/Contents/MacOS/FocusGuard"
cp "$HELPER_SRC" "$BUNDLE_DIR/Contents/Helpers/com.focusguard.helper"
cp BundleResources/Info.plist                     "$BUNDLE_DIR/Contents/Info.plist"
cp BundleResources/PkgInfo                         "$BUNDLE_DIR/Contents/PkgInfo"
cp BundleResources/AppIcon.icns                    "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"
cp BundleResources/com.focusguard.helper.plist     "$BUNDLE_DIR/Contents/Resources/com.focusguard.helper.plist"

chmod +x "$BUNDLE_DIR/Contents/MacOS/FocusGuard"
chmod +x "$BUNDLE_DIR/Contents/Helpers/com.focusguard.helper"

# Ad-hoc sign both binaries
codesign --force --sign - "$BUNDLE_DIR/Contents/MacOS/FocusGuard" 2>/dev/null || true
codesign --force --sign - "$BUNDLE_DIR/Contents/Helpers/com.focusguard.helper" 2>/dev/null || true

# Also copy helper + plist next to the executable for dev-mode (command-line) runs
BUILD_OUT_DIR=".build/arm64-apple-macosx/$BUILD_CONFIG"
cp BundleResources/com.focusguard.helper.plist "$BUILD_OUT_DIR/com.focusguard.helper.plist"

echo "=== Bundle created: $BUNDLE_DIR ==="
echo "Run with: open $BUNDLE_DIR"
