#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/1Tool.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
# Apple Silicon executables still require ad-hoc signing; no certificate is used.
for bundle in "$APP" "$APP/Contents/PlugIns/OneToolFinder.appex"; do
    codesign --verify --strict "$bundle"
    SIGNATURE=$(codesign -dv "$bundle" 2>&1)
    [[ "$SIGNATURE" == *'Signature=adhoc'* ]] || { echo 'Build with CODE_SIGN_IDENTITY=- ./build.sh before packaging.' >&2; exit 1; }
done
codesign --verify --deep --strict "$APP"
mkdir -p dist
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/onetool-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/1Tool.app"
ln -s /Applications "$STAGING/Applications"
cp LICENSE NOTICE.md "$STAGING/"
DMG="$PWD/dist/1Tool-$VERSION-${PACKAGE_ARCH:-$(uname -m)}-unsigned.dmg"
hdiutil create -volname 1Tool -srcfolder "$STAGING" -format UDZO -ov "$DMG"
(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Created: $DMG"
