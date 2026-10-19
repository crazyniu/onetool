#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:---release}"
[[ "$MODE" == --release || "$MODE" == --development ]] || { echo 'Usage: Tools/package-dmg.sh [--release|--development]' >&2; exit 1; }
APP="$PWD/build/1Tool.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [[ "$MODE" == --release ]]; then
    [[ "$IDENTITY" == 'Developer ID Application:'* ]] || { echo 'Release requires a Developer ID Application identity.' >&2; exit 1; }
    : "${NOTARY_KEY_PATH:?Set NOTARY_KEY_PATH}"
    : "${NOTARY_KEY_ID:?Set NOTARY_KEY_ID}"
    : "${NOTARY_ISSUER_ID:?Set NOTARY_ISSUER_ID}"
    codesign -dv "$APP" 2>&1 | grep -Fq "Authority=$IDENTITY" || { echo 'App is not signed with the release identity.' >&2; exit 1; }
fi
codesign --verify --deep --strict "$APP"
mkdir -p dist
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/onetool-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
# ditto preserves the signed bundle, including its Finder extension.
ditto "$APP" "$STAGING/1Tool.app"
ln -s /Applications "$STAGING/Applications"
cp LICENSE NOTICE.md "$STAGING/"
SUFFIX="${PACKAGE_ARCH:-$(uname -m)}"
if [[ "$MODE" == --development ]]; then SUFFIX="$SUFFIX-development"; fi
DMG="$PWD/dist/1Tool-$VERSION-$SUFFIX.dmg"
hdiutil create -volname 1Tool -srcfolder "$STAGING" -format UDZO -ov "$DMG"
if [[ "$MODE" == --release ]]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
    codesign --verify --strict "$DMG"
    xcrun notarytool submit "$DMG" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait --timeout 30m
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi
(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Created: $DMG"
