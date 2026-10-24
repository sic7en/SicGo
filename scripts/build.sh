#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
swift build -c release
APP=build/SicGo.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/SicGo" "$APP/Contents/MacOS/SicGo"
xcrun strip -x "$APP/Contents/MacOS/SicGo"
python3 - <<'PY'
import plistlib
from pathlib import Path
info = {
    'CFBundleName': 'SicGo', 'CFBundleDisplayName': 'SicGo',
    'CFBundleIdentifier': 'local.makstton.SicGo', 'CFBundleExecutable': 'SicGo',
    'CFBundleVersion': '11', 'CFBundleShortVersionString': '1.3.2',
    'NSHumanReadableCopyright': '© 2026 Sic7en',
    'CFBundlePackageType': 'APPL', 'CFBundleDevelopmentRegion': 'en',
    'LSMinimumSystemVersion': '14.0', 'NSHighResolutionCapable': True, 'LSUIElement': True,
    'CFBundleIconFile': 'SicGo', 'NSPrincipalClass': 'NSApplication',
    'NSDesktopFolderUsageDescription': 'Open an image you choose to annotate.',
    'NSDocumentsFolderUsageDescription': 'Open an image you choose to annotate.',
    'NSDownloadsFolderUsageDescription': 'Open an image you choose to annotate.',
    'CFBundleDocumentTypes': [{'CFBundleTypeName': 'Image', 'CFBundleTypeRole': 'Viewer',
        'LSHandlerRank': 'Alternate', 'LSItemContentTypes': ['public.image']}]
}
Path('build/SicGo.app/Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
swift scripts/icon.swift "$APP/Contents/Resources/SicGo.icns"
codesign --force --sign - "$APP"
echo "Built $APP"
