#!/bin/zsh

set -euo pipefail

PROJECT="${PROJECT:-Porter.xcodeproj}"
SCHEME="${SCHEME:-Porter}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-Port Menu}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
ARCHIVE_PATH="${OUTPUT_DIR}/${APP_NAME}.xcarchive"
EXPORT_APP_PATH="${OUTPUT_DIR}/${APP_NAME}.app"
ZIP_PATH="${OUTPUT_DIR}/${APP_NAME}.zip"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"

: "${TEAM_ID:?Set TEAM_ID to your Apple Developer team ID.}"
: "${DEVELOPER_ID_APP:?Set DEVELOPER_ID_APP to your Developer ID Application signing identity.}"

rm -rf "${ARCHIVE_PATH}" "${EXPORT_APP_PATH}" "${ZIP_PATH}"
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

echo "Creating notarization archive..."
/usr/bin/ditto -c -k --keepParent "${EXPORT_APP_PATH}" "${ZIP_PATH}"

echo "Submitting for notarization..."
xcrun notarytool submit "${ZIP_PATH}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "${EXPORT_APP_PATH}"

echo "Release ready:"
echo "  App: ${EXPORT_APP_PATH}"
echo "  Zip: ${ZIP_PATH}"
