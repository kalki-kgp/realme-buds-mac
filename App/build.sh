#!/bin/sh
# Builds Buds.app with the Command Line Tools alone (no Xcode needed).
set -e
cd "$(dirname "$0")"
APP="Buds.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macosx26.0 \
    -framework IOBluetooth -framework SwiftUI -framework AppKit \
    Sources/*.swift -o "$APP/Contents/MacOS/Buds"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier dev.kalki.buds "$APP"
echo "built $PWD/$APP"
