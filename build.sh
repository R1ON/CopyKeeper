#!/bin/bash
set -e

APP_NAME="CopyKeeper"
BUNDLE="${APP_NAME}.app"

SDK_PATH=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)
ARCH=$(uname -m)
TARGET="${ARCH}-apple-macosx13.0"

SOURCES=(
    "Sources/CopyKeeper/Models/ClipboardItem.swift"
    "Sources/CopyKeeper/Models/ClipboardGroup.swift"
    "Sources/CopyKeeper/Extensions/Extensions.swift"
    "Sources/CopyKeeper/Managers/PersistenceManager.swift"
    "Sources/CopyKeeper/ClipboardStore.swift"
    "Sources/CopyKeeper/Managers/ClipboardMonitor.swift"
    "Sources/CopyKeeper/AppDelegate.swift"
    "Sources/CopyKeeper/Panel/ClipboardPanel.swift"
    "Sources/CopyKeeper/Views/ClipboardPanelView.swift"
    "Sources/CopyKeeper/Views/ClipboardCardView.swift"
    "Sources/CopyKeeper/Views/GroupBarView.swift"
    "Sources/CopyKeeper/Views/NewGroupSheet.swift"
    "Sources/CopyKeeper/Views/HotkeySettings.swift"
    "Sources/CopyKeeper/Views/StatisticsView.swift"
    "Sources/CopyKeeper/Views/CardContextMenu.swift"
    "Sources/CopyKeeper/Views/Settings.swift"
    "Sources/CopyKeeper/CopyKeeperApp.swift"
)

echo "Building ${APP_NAME}..."
echo "Swift: $(swiftc --version 2>&1 | head -1)"
echo "SDK:   ${SDK_PATH}"
echo "Target: ${TARGET}"
echo ""

mkdir -p .build
mkdir -p .build/ModuleCache

swiftc \
    -target "${TARGET}" \
    -sdk "${SDK_PATH}" \
    -module-cache-path ".build/ModuleCache" \
    -O \
    -o ".build/${APP_NAME}" \
    "${SOURCES[@]}"

echo ""
echo "Creating app bundle..."
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"

cp ".build/${APP_NAME}" "${BUNDLE}/Contents/MacOS/"
cp "Sources/CopyKeeper/Resources/Info.plist" "${BUNDLE}/Contents/"
cp "AppIcon.icns" "${BUNDLE}/Contents/Resources/"
# Optional custom menu-bar icon
cp "trayIcon.png" "${BUNDLE}/Contents/Resources/" 2>/dev/null || true

# Remove quarantine attribute for local unsigned builds
xattr -dr com.apple.quarantine "${BUNDLE}" 2>/dev/null || true

echo "Done! ${BUNDLE} created."
echo ""
echo "To run: open ${BUNDLE}"
echo "To install: cp -r ${BUNDLE} /Applications/"
echo ""
echo "NOTE: On first launch, grant Accessibility access in:"
echo "   System Settings -> Privacy & Security -> Accessibility"
echo ""
echo "NOTE: If you see SDK version mismatch errors, install Xcode"
echo "   from the App Store to get the matching toolchain."
