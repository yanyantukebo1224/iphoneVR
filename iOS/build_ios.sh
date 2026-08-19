#!/bin/bash
set -e

echo "=== Building MoonlightHMD Xcode Project ==="

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"

mkdir -p "$BUILD_DIR"

# Xcode build command
xcodebuild -project "$PROJECT_DIR/MoonlightHMD.xcodeproj" \
  -scheme MoonlightHMD \
  -sdk iphoneos \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  clean build

# .app 成果物のコピーとZIP圧縮 (Artifact用)
APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "MoonlightHMD.app" | head -n 1)

if [ -n "$APP_PATH" ]; then
    echo "Found built app at: $APP_PATH"
    cp -R "$APP_PATH" "$BUILD_DIR/MoonlightHMD.app"
    cd "$BUILD_DIR"
    zip -r MoonlightHMD-iOS.zip MoonlightHMD.app
    echo "Successfully packaged MoonlightHMD.app"
else
    echo "Error: MoonlightHMD.app build failed!"
    exit 1
fi
