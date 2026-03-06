#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Build, sign, notarize, and package SEER for direct macOS distribution.

Usage:
  scripts/package_macos_direct.sh

Environment variables:
  PROJECT_PATH        Path to .xcodeproj
                      Default: <repo>/OllamaCloud.xcodeproj
  SCHEME              Xcode scheme
                      Default: OllamaCloudMac
  CONFIGURATION       Build configuration
                      Default: Release
  DERIVED_DATA_PATH   DerivedData path
                      Default: /tmp/OllamaCloudMac-Direct
  OUTPUT_DIR          Output folder
                      Default: <repo>/dist/macos
  APP_NAME            App bundle name
                      Default: SEER
  EXPECTED_BUNDLE_ID  Bundle ID sanity check
                      Default: com.colecantcode.ollamacloud.mac
  RUN_XCODEGEN        1 to run xcodegen generate first, 0 to skip
                      Default: 1
  SIGN_APP            1 to sign app with Developer ID cert, 0 to skip
                      Default: 1
  DEVELOPER_ID_APP    Signing identity (required when SIGN_APP=1)
                      Example: Developer ID Application: Your Name (TEAMID)
  NOTARIZE            1 to notarize artifacts, 0 to skip
                      Default: 1
  NOTARY_PROFILE      notarytool keychain profile (required when NOTARIZE=1)
                      Example: seer-notary
  CREATE_DMG          1 to emit .dmg, 0 for zip-only
                      Default: 1
  STABLE_PREFIX       Stable asset prefix for GitHub latest/download links
                      Default: SEER-macos

Examples:
  DEVELOPER_ID_APP="Developer ID Application: Cole Cant Code (ABCDE12345)" \
  NOTARY_PROFILE="seer-notary" \
  scripts/package_macos_direct.sh

  SIGN_APP=0 NOTARIZE=0 scripts/package_macos_direct.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/OllamaCloud.xcodeproj}"
SCHEME="${SCHEME:-OllamaCloudMac}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/OllamaCloudMac-Direct}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist/macos}"
APP_NAME="${APP_NAME:-SEER}"
EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-com.colecantcode.ollamacloud.mac}"
RUN_XCODEGEN="${RUN_XCODEGEN:-1}"
SIGN_APP="${SIGN_APP:-1}"
NOTARIZE="${NOTARIZE:-1}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
CREATE_DMG="${CREATE_DMG:-1}"
DEVELOPER_ID_APP="${DEVELOPER_ID_APP:-}"
STABLE_PREFIX="${STABLE_PREFIX:-SEER-macos}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: missing required command '$1'" >&2
    exit 1
  fi
}

require_cmd xcodebuild
require_cmd codesign
require_cmd ditto
require_cmd xcrun
require_cmd hdiutil

if [[ "${RUN_XCODEGEN}" == "1" ]] && ! command -v xcodegen >/dev/null 2>&1; then
  echo "Error: RUN_XCODEGEN=1 but xcodegen is not installed." >&2
  echo "Install with: brew install xcodegen" >&2
  exit 1
fi

if [[ "${SIGN_APP}" == "1" && -z "${DEVELOPER_ID_APP}" ]]; then
  echo "Error: SIGN_APP=1 requires DEVELOPER_ID_APP" >&2
  exit 1
fi

if [[ "${NOTARIZE}" == "1" ]]; then
  if [[ "${SIGN_APP}" != "1" ]]; then
    echo "Error: NOTARIZE=1 requires SIGN_APP=1" >&2
    exit 1
  fi
  if [[ -z "${NOTARY_PROFILE}" ]]; then
    echo "Error: NOTARIZE=1 requires NOTARY_PROFILE" >&2
    exit 1
  fi
fi

mkdir -p "${OUTPUT_DIR}"
WORK_DIR="${OUTPUT_DIR}/work"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
BUILD_LOG="${OUTPUT_DIR}/build.log"

echo "==> Config"
echo "Project:      ${PROJECT_PATH}"
echo "Scheme:       ${SCHEME}"
echo "Config:       ${CONFIGURATION}"
echo "Output:       ${OUTPUT_DIR}"
echo "Sign app:     ${SIGN_APP}"
echo "Notarize:     ${NOTARIZE}"
echo "Create DMG:   ${CREATE_DMG}"
echo

if [[ "${RUN_XCODEGEN}" == "1" ]]; then
  echo "==> Generating Xcode project"
  (
    cd "${ROOT_DIR}"
    xcodegen generate
  )
