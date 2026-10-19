# Validation

Current GitHub delivery checks, October 19, 2026. Local environment: Apple Silicon, macOS 27.0.1, Xcode 27.1. These results apply to the GitHub edition.

| Check | Status | Evidence |
| --- | --- | --- |
| Universal app and Finder extension | PASS | `ARCHS="arm64 x86_64" ./build.sh`; both executables contain arm64 and x86_64 slices |
| Core checks | PASS | `./test.sh`: 66 checks, including file safety, templates, localization, input selection logic, DDC parsing and real timed IOPM assertion release |
| Installed app | PASS | Local app updated; `codesign --verify --deep --strict` succeeds; all six settings pages remain available |
| README screenshots | PASS | Captured from the installed full app using native UI tools; Keep Awake, Finder Actions and General |
| Dock artwork fix | PARTIAL | Launch now assigns the bundled blue wrench to the application icon; installed ICNS verified. A separate Dock visual capture was unavailable |
| DMG creation and integrity | PASS | Native disk image created; image checksum validated; mounted app signature and universal slices verified; Applications shortcut present |
| Release guard | PASS | `Tools/package-dmg.sh --release` rejects a missing Developer ID identity before producing a release image |
| Shell and workflow checks | PASS | `bash -n`, ShellCheck and actionlint |
| Fresh hardware coverage | NOT RUN | No new physical brightness, keyboard-backlight or input-switching acceptance claimed by this packaging change |
| Trusted distribution signing / notarization | BLOCKED | Requires the five repository Secrets documented in RELEASING.md; this Mac currently has an Apple Development identity, not Developer ID Application |

CI executes a clean universal build, the core checks and development DMG packaging on a GitHub-hosted macOS runner. The signed workflow separately requires a real distribution identity and successful notarization, stapling and Gatekeeper validation. Local PASS does not imply that those external steps have succeeded.
