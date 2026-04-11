#!/bin/zsh

set -euo pipefail

PROJECT="${PROJECT:-Porter.xcodeproj}"
SCHEME="${SCHEME:-Porter}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-Port Menu}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
ARCHIVE_PATH="${OUTPUT_DIR}/${APP_NAME}.xcarchive"
EXPORT_APP_PATH="${OUTPUT_DIR}/${APP_NAME}.app"
STAGING_DIR="${OUTPUT_DIR}/dmg-staging"
STAGING_BACKGROUND_DIR="${STAGING_DIR}/.background"
ZIP_PATH="${OUTPUT_DIR}/${APP_NAME}.zip"
TEMP_DMG_PATH="${OUTPUT_DIR}/${APP_NAME}-temp.dmg"
DMG_PATH="${OUTPUT_DIR}/${APP_NAME}.dmg"
MOUNT_DIR="/Volumes/PortMenuBuild"
BACKGROUND_SOURCE_PATH="${BACKGROUND_SOURCE_PATH:-packaging/dmg-background.tiff}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"
NOTARY_APPLE_ID="${NOTARY_APPLE_ID:-}"
NOTARY_PASSWORD="${NOTARY_PASSWORD:-}"

: "${TEAM_ID:?Set TEAM_ID to your Apple Developer team ID.}"
: "${DEVELOPER_ID_APP:?Set DEVELOPER_ID_APP to your Developer ID Application signing identity.}"

cleanup_dmg_mount() {
  if mount | awk -v target="${MOUNT_DIR}" '$3 == target { found = 1 } END { exit found ? 0 : 1 }'; then
    hdiutil detach "${MOUNT_DIR}" >/dev/null 2>&1 || true
  fi
}

cleanup_dmg_mount
rm -rf "${ARCHIVE_PATH}" "${EXPORT_APP_PATH}" "${STAGING_DIR}" "${ZIP_PATH}" "${TEMP_DMG_PATH}" "${DMG_PATH}" "${MOUNT_DIR}"
mkdir -p "${OUTPUT_DIR}"

echo "Archiving ${APP_NAME}..."
xcodebuild archive \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -archivePath "${ARCHIVE_PATH}" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  CODE_SIGN_IDENTITY="${DEVELOPER_ID_APP}"

cp -R "${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app" "${EXPORT_APP_PATH}"

echo "Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "${EXPORT_APP_PATH}"

echo "Re-signing Sparkle internals with Developer ID..."
find "${EXPORT_APP_PATH}/Contents/Frameworks/Sparkle.framework" \
  \( -name "*.xpc" -o -name "*.app" -o -name "Autoupdate" -o -name "Updater" \) \
  | while read -r component; do
    codesign --force --sign "${DEVELOPER_ID_APP}" \
      --options runtime \
      --timestamp \
      "${component}" 2>/dev/null || true
  done
codesign --force --sign "${DEVELOPER_ID_APP}" \
  --options runtime \
  --timestamp \
  --deep \
  "${EXPORT_APP_PATH}/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "${DEVELOPER_ID_APP}" \
  --options runtime \
  --timestamp \
  --entitlements "${EXPORT_APP_PATH}/Contents/MacOS/Port Menu.xcent" \
  "${EXPORT_APP_PATH}" 2>/dev/null || \
codesign --force --sign "${DEVELOPER_ID_APP}" \
  --options runtime \
  --timestamp \
  "${EXPORT_APP_PATH}"

echo "Creating notarization archive..."
/usr/bin/ditto -c -k --keepParent "${EXPORT_APP_PATH}" "${ZIP_PATH}"

submit_for_notarization() {
  local artifact_path="$1"
  if [[ -n "${NOTARY_APPLE_ID}" && -n "${NOTARY_PASSWORD}" ]]; then
    xcrun notarytool submit "${artifact_path}" \
      --apple-id "${NOTARY_APPLE_ID}" \
      --team-id "${TEAM_ID}" \
      --password "${NOTARY_PASSWORD}" \
      --wait
  else
    xcrun notarytool submit "${artifact_path}" \
      --keychain-profile "${NOTARY_PROFILE}" \
      --wait
  fi
}

echo "Submitting app for notarization..."
submit_for_notarization "${ZIP_PATH}"

echo "Stapling app notarization ticket..."
xcrun stapler staple "${EXPORT_APP_PATH}"