fi

echo "==> Building macOS app"
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -destination "platform=macOS,arch=arm64" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  clean build > "${BUILD_LOG}"

BUILT_APP="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
if [[ ! -d "${BUILT_APP}" ]]; then
  echo "Error: built app not found at ${BUILT_APP}" >&2
  echo "See build log: ${BUILD_LOG}" >&2
  exit 1
fi

STAGED_APP="${WORK_DIR}/${APP_NAME}.app"
cp -R "${BUILT_APP}" "${STAGED_APP}"

APP_INFO_PLIST="${STAGED_APP}/Contents/Info.plist"
BUNDLE_ID="$(
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${APP_INFO_PLIST}" 2>/dev/null || true
)"
MARKETING_VERSION="$(
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_INFO_PLIST}" 2>/dev/null || true
)"
BUILD_NUMBER="$(
  /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${APP_INFO_PLIST}" 2>/dev/null || true
)"

if [[ -z "${MARKETING_VERSION}" || -z "${BUILD_NUMBER}" ]]; then
  echo "Error: could not read version/build from ${APP_INFO_PLIST}" >&2
  exit 1
fi

if [[ -n "${BUNDLE_ID}" && "${BUNDLE_ID}" != "${EXPECTED_BUNDLE_ID}" ]]; then
  echo "Error: bundle ID mismatch. Expected '${EXPECTED_BUNDLE_ID}', got '${BUNDLE_ID}'" >&2
  exit 1
fi

BASE_NAME="${APP_NAME}-${MARKETING_VERSION}-${BUILD_NUMBER}-macos"
ZIP_PATH="${OUTPUT_DIR}/${BASE_NAME}.zip"
DMG_PATH="${OUTPUT_DIR}/${BASE_NAME}.dmg"
STABLE_ZIP_PATH="${OUTPUT_DIR}/${STABLE_PREFIX}.zip"
STABLE_DMG_PATH="${OUTPUT_DIR}/${STABLE_PREFIX}.dmg"

if [[ "${SIGN_APP}" == "1" ]]; then
  echo "==> Signing app (${DEVELOPER_ID_APP})"
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "${DEVELOPER_ID_APP}" \
    "${STAGED_APP}"

  echo "==> Verifying signature"
  codesign --verify --deep --strict --verbose=2 "${STAGED_APP}"
fi

echo "==> Creating zip artifact"
rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${STAGED_APP}" "${ZIP_PATH}"

if [[ "${NOTARIZE}" == "1" ]]; then
  echo "==> Notarizing zip"
  xcrun notarytool submit "${ZIP_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
  echo "==> Stapling app"
  xcrun stapler staple "${STAGED_APP}"
  echo "==> Repacking zip with stapled app"
  rm -f "${ZIP_PATH}"
  ditto -c -k --sequesterRsrc --keepParent "${STAGED_APP}" "${ZIP_PATH}"
fi

cp -f "${ZIP_PATH}" "${STABLE_ZIP_PATH}"

if [[ "${CREATE_DMG}" == "1" ]]; then
  echo "==> Creating dmg artifact"
  DMG_STAGE="${WORK_DIR}/dmg-root"
  rm -rf "${DMG_STAGE}"
  mkdir -p "${DMG_STAGE}"
  cp -R "${STAGED_APP}" "${DMG_STAGE}/${APP_NAME}.app"
  ln -s /Applications "${DMG_STAGE}/Applications"

  rm -f "${DMG_PATH}"
  hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGE}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}" >/dev/null

  if [[ "${SIGN_APP}" == "1" ]]; then
    echo "==> Signing dmg"
    codesign --force --timestamp --sign "${DEVELOPER_ID_APP}" "${DMG_PATH}"
  fi

  if [[ "${NOTARIZE}" == "1" ]]; then
    echo "==> Notarizing dmg"
    xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
    echo "==> Stapling dmg"
    xcrun stapler staple "${DMG_PATH}"
  fi

  cp -f "${DMG_PATH}" "${STABLE_DMG_PATH}"
fi

echo
echo "==> Done"
echo "Build log: ${BUILD_LOG}"
echo "App:       ${STAGED_APP}"
echo "ZIP:       ${ZIP_PATH}"
echo "ZIP (stable): ${STABLE_ZIP_PATH}"
if [[ "${CREATE_DMG}" == "1" ]]; then
  echo "DMG:       ${DMG_PATH}"
  echo "DMG (stable): ${STABLE_DMG_PATH}"
fi
