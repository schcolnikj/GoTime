#!/bin/bash
# Builds build/GoTime.app (ad-hoc signed) and runs the self-test.
# Uses the Command Line Tools so it works without accepting the Xcode license.
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"

swift build -c release
.build/release/GoTime --selftest

APP=build/GoTime.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/GoTime "$APP/Contents/MacOS/GoTime"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
