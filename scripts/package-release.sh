#!/usr/bin/env bash
# Build DevBar for Release and package it as a shareable .app.zip.
# Meant for local sanity-checks of the packaging flow — the same steps
# run in .github/workflows/release.yml on tag pushes.
#
# Output: dist/DevBar.app and dist/DevBar-<version>.zip (+ .sha256).

set -euo pipefail

VERSION="${1:-dev}"
BUILD_DIR="build"
DIST_DIR="dist"

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "Building DevBar (Release, unsigned)..."
xcodebuild \
    -scheme DevBar \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build

APP_PATH=$(find "$BUILD_DIR/Build/Products/Release" -maxdepth 2 -name 'DevBar.app' -type d | head -n 1)
if [ -z "$APP_PATH" ]; then
    echo "error: DevBar.app not found after build" >&2
    exit 1
fi

cp -R "$APP_PATH" "$DIST_DIR/DevBar.app"
ZIP_NAME="DevBar-${VERSION}.zip"

echo "Packaging ${ZIP_NAME}..."
(cd "$DIST_DIR" && ditto -c -k --keepParent DevBar.app "$ZIP_NAME")
(cd "$DIST_DIR" && shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256")

echo
echo "Built:"
echo "  $DIST_DIR/DevBar.app"
echo "  $DIST_DIR/$ZIP_NAME"
echo "  $DIST_DIR/$ZIP_NAME.sha256"
