#!/bin/bash
# Builds dist/Brink.app (release, ad-hoc signed so it runs locally).
#
# Optional environment:
#   OUT_DIR=dist         where to put the app (default dist/)
#   VERSION=1.0.2        marketing version
#   BUILD_NUMBER=1       build number
#   BUNDLE_ID=...        bundle identifier (default io.github.jotharsh.Brink - set your own)
#   ARCHS="arm64"        architectures (default: arm64 x86_64, a universal binary)
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Brink"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_ID="${BUNDLE_ID:-io.github.jotharsh.Brink}"
ARCHS="${ARCHS:-arm64 x86_64}"

OUT_DIR="${OUT_DIR:-dist}"
APP="$OUT_DIR/$APP_NAME.app"
ARCH_FLAGS=()
for arch in $ARCHS; do ARCH_FLAGS+=(--arch "$arch"); done

echo "==> swift build -c release (${ARCHS})"
swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
    echo "    (no Resources/AppIcon.icns - run: swift scripts/make_icon.swift)"
fi

PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
plutil -lint "$PLIST" >/dev/null

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

echo "Built $APP"
