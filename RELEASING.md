# Releasing

1Tool packages a certificate-free universal DMG. Neither the app nor the DMG is signed with an Apple certificate or notarized. The app and Finder extension use ad-hoc code signatures, which allow the executables to run on Apple Silicon without requiring a signing identity.

## Automatic builds

The **Build DMG** workflow runs on every push to `main`, a version tag (`v1.0.0`, matching `CFBundleShortVersionString`), or manual dispatch from Actions on `main`.

It builds arm64 and x86_64, runs the core checks, packages the app and Finder extension, and uploads the DMG plus a SHA-256 checksum as the **unsigned-dmg** artifact. Version tags also create a GitHub Release with direct downloads.

**No repository Secrets, P12 certificate or Apple API key is required.** The workflow uses the repository's built-in `GITHUB_TOKEN` for publishing tagged releases.

## Local packaging

```sh
CODE_SIGN_IDENTITY=- ARCHS='arm64 x86_64' ./build.sh
./test.sh
PACKAGE_ARCH=universal Tools/package-dmg.sh
```

Output: `dist/1Tool-1.0.0-universal-unsigned.dmg` and its `.sha256` sidecar. The image contains `1Tool.app`, an Applications shortcut and license notices. The packaging script verifies that the app and Finder extension have ad-hoc signatures and refuses a mismatched build.

To verify the checksum, run `shasum -a 256 -c 1Tool-1.0.0-universal-unsigned.dmg.sha256` from the download folder.

## Opening a downloaded build

Because these builds are not Developer ID signed or notarized, macOS may block the first launch. Review the source and download origin before allowing the app through the normal Privacy & Security settings. See [Apple's guidance for opening a Mac app from an unidentified developer](https://support.apple.com/102445). No system-wide security setting needs to be disabled.
