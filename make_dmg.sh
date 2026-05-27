#!/bin/bash
set -e

APP_NAME="CopyKeeper"
BUNDLE="${APP_NAME}.app"
VOL_NAME="${APP_NAME}"
STAGING=".dmg_staging"
DMG_NAME="${APP_NAME}.dmg"

# Build the app first if it isn't there.
if [ ! -d "${BUNDLE}" ]; then
    echo "No ${BUNDLE} found — building first..."
    ./build.sh
fi

# Use the bundle's version in the dmg file name, e.g. CopyKeeper-1.0.0.dmg
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${BUNDLE}/Contents/Info.plist" 2>/dev/null || echo "")
if [ -n "${VERSION}" ]; then
    DMG_NAME="${APP_NAME}-${VERSION}.dmg"
fi

echo "Packaging ${BUNDLE} -> ${DMG_NAME}"

# Fresh staging folder containing the app + a shortcut to /Applications,
# so the user can drag-and-drop to install.
rm -rf "${STAGING}" "${DMG_NAME}"
mkdir -p "${STAGING}"
cp -R "${BUNDLE}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

# Strip the quarantine flag from the copy we ship.
xattr -dr com.apple.quarantine "${STAGING}/${BUNDLE}" 2>/dev/null || true

hdiutil create \
    -volname "${VOL_NAME}" \
    -srcfolder "${STAGING}" \
    -ov \
    -format UDZO \
    "${DMG_NAME}"

rm -rf "${STAGING}"

echo ""
echo "Done! ${DMG_NAME} created ($(du -h "${DMG_NAME}" | cut -f1))."
echo ""
echo "Share this file. To install: open it, drag ${BUNDLE} onto Applications."
echo ""
echo "NOTE: The app is unsigned. On first launch your friends must either:"
echo "  - right-click the app in Applications -> Open -> Open, OR"
echo "  - run: xattr -dr com.apple.quarantine /Applications/${BUNDLE}"
