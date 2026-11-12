#!/bin/bash
# Builds "build/Weather Wallpaper Installer.pkg", which installs the app into /Applications.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
IDENTIFIER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir "$WORK/root"
cp -R "build/Weather Wallpaper.app" "$WORK/root/"

# Without this the installer "relocates": it updates any existing copy of the app it
# finds on disk (such as ./build) instead of installing into /Applications.
pkgbuild --analyze --root "$WORK/root" "$WORK/component.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Delete :0:BundleIsRelocatable" "$WORK/component.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$WORK/component.plist"
# Always overwrite, so re-running the installer for the same version picks up a rebuild.
/usr/libexec/PlistBuddy -c "Set :0:BundleIsVersionChecked false" "$WORK/component.plist"

pkgbuild --root "$WORK/root" \
    --component-plist "$WORK/component.plist" \
    --scripts installer/scripts \
    --identifier "$IDENTIFIER" \
    --version "$VERSION" \
    --install-location /Applications \
    "$WORK/component.pkg" >/dev/null

PKG="build/Weather Wallpaper Installer.pkg"
productbuild --package "$WORK/component.pkg" "$PKG" >/dev/null

echo "Built $PKG"
