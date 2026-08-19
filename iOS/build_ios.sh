#!/bin/bash
set -e

echo "=== Building Official Moonlight iOS Xcode Project with ARKit 6DoF & Hand Tracking ==="

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"

mkdir -p "$BUILD_DIR"

# Ensure all submodules and nested source files are initialized in CI runner
cd "$PROJECT_DIR/.."
git submodule update --init --recursive || true
cd "$PROJECT_DIR"

# Xcode build command for Moonlight.xcodeproj
xcodebuild -project "$PROJECT_DIR/Moonlight.xcodeproj" \
  -scheme Moonlight \
  -sdk iphoneos \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  clean build

APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "Moonlight.app" | head -n 1)

if [ -n "$APP_PATH" ]; then
    echo "Found built app at: $APP_PATH"
    cp -R "$APP_PATH" "$BUILD_DIR/Moonlight.app"
    cd "$BUILD_DIR"
    zip -r Moonlight-iOS.zip Moonlight.app
    echo "Successfully packaged Moonlight.app"
else
    echo "Error: Moonlight.app build failed!"
    exit 1
fi
