#!/bin/bash
# Builds "Weather Wallpaper.app" into ./build
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Weather Wallpaper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/WeatherWallpaper" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
if [ -d Resources/Textures ]; then
    mkdir -p "$APP/Contents/Resources"
    cp -R Resources/Textures "$APP/Contents/Resources/"
fi
codesign --force --sign - "$APP"

echo "Built $APP"
