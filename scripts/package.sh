#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/SicGo.app/Contents/Info.plist)
ARCH=$(uname -m)
if [[ "$ARCH" == arm64 ]]; then ARCH=AppleSilicon; fi
STAGING=$(mktemp -d -t sicgo-package)
trap 'rm -rf "$STAGING"' EXIT
ditto build/SicGo.app "$STAGING/SicGo.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname SicGo -srcfolder "$STAGING" -format UDZO -ov "build/SicGo-${VERSION}-${ARCH}.dmg"
shasum -a 256 "build/SicGo-${VERSION}-${ARCH}.dmg"
