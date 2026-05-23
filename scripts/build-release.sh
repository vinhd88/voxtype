#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="VoxType"
SCHEME="VoxType"
BUILD_DIR="$PROJECT_ROOT/build"
DMG_NAME="VoxType"
VERSION="1.0.0"

echo "==> Building $APP_NAME v$VERSION..."

# Generate Xcode project from project.yml (idempotent)
cd "$PROJECT_ROOT"
xcodegen generate

# Build release
xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/derivedData" \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    clean build \
    | tail -5

APP_PATH="$BUILD_DIR/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: $APP_PATH not found. Build may have failed."
    exit 1
fi

echo "==> App built: $APP_PATH"

# Create DMG
DMG_PATH="$PROJECT_ROOT/$DMG_NAME.dmg"
rm -f "$DMG_PATH"

# Use temporary folder for DMG staging
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING"

echo "==> DMG created: $DMG_PATH"
echo "==> Size: $(du -h "$DMG_PATH" | cut -f1)"
echo "==> Done! Share $DMG_PATH to distribute VoxType."
