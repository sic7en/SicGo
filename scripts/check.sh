#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
CHECK_DIR="$(mktemp -d -t sicgo-check)"
trap 'rm -rf "$CHECK_DIR"' EXIT
xcrun swiftc -parse-as-library Sources/SicGo/Drawing.swift Sources/SicGo/ToolbarLayout.swift Sources/SicGo/AnnotationClipboard.swift Sources/SicGo/EditorDocument.swift Sources/SicGo/EditorPreferences.swift Sources/SicGo/Localization.swift Sources/SicGo/UpdateChecker.swift Sources/SicGo/SettingsWindow.swift Sources/SicGo/HomeWindow.swift Sources/SicGo/EditorCanvas.swift Sources/SicGo/EditorWindow.swift Sources/SicGo/Capture.swift Tests/Checks.swift Tests/UpdateChecks.swift -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks"
