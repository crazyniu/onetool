#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/1Tool.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
NOTARIZE="${NOTARIZE:-0}"
[[ "$NOTARIZE" == 0 || "$NOTARIZE" == 1 ]] || { echo 'NOTARIZE must be 0 or 1.' >&2; exit 1; }
codesign --verify --deep --strict "$APP"
SIGNATURE=$(codesign -dvv "$APP" 2>&1)
IDENTITY=$(printf '%s\n' "$SIGNATURE" | sed -n 's/^Authority=\(Developer ID Application:.*\)/\1/p' | head -1)
SUFFIX=unsigned
if [[ "$SIGNATURE" == *'Authority=Apple Development:'* ]]; then SUFFIX=development; fi
if [[ -n "$IDENTITY" ]]; then SUFFIX=signed-unnotarized; fi
if [[ "$NOTARIZE" == 1 ]]; then
    [[ -n "$IDENTITY" ]] || { echo 'Notarization requires a Developer ID Application signed build. Run RELEASE_SIGNING=1 ./build.sh.' >&2; exit 1; }
    [[ -n "${NOTARY_PROFILE:-}" ]] || { echo 'Set NOTARY_PROFILE to a notarytool Keychain credential profile. See RELEASING.md.' >&2; exit 1; }
    EXT_SIGNATURE=$(codesign -dvv "$APP/Contents/PlugIns/OneToolFinder.appex" 2>&1)
    [[ "$EXT_SIGNATURE" == *"Authority=$IDENTITY"* ]] || { echo 'App and extension must use the same Developer ID certificate.' >&2; exit 1; }
    SUFFIX=notarized
fi
mkdir -p dist
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/onetool-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
# Work on a copy; package failures do not mutate the build under test.
mkdir "$STAGING/image"
ditto "$APP" "$STAGING/image/1Tool.app"
notarize() {
    local artifact="$1" report="$2"
    local args=(--keychain-profile "$NOTARY_PROFILE")
    if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then args+=(--keychain "$NOTARY_KEYCHAIN"); fi
    xcrun notarytool submit "$artifact" "${args[@]}" --wait --timeout 30m --output-format json > "$report"
    python3 - "$report" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
print('Notarization:', r.get('status', 'unknown'), 'Submission:', r.get('id', 'unknown'))
if r.get('status') != 'Accepted':
    sys.exit('Apple did not accept this package. Inspect the submission with notarytool log; no release artifact was produced.')
PY
}
if [[ "$NOTARIZE" == 1 ]]; then
    ditto -c -k --keepParent "$STAGING/image/1Tool.app" "$STAGING/1Tool.zip"
    notarize "$STAGING/1Tool.zip" "$PWD/dist/notary-app.json"
    xcrun stapler staple "$STAGING/image/1Tool.app"
    xcrun stapler validate "$STAGING/image/1Tool.app"
    spctl --assess --type execute --verbose=2 "$STAGING/image/1Tool.app"
fi
ln -s /Applications "$STAGING/image/Applications"
cp LICENSE NOTICE.md "$STAGING/image/"
NAME="1Tool-$VERSION-${PACKAGE_ARCH:-$(if [[ $(lipo -archs "$APP/Contents/MacOS/OneTool" | wc -w | tr -d " ") -gt 1 ]]; then echo universal; else lipo -archs "$APP/Contents/MacOS/OneTool"; fi)}-$SUFFIX.dmg"
# Keep incomplete submissions out of dist and avoid leaving a mislabeled final DMG.
DMG="$STAGING/$NAME"
hdiutil create -volname 1Tool -srcfolder "$STAGING/image" -format UDZO -ov "$DMG"
if [[ -n "$IDENTITY" ]]; then codesign --force --timestamp --sign "$IDENTITY" "$DMG"; fi
if [[ "$NOTARIZE" == 1 ]]; then
    notarize "$DMG" "$PWD/dist/notary-dmg.json"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi
mv "$DMG" "$PWD/dist/$NAME"
(cd dist && shasum -a 256 "$NAME" > "$NAME.sha256")
echo "Created: $PWD/dist/$NAME"
