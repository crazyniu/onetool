# Releasing

A Developer ID Application signature identifies the publisher. To distribute outside the Mac App Store with normal Gatekeeper acceptance, also submit to Apple's notarization service and staple its ticket. An **Apple Development** certificate supports local development and is not a distribution certificate. File and Automation permissions still apply after notarization.

## Local development

`./build.sh` prefers a valid **Developer ID Application** identity in the login Keychain, then Apple Development, then an ad-hoc signature. `CODE_SIGN_IDENTITY` overrides the choice. The certificate must include its private key. Both the Finder extension and its host are signed with the hardened runtime; certificate signatures receive secure timestamps.

```sh
./build.sh
./test.sh
./build.sh --install
```

## Signed, notarized distribution

In the Apple Developer account or Xcode, create/import a **Developer ID Application** certificate. Keep the certificate's private key in Keychain. Save notarization credentials once using the interactive `notarytool` command (Apple ID with an app-specific password, or an App Store Connect API key). Never put credentials in the repository.

```sh
xcrun notarytool store-credentials onetool-release
RELEASE_SIGNING=1 ARCHS='arm64 x86_64' ./build.sh
./test.sh
NOTARIZE=1 NOTARY_PROFILE=onetool-release PACKAGE_ARCH=universal Tools/package-dmg.sh
```

`RELEASE_SIGNING=1` fails early if the selected identity is not Developer ID Application. For multiple teams, explicitly set `CODE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'`. `NOTARY_KEYCHAIN` can point to a custom Keychain.

The packager verifies both bundles, notarizes a ZIP containing a copy of the app, checks the **Accepted** result, staples and validates the app, creates and signs the DMG, then notarizes and staples the DMG. It checks Gatekeeper assessment for both. Only successful results are moved to `dist/1Tool-VERSION-universal-notarized.dmg`, with a SHA-256 checksum. The build app remains unchanged. Submission IDs and status are saved in `dist/notary-*.json`; use `xcrun notarytool log ID --keychain-profile onetool-release` to inspect an Apple rejection.

Signing alone produces `signed-unnotarized.dmg`. Apple Development builds produce `development.dmg`. Ad-hoc builds produce `unsigned.dmg`. These filenames describe the actual verification level.

## GitHub Actions

The **Build DMG** workflow runs on main, matching version tags, and manual dispatch. It builds both architectures, runs checks, and uploads the package. Tags also create a Release.

Configure these repository Actions secrets to enable automatic Developer ID signing and notarization:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Base64 export of the Developer ID Application certificate and private key |
| `MACOS_CERTIFICATE_PASSWORD` | Password protecting that P12 |
| `APPLE_ID` | Developer account Apple ID |
| `APPLE_APP_PASSWORD` | App-specific password for notarization |
| `APPLE_TEAM_ID` | Developer team ID |

The workflow imports the identity into a temporary Keychain, stores the notary profile there, and deletes the Keychain and P12 in an always-run cleanup step. Secrets are only needed on the release repository; never commit a P12, private key, password, or API key. If no certificate secret is configured, the workflow retains the existing ad-hoc build path and labels the artifact and Release as unsigned. A configured certificate with incomplete credentials fails instead of silently downgrading.

## Certificate-free packages

```sh
CODE_SIGN_IDENTITY=- ARCHS='arm64 x86_64' ./build.sh
./test.sh
PACKAGE_ARCH=universal Tools/package-dmg.sh
```

## Opening a downloaded build

A notarized build can be opened through the normal macOS download flow, subject to Apple's first-launch confirmation and system policy. Unsigned or development builds may require approval in Privacy & Security. Do not disable Gatekeeper globally. Verify the checksum with `shasum -a 256 -c PACKAGE.dmg.sha256`.

References: [Developer ID](https://developer.apple.com/developer-id/), [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Customizing the notarization workflow](https://developer.apple.com/documentation/Security/customizing-the-notarization-workflow), [Opening an unidentified developer's app](https://support.apple.com/102445).
