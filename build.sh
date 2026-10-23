#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITIES=$(security find-identity -v -p codesigning)
    IDENTITY=$(printf '%s\n' "$IDENTITIES" | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)
    if [[ -z "$IDENTITY" ]]; then
        IDENTITY=$(printf '%s\n' "$IDENTITIES" | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)
    fi
fi
IDENTITY="${IDENTITY:--}"
if [[ "${RELEASE_SIGNING:-0}" == 1 && "$IDENTITY" != "Developer ID Application:"* ]]; then
    echo 'Release signing requires a Developer ID Application certificate and its private key. Apple Development is only for development.' >&2
    exit 1
fi
mkdir -p build
ARCHS="${ARCHS:-$(uname -m)}"
SDK="$(xcrun --show-sdk-path)"
APP="$PWD/build/1Tool.app"
# Start clean so retired artwork and resources cannot survive incremental builds.
rm -rf "$APP"
EXT="$APP/Contents/PlugIns/OneToolFinder.appex"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXT/Contents/MacOS"
SOURCES=(Sources/OneTool/*.swift Sources/Shared/*.swift)
APP_BINARIES=()
EXT_BINARIES=()
for arch in $ARCHS; do
    [[ "$arch" == arm64 || "$arch" == x86_64 ]] || { echo "Unsupported architecture: $arch" >&2; exit 1; }
    echo "Building 1Tool ($arch)…"
    APP_BINARY="$PWD/build/OneTool-$arch"
    EXT_BINARY="$PWD/build/OneToolFinder-$arch"
    xcrun swiftc -swift-version 5 -parse-as-library -O -target "$arch-apple-macosx14.0" -sdk "$SDK" \
        "${SOURCES[@]}" -o "$APP_BINARY"
    xcrun swiftc -swift-version 5 -parse-as-library -application-extension -O -target "$arch-apple-macosx14.0" -sdk "$SDK" \
        Sources/FinderExtension/FinderSync.swift Sources/Shared/SuperRightClickSupport.swift Sources/Shared/Localization.swift \
        -framework FinderSync -framework AppKit -Xlinker -e -Xlinker _NSExtensionMain -o "$EXT_BINARY"
    APP_BINARIES+=("$APP_BINARY")
    EXT_BINARIES+=("$EXT_BINARY")
done
xcrun lipo -create "${APP_BINARIES[@]}" -output "$APP/Contents/MacOS/OneTool"
xcrun lipo -create "${EXT_BINARIES[@]}" -output "$EXT/Contents/MacOS/OneToolFinder"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/FinderExtension-Info.plist "$EXT/Contents/Info.plist"
cp -R Resources/FileTemplates "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/"
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
cp build/AppIcon.icns "$EXT/Contents/Resources/"

SIGN_FLAGS=(--force --options runtime --sign "$IDENTITY")
if [[ "$IDENTITY" != - ]]; then SIGN_FLAGS+=(--timestamp); fi
codesign "${SIGN_FLAGS[@]}" --entitlements Resources/FinderExtension.entitlements "$EXT"
codesign "${SIGN_FLAGS[@]}" --entitlements Resources/App.entitlements "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP (signing: $IDENTITY)"
if [[ "${1:-}" == "--install" ]]; then
    DEST="/Applications/1Tool.app"
    if [[ -d "$DEST" ]]; then
        EXISTING=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DEST/Contents/Info.plist")
        [[ "$EXISTING" == "com.shopkivoo.onetool" ]] || { echo "Refusing to overwrite unrelated application: $EXISTING" >&2; exit 1; }
        osascript -e 'tell application id "com.shopkivoo.onetool" to quit' 2>/dev/null || true
        BACKUP="$PWD/build/1Tool-previous-$(date +%Y%m%d-%H%M%S).app"
        ditto "$DEST" "$BACKUP"
    fi
    rsync -a --delete "$APP/" "$DEST/"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
    pluginkit -a "$DEST/Contents/PlugIns/OneToolFinder.appex"
    # Reload only this extension after replacing a running development build.
    pkill -x OneToolFinder 2>/dev/null || true
    open "$DEST"
    echo "Installed: $DEST"
fi
