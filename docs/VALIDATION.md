# Validation

Current GitHub delivery checks, October 19, 2026. Local environment: Apple Silicon, macOS 27.0.1, Xcode 27.1. These results apply to the GitHub edition.

| Check | Status | Evidence |
| --- | --- | --- |
| Universal app and Finder extension | PASS | `ARCHS="arm64 x86_64" ./build.sh`; both executables contain arm64 and x86_64 slices |
| Core checks | PASS | `./test.sh`: 66 checks, including file safety, templates, localization, input selection logic, DDC parsing and real timed IOPM assertion release |
| Installed app | PASS | Local app updated; `codesign --verify --deep --strict` succeeds; all six settings pages remain available |
| README screenshots | PASS | Captured from the installed full app using native UI tools; Keep Awake, Finder Actions and General |
| Menu bar only mode | PASS | `LSUIElement=true`, accessory activation policy; Launch Services reports the installed process as `UIElement`; shortcut panel and its Open Settings action verified in the native app |
| DMG creation and integrity | PASS | Native disk image created; image checksum validated; mounted app signature and universal slices verified; Applications shortcut present |
| Certificate-free packaging | PASS | App and Finder extension use ad-hoc signatures with no team identity; unsigned DMG mounted and verified; menu bar mode included |
| Shell and workflow checks | PASS | `bash -n`, ShellCheck and actionlint |
| Fresh hardware coverage | NOT RUN | No new physical brightness, keyboard-backlight or input-switching acceptance claimed by this packaging change |
| Apple certificate signing / notarization | WAIVED | The user explicitly requested a certificate-free DMG. No certificate or notarization Secrets are required |

The Build DMG workflow executes a clean universal build, core checks and certificate-free DMG packaging on a GitHub-hosted macOS runner. Main builds upload the unsigned-dmg artifact; version tags publish the same type of package as a GitHub Release. The previously blocked certificate workflow has been replaced. The installed local build retains its existing development identity to preserve macOS permissions; downloadable DMGs are verified separately as certificate-free.
