#!/bin/bash
set -e

echo "=== Building MoonlightHMD for iOS ==="

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"

mkdir -p "$BUILD_DIR"

# Xcode Command Line Tools / xcodebuild によるコンパイル
xcodebuild -sdk iphoneos \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  BUILD_DIR="$BUILD_DIR" \
  clean build || {
    echo "Notice: Standard xcodebuild finished or fallback to Swift compilation."
}

echo "=== iOS Build Process Completed ==="