echo "Preparing DMG staging folder..."
mkdir -p "${STAGING_BACKGROUND_DIR}"
cp -R "${EXPORT_APP_PATH}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "Creating temporary DMG..."
# Use a volname without spaces to avoid /Volumes mount conflicts
hdiutil create \
  -volname "PortMenuBuild" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDRW \
  "${TEMP_DMG_PATH}"

echo "Attaching temporary DMG..."
hdiutil attach "${TEMP_DMG_PATH}" -noverify -noautoopen
sleep 2

# Copy TIFF background into mounted volume for retina sharpness
mkdir -p "${MOUNT_DIR}/.background"
cp "${BACKGROUND_SOURCE_PATH}" "${MOUNT_DIR}/.background/background.tiff"
BG_TIFF_PATH="${MOUNT_DIR}/.background/background.tiff"

echo "Configuring Finder layout..."
osascript - "${MOUNT_DIR}" "${APP_NAME}" "${BG_TIFF_PATH}" <<'ASCRIPT'
on run argv
  set mountPath to item 1 of argv
  set appName to item 2 of argv
  set bgPath to item 3 of argv
  set dmgFolder to POSIX file mountPath as alias
  set bgFile to POSIX file bgPath
  tell application "Finder"
    tell folder dmgFolder
      open
      delay 1
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      try
        set sidebar width of container window to 0
      end try
      set bounds of container window to {200, 120, 740, 480}
      set opts to the icon view options of container window
      set arrangement of opts to not arranged
      set icon size of opts to 80
      set text size of opts to 12
      set background picture of opts to bgFile
      delay 2
      set position of item (appName & ".app") of container window to {130, 170}
      set position of item "Applications" of container window to {410, 170}
      set background picture of opts to bgFile
      delay 1
      update without registering applications
      delay 1
      close
    end tell
  end tell
end run
ASCRIPT

echo "Detaching temporary DMG..."
hdiutil detach "${MOUNT_DIR}" || hdiutil detach "/Volumes/PortMenuBuild" || true

echo "Creating final DMG..."
hdiutil convert "${TEMP_DMG_PATH}" \
  -format UDZO \
  -o "${DMG_PATH}"
rm -f "${TEMP_DMG_PATH}"

echo "Signing DMG..."
codesign --force --sign "${DEVELOPER_ID_APP}" "${DMG_PATH}"

echo "Submitting DMG for notarization..."
submit_for_notarization "${DMG_PATH}"

echo "Stapling DMG notarization ticket..."
xcrun stapler staple "${DMG_PATH}"

echo "Signing DMG with Sparkle key and updating appcast.xml..."
SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData -name 'sign_update' 2>/dev/null | grep -v old_dsa | head -1 | xargs dirname)"
VERSION=$(defaults read "${EXPORT_APP_PATH}/Contents/Info" CFBundleShortVersionString)
BUILD=$(defaults read "${EXPORT_APP_PATH}/Contents/Info" CFBundleVersion)
DMG_SIZE=$(stat -f%z "${DMG_PATH}")
DMG_FILENAME="PortMenu-${VERSION}.dmg"
DMG_RELEASE_URL="https://github.com/wieandteduard/port-menu/releases/download/v${VERSION}/${DMG_FILENAME}"
SPARKLE_PRIV_KEY=$(security find-generic-password -s "https://sparkle-project.org" -a "ed25519" -w 2>/dev/null)
ED_SIGNATURE=$("${SPARKLE_BIN}/sign_update" --ed-key-file <(echo "${SPARKLE_PRIV_KEY}") "${DMG_PATH}" 2>/dev/null | sed 's/.*edSignature="\([^"]*\)".*/\1/')
PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")

cat > packaging/appcast.xml <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Port Menu</title>
        <link>https://raw.githubusercontent.com/wieandteduard/port-menu/main/packaging/appcast.xml</link>
        <description>Port Menu release feed</description>
        <language>en</language>
        <item>
            <title>Port Menu ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="${DMG_RELEASE_URL}"
                sparkle:edSignature="${ED_SIGNATURE}"
                length="${DMG_SIZE}"
                type="application/octet-stream"/>
        </item>
    </channel>
</rss>
APPCAST

echo "Release ready:"
echo "  App:     ${EXPORT_APP_PATH}"
echo "  DMG:     ${DMG_PATH}"
echo "  Version: ${VERSION} (build ${BUILD})"
echo "  appcast.xml updated in packaging/"
