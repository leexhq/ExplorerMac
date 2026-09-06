#!/bin/bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="${1:-$SOURCE_DIR/../}"
BUILD_DIR="$SOURCE_DIR/.build"
APP="$DEST_DIR/ExplorerMac.app"
mkdir -p "$BUILD_DIR" "$APP/Contents/MacOS" "$APP/Contents/Resources"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
for ARCH in arm64 x86_64; do
    xcrun swiftc -swift-version 5 -O -whole-module-optimization -target "$ARCH-apple-macos14.0" -sdk "$SDK" -module-cache-path "$BUILD_DIR/ModuleCache" "$SOURCE_DIR"/Sources/*.swift -o "$BUILD_DIR/ExplorerMac-$ARCH" -framework AppKit -framework SwiftUI -framework Quartz -framework QuickLookThumbnailing -framework UniformTypeIdentifiers
done
lipo -create "$BUILD_DIR/ExplorerMac-arm64" "$BUILD_DIR/ExplorerMac-x86_64" -output "$APP/Contents/MacOS/ExplorerMac"
cp "$SOURCE_DIR/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$SOURCE_DIR/AppIcon.icns" ]; then cp "$SOURCE_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"; fi
codesign --force --sign - --identifier local.ExplorerMac "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
