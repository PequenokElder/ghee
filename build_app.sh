#!/bin/bash
# Builds "Guitar Monitor.app" next to this script.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="Ghee.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/GuitarMonitor "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --options runtime --entitlements Resources/GuitarMonitor.entitlements --sign - "$APP"
echo "Built: $(pwd)/$APP"
