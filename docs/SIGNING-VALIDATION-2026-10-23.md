# Developer ID signing and notarization — October 23, 2026

A Developer ID Application identity for team `WT475Q2P69` was created through Xcode with the user's confirmation. The selected identity alone was exported as an encrypted PKCS12 in memory, and its Base64 value and randomly generated export password were transferred directly to repository Actions secrets. No private keys or passwords were committed or printed.

All five required repository secrets are configured: `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_APP_PASSWORD`, and `APPLE_TEAM_ID`. Apple notarization credentials were validated successfully and stored locally under the `onetool-release` Keychain profile.

The tested code is commit `1bdd97a`; the GitHub run uses `aa3be22`, which adds only its validation documentation. Uncommitted app-update work in the shared workspace is excluded. Local packaging uses the isolated `build/signing-release-workspace`, populated from the same tested code, with its existing universal executable re-signed using Developer ID Application.

## Local package: PASS

- Host and Finder extension: hardened runtime, secure timestamp, Developer ID Application signature; deep/strict validation passed.
- App notarization: Accepted, submission `079c26e5-c4af-4f62-a7a4-ee3e3420ccd1`.
- DMG notarization: Accepted, submission `1a3b6802-a930-45bc-9483-69a6614ff8e4`.
- App and DMG tickets: stapled and validated.
- Gatekeeper: app execute assessment and DMG open assessment both accepted as `Notarized Developer ID`.
- Final DMG integrity, read-only mounting, embedded-app signature, stapled ticket and architecture checks: PASS; mount ejected.
- Package: `dist/1Tool-1.0.0-universal-notarized.dmg`.
- SHA-256: `f39117d536a301fed0d832e1f48d581bd800a6b5f84d4dc527cde92eba6b2a6f`.
- Architectures: x86_64 and arm64. Version: 1.0.0 (1).

Local logs and Apple submission reports are under `build/signing-release-workspace/` and `build/signing-setup/`. This packaging changes signatures and notarization tickets; it does not change the tested app behavior or extend prior UI/permission acceptance claims.

## GitHub package: PASS

[Workflow 39970439617](https://github.com/crazyniu/onetool/actions/runs/39970439617) completed successfully with the configured signing credentials: signing setup, universal build, 327 core/state checks, Apple notarization, stapling, Gatekeeper assessment and artifact upload.

Download the [notarized-dmg artifact](https://github.com/crazyniu/onetool/actions/runs/39970439617/artifacts/12508249757). It contains `1Tool-1.0.0-universal-notarized.dmg` and its SHA-256 file. The downloaded artifact was independently checked locally:

- SHA-256 matches the uploaded checksum: `0679b39a8d9eb15df3409f1f2be72fcb6afb397c77363e539fa62d207dda8177`.
- DMG signature verifies as Developer ID Application for team `WT475Q2P69`, with a secure timestamp and stapled notarization ticket.
- DMG ticket validation and Gatekeeper open assessment pass (`Notarized Developer ID`).
- DMG integrity and read-only mounting pass; contained app passes deep/strict signature verification, stapled-ticket validation and Gatekeeper execute assessment.
- Verification mount ejected; downloaded evidence is in `build/signing-setup/github-artifact/`.

The local and CI package checksums differ because they are separately compiled/signed artifacts. Both passed notarization and Gatekeeper validation. This manual main-branch workflow uploads an Actions artifact; it does not create a version-tagged GitHub Release. No credentials are included in these public validation notes.

## Published Release v1.0.1

[Release v1.0.1](https://github.com/crazyniu/onetool/releases/tag/v1.0.1) is published, non-draft and non-prerelease. The pre-existing v1.0.0 tag was preserved; the new v1.0.1 tag points to `79fc0ca476678a83126a6160a39d3ff72abdd87a`, which changes only the app and Finder extension versions to 1.0.1, build 2. [Tag workflow 39971687328](https://github.com/crazyniu/onetool/actions/runs/39971687328) passed build, 327 checks, signing, notarization, packaging and Release publication.

The published assets are `1Tool-1.0.1-universal-notarized.dmg` and its `.sha256` file. The actual Release download was independently verified: matching SHA-256 `7da1bfe133111b1249e648a163345f91bb8c1fa841a24e6e91cd81980a721a90`, valid Developer ID DMG/app signatures, stapled tickets and successful Gatekeeper assessments. The mounted app reports 1.0.1; the mount was ejected. Downloaded verification evidence is under `build/release-1.0.1/`.
