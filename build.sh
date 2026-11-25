#!/bin/bash
# Builds build/GoTime.app (ad-hoc signed) and runs the self-test.
# Builds with the Command Line Tools by default; set DEVELOPER_DIR to use Xcode instead.
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"

swift build -c release
.build/release/GoTime --selftest

ICONSET=.build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
.build/release/GoTime --export-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o .build/AppIcon.icns

APP=build/GoTime.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/GoTime "$APP/Contents/MacOS/GoTime"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp .build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"
