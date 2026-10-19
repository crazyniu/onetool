#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
TARGET="$(uname -m)-apple-macosx14.0"
SDK="$(xcrun --show-sdk-path)"
APP="$PWD/build/1Tool.app"
EXT="$APP/Contents/PlugIns/OneToolFinder.appex"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXT/Contents/MacOS"
SOURCES=(Sources/OneTool/*.swift Sources/Shared/*.swift)
echo "Building 1Tool…"
xcrun swiftc -swift-version 5 -parse-as-library -O -target "$TARGET" -sdk "$SDK" \
    "${SOURCES[@]}" -o "$APP/Contents/MacOS/OneTool"
echo "Building Finder extension…"
xcrun swiftc -swift-version 5 -parse-as-library -application-extension -O -target "$TARGET" -sdk "$SDK" \
    Sources/FinderExtension/FinderSync.swift Sources/Shared/SuperRightClickSupport.swift Sources/Shared/Localization.swift \
    -framework FinderSync -framework AppKit -Xlinker -e -Xlinker _NSExtensionMain \
    -o "$EXT/Contents/MacOS/OneToolFinder"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/FinderExtension-Info.plist "$EXT/Contents/Info.plist"
cp -R Resources/FileTemplates "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp NOTICE.md "$APP/Contents/Resources/NOTICE.md"
mkdir -p "$EXT/Contents/Resources"
xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$APP/Contents/Resources"
xcrun xcstringstool compile Resources/InfoPlist.xcstrings --output-directory "$APP/Contents/Resources"
for localization in "$APP/Contents/Resources/"*.lproj; do
    mkdir -p "$EXT/Contents/Resources/$(basename "$localization")"
    cp "$localization/Localizable.strings" "$EXT/Contents/Resources/$(basename "$localization")/"
done
if [[ ! -f build/MenuBarIcon.png || ! -f build/AppIcon.icns || Tools/Icon.swift -nt build/AppIcon.icns || Resources/Brand/logo.png -nt build/AppIcon.icns || Resources/Brand/AppIcon-Default.png -nt build/AppIcon.icns ]]; then
    xcrun swift Tools/Icon.swift build/AppIcon.iconset
fi
cp build/AppIcon.icns build/MenuBarIcon.png build/MenuBarIcon@2x.png "$APP/Contents/Resources/"
IDENTITY="${CODE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)}"
IDENTITY="${IDENTITY:--}"
codesign --force --options runtime --entitlements Resources/FinderExtension.entitlements --sign "$IDENTITY" "$EXT"
codesign --force --options runtime --entitlements Resources/App.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
if [[ "${1:-}" == "--install" ]]; then
    DEST="/Applications/1Tool.app"
    if [[ -d "$DEST" ]]; then
        EXISTING=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DEST/Contents/Info.plist")
        [[ "$EXISTING" == "com.shopkivoo.onetool" ]] || { echo "Refusing to overwrite unrelated application: $EXISTING" >&2; exit 1; }
        osascript -e 'tell application id "com.shopkivoo.onetool" to quit' 2>/dev/null || true
        BACKUP="$PWD/build/1Tool-previous-$(date +%Y%m%d-%H%M%S).app"
        ditto "$DEST" "$BACKUP"
    fi
    ditto "$APP" "$DEST"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
    pluginkit -a "$DEST/Contents/PlugIns/OneToolFinder.appex"
    # Reload only this extension after replacing a running development build.
    pkill -x OneToolFinder 2>/dev/null || true
    open "$DEST"
    echo "Installed: $DEST"
fi
