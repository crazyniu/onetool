# Releasing

## GitHub edition: signed and notarized DMG

The release workflow runs on pushes to `main`, version tags (`v1.0.0`, matching `CFBundleShortVersionString`) or manually from Actions on `main`. It builds arm64 + x86_64 on macOS 26. Tagged runs create a public GitHub release; manual runs only upload workflow artifacts.

Add these **repository Actions secrets**:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded P12 containing a Developer ID Application certificate and its private key |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | P12 export password |
| `NOTARY_API_KEY_BASE64` | Base64-encoded App Store Connect team API key (`.p8`) with notarization access |
| `NOTARY_KEY_ID` | API key ID |
| `NOTARY_ISSUER_ID` | Team API issuer UUID |

Export the P12 from Keychain Access on a trusted Mac. Use the repository's Settings → Secrets and variables → Actions to save values. Do not paste credentials into issues or commits. Apple Development and Mac App Distribution certificates are different from Developer ID Application and cannot substitute for it in this workflow.

The identity is imported into a temporary keychain on the ephemeral runner. The job deletes that keychain and credential files in an `always()` cleanup step. No credentials are used on pull requests. Release packaging stops when credentials, notarization, stapling or Gatekeeper validation fail.

For a local release with the appropriate certificate already in your keychain:

```sh
export CODE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export NOTARY_KEY_PATH='/secure/path/AuthKey.p8'
export NOTARY_KEY_ID='YOUR_KEY_ID'
export NOTARY_ISSUER_ID='YOUR_ISSUER_UUID'
ARCHS='arm64 x86_64' ./build.sh
./test.sh
PACKAGE_ARCH=universal Tools/package-dmg.sh --release
```

The DMG contains `1Tool.app`, an Applications shortcut and license notices. The `.sha256` sidecar is created after signing and stapling. CI's `--development` DMGs are clearly labeled and are neither notarized nor distribution-signed.

