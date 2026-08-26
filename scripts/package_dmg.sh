#!/usr/bin/env bash

set -euo pipefail

APP_NAME="Eye Break"
SCHEME_NAME="Eye Break"
PROJECT_NAME="Eye Break.xcodeproj"
CONFIGURATION="Release"
VERSION="1.1.0"
DMG_NAME="EyeBreak-v${VERSION}-universal.dmg"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${ROOT_DIR}/build/release-dmg"
DERIVED_DATA="${BUILD_ROOT}/DerivedData"
STAGING_DIR="${BUILD_ROOT}/staging"
APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
SIGNED_APP_PATH="${STAGING_DIR}/${APP_NAME}.app"
DMG_PATH="${BUILD_ROOT}/${DMG_NAME}"
BINARY_PATH="${SIGNED_APP_PATH}/Contents/MacOS/${APP_NAME}"

log() {
  printf '\n==> %s\n' "$1"
}

fail() {
  printf '\nERROR: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

require_command xcodebuild
require_command lipo
require_command codesign
require_command hdiutil
require_command xattr

cd "${ROOT_DIR}"

log "Checking Xcode schemes"
SCHEME_LIST_OUTPUT="$(xcodebuild -list -project "${PROJECT_NAME}")"
printf '%s\n' "${SCHEME_LIST_OUTPUT}"

if ! printf '%s\n' "${SCHEME_LIST_OUTPUT}" | awk '/Schemes:/{flag=1; next} flag && NF {sub(/^[[:space:]]+/, ""); print}' | grep -Fxq "${SCHEME_NAME}"; then
  fail "Scheme not found: ${SCHEME_NAME}"
fi

log "Cleaning package output"
rm -rf "${BUILD_ROOT}"
mkdir -p "${STAGING_DIR}"

log "Building universal Release app"
xcodebuild \
  -project "${PROJECT_NAME}" \
  -scheme "${SCHEME_NAME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  BUILD_ACTIVE_ARCH_ONLY=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

[[ -d "${APP_PATH}" ]] || fail "Built app not found: ${APP_PATH}"

log "Staging app"
ditto --noextattr --noqtn "${APP_PATH}" "${SIGNED_APP_PATH}"

[[ -f "${BINARY_PATH}" ]] || fail "Main binary not found: ${BINARY_PATH}"

log "Checking app binary architectures before signing"
ARCHS_OUTPUT="$(lipo -archs "${BINARY_PATH}")"
printf 'Architectures: %s\n' "${ARCHS_OUTPUT}"
if [[ " ${ARCHS_OUTPUT} " != *" arm64 "* || " ${ARCHS_OUTPUT} " != *" x86_64 "* ]]; then
  fail "Expected universal binary with arm64 and x86_64, got: ${ARCHS_OUTPUT}"
fi

log "Ad-hoc codesigning app"
find "${SIGNED_APP_PATH}" \( -name ".DS_Store" -o -name "._*" \) -delete
xattr -cr "${SIGNED_APP_PATH}"
xattr -d "com.apple.FinderInfo" "${SIGNED_APP_PATH}" 2>/dev/null || true
xattr -d "com.apple.fileprovider.fpfs#P" "${SIGNED_APP_PATH}" 2>/dev/null || true
xattr -d "com.apple.provenance" "${SIGNED_APP_PATH}" 2>/dev/null || true
codesign --force --deep --sign - "${SIGNED_APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${SIGNED_APP_PATH}"

log "Preparing DMG staging folder"
ln -s /Applications "${STAGING_DIR}/Applications"
rm -f "${DMG_PATH}"

log "Creating DMG: ${DMG_PATH}"
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

log "Verifying DMG"
hdiutil verify "${DMG_PATH}"

log "Package complete"
printf 'DMG: %s\n' "${DMG_PATH}"
