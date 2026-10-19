# Validation

## Settings and icon follow-up — October 19, 2026

| Check | Status | Evidence |
| --- | --- | --- |
| Local app build | PASS | Apple Silicon build; installed binary matches the built binary SHA-256; `codesign --verify --deep --strict` passes |
| Core checks | PASS | `./test.sh`: 133 checks, including every retained icon's rendering, green active silhouette, input-settings restoration and per-app edits/removals |
| Input rules in the installed app | PASS | Add TextEdit through the app picker, change its source, quit and reopen: rule and edited choice remain. Remove it, quit and reopen: rule stays removed. The test rule was cleaned up |
| Delete rule without crashing | PASS | Reproduced an exclusivity conflict caused by reading a bound row inside an array mutation; capture the row identifier first. Native UI deletion succeeds and the process remains alive |
| Icon grid and selected text | PASS | Installed app shows exactly four rows of eight icons with aligned centers; General's label and icon use the same pink accent. Updated `images/appearance.png` from the installed app |
| Consistent app artwork | PASS | Host and Finder extension contain identical wrench ICNS files; extension declares that icon. Finder Applications and app sidebar show the blue wrench; old `BrandMark.png` is removed by clean build and replacement |
| Menu bar image size and active color | PASS | 22×22-point image canvas, at most 20×18-point visible symbol, minimum 8-point ink width and 14-point ink height; AppKit square status item. All 32 choices retain their silhouette and render entirely green while active, without a dot |
| Desktop menu bar pixel capture | NOT RUN | Native SystemUIServer access timed out. Image-rendering checks and keep-awake assertions passed; a screenshot of the actual desktop menu bar is not claimed |
| Menu bar process and awake session | PASS | Installed process reports `UIElement`; real system/display sleep assertions are held; user's indefinite session restored after replacement |
| Build script checks | PASS | `bash -n`, ShellCheck and `git diff --check` |
| New DMG / release | WAIVED | User requested local application replacement and code submission only; no packaging command or version tag is used, and the commit skips Actions |
| Fresh Intel and physical hardware acceptance | NOT RUN | This follow-up builds locally for Apple Silicon; hardware brightness/backlight behavior and the prior universal release baseline below were not retested |

The startup bug saved defaults while still loading them, overwriting unread input rules. Loading now completes before saving is allowed. Rules already erased by the old build must be added again.

## Previous distribution baseline — commit 3817505

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
