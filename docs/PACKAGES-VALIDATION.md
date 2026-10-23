# Package management validation — 2026-10-23

## Final installed application

The main integration chat completed the v7 universal distribution build and installed `/Applications/1Tool.app`, version **1.0.0 (1)**. Main executable SHA-256: `410f84ec7c81c5a41e8d962019619e03c571767e4aa28170d709a317bb41bc03`.

The coordinating chat reported native acceptance in the installed application: Homebrew **143 installed / 50 eligible upgrades**; npm **Node v24.21.0 / npm 11.19.0**, global prefix **`/opt/homebrew`**, **12 packages**. npm's actual online check still reports the existing user-cache `ENOTDIR` failure while preserving the inventory. No package-changing action was performed during final installed-app acceptance. The final change only corrected generic Japanese/Chinese “Available” translations; Swift sources were unchanged. The shared suite passed 279 checks again, and the remaining valid results were reused for **332 total passing checks**. This formal installed-app evidence supersedes the pending installation entries in earlier snapshot sections below; it was supplied by the coordinating chat, without a second CUA session here.

## Global environment and live-inventory follow-up

The user selected **global tools across all detectable Node/npm environments**. The current implementation scans the login-shell PATH and standard Homebrew/nvm/fnm/Volta/asdf/mise installation roots. Each environment binds its npm CLI, matching Node executable and canonical global prefix. Unusual custom locations remain available through Choose Executable. Bun/pnpm direct tools are identified from their root manifests and remain managed by their own tools; project dependencies and flattened transitive dependencies are outside this inventory.

The frozen snapshot in `build/package-environments/workspace` built successfully. After the shared system-theme translations were completed, its full regression run passed **279 shared checks** (including 11 environment checks), **32 package-state checks**, five cleanup-state checks, 11 system-appearance checks and **five real npm lifecycle assertions**. The lifecycle uses a disposable prefix/cache/configuration and a loopback registry. Logs are `build/package-environments/build.log` and `tests.log`. Package production files, package tests and the localization catalog match the snapshot byte for byte; see `source-sha256.json`. The independently refreshed localization resources were compiled into the snapshot app and extension for the final regression run; the coordinating chat owns the subsequent final signed distribution build.

| Check | Result and actual evidence |
| --- | --- |
| Real Homebrew first-open inventory | PASS: 143 installed packages and 50 eligible upgrades, matching read-only CLI metadata. Individual upgrade buttons and Upgrade All (50) are immediately available. Local metadata is explicitly identified. `brew-first-open.ax.txt` / `.jpg` |
| Real npm inventory | PASS: one detected Node v24.21.0 / npm 11.19.0 environment, `/opt/homebrew` prefix and 12 direct global packages. `inventory-probe.log`, `npm-live.jpg` and `inventory-after-ui.log` |
| Actual npm online update check | Environment failure: `~/.npm` points to `/Volumes/Lexar/DevStorage/cache/npm`; npm reports `ENOTDIR` when creating that cache path. The page preserves all 12 packages, exposes the original error and keeps availability unknown without a misleading zero. `npm-live-error.ax.txt`. The user cache/configuration was preserved |
| Two-environment native selection | PASS: switching fixture Node 20 to Node 24 changes the visible version, prefix and package inventory together. Confirmation and executed command/log use the selected Node and prefix. `two-environments.ax.txt` / `.jpg`, `fixture-target-log.ax.txt` |
| Partial npm inventory | PASS: the second fixture emits `ELSPROBLEMS`; its readable package remains listed with an explicit dependency/completeness warning |
| Busy environment controls | PASS: during an eight-second disposable fixture operation, the environment picker, refresh and package changes are disabled; fixed footer and row show progress. Controls return after completion. `busy-environment-locked.ax.txt` |
| Installation confirmation | PASS in the isolated environment: name entry opens final confirmation with environment/name/count, and Cancel returns without starting a new command |
| Dark narrow layout | PASS: real SwiftUI MainView at 880×660 and 1000×760 content sizes; environment menu and Refresh centers align, installation/filter/update controls and package rows remain visible. `brew-dark-narrow.jpg`, `npm-dark-narrow.jpg` |
| Matching runtime outside PATH | PASS: nvm/fnm fixtures are discovered when PATH has no npm; aliases are deduplicated. A copied recovery command still uses the selected Node/prefix when Terminal PATH points at another Node |
| Final installed application | Coordinated separately by the main integration chat. Private native harnesses were stopped and CUA released after these checks |

Native checks used private AppKit applications hosting the real SwiftUI MainView. Unrelated services were lazy in the harness; only catalog discovery was redirected to disposable fixtures for the two-environment cases. Fixture operations verify targeting/UI behavior; the separate real npm lifecycle verifies actual install/update/uninstall state changes. No real Homebrew package was changed.

One real-environment test action was erroneous: after an accessibility refresh changed element numbering, the intended Cancel click instead confirmed installation of `@scope/review-tool`. npm returned E404 because the package does not exist; the subsequent read-only inventory still contained exactly the original 12 packages and no test package. This attempt is recorded in `npm-install-failed.ax.txt` and is **not** counted as an installation success or cancellation test. All subsequent change operations used disposable fixtures. No npm cache repair, user configuration change or successful user-package installation occurred.

## UI-17–19 follow-up

The follow-up snapshot in `build/package-review/workspace` built successfully with ad-hoc signature verification and no compiler diagnostics. Its test run passed 249 shared checks, 28 asynchronous package-state checks and five real npm lifecycle assertions. Logs: `build/package-review/build.log` and `tests.log`. Package production sources and the state test match the snapshot byte for byte; hashes are in `build/package-review/source-sha256.json`.

Native CUA actions operated the actual SwiftUI `MainView` in a private AppKit test application using a disposable 60-package CLI fixture. Unrelated services were lazy and npm was injected only in the harness. The following interactions passed:

| Item | Actual verification | Evidence in `build/package-review/` |
| --- | --- | --- |
| UI-17 | Enable updates-only before checking: explicitly unknown; successful empty check: no updates; failed E401 check: unknown with registry guidance; retry from footer: 60 updates | `unknown-updates.jpg`, `no-updates.jpg`, `failed-check.jpg`, `failed-check.ax.txt` |
| UI-18 | From the last package in a long list, confirm an upgrade and observe a fixed progress bar/current name/0 of 1; after completion the same row and footer report completion | `running-from-bottom.jpg`, `running-from-bottom.ax.txt`, `completed-at-bottom.jpg`, `completed-at-bottom.ax.txt` |
| UI-19 | Simulated administrator prompt failure exposes manual recovery, refresh and retry; Permissions button opens the shared page; returning retains the failure; retry reconfirms the exact failed package and completes | `administrator-failure.jpg` plus native interaction trace |
| UI-19 directory access | Confirm an installation against an EACCES fixture: reported path, directory ownership/npm prefix guidance, original error details and Permissions/refresh/retry controls are visible; no automatic elevation or privacy request | `directory-denial.jpg`, `directory-denial.ax.txt` |
| Large confirmations | A 60-item upgrade sheet scrolls to the last long package name without truncating it; count, major-version explanation, Cancel and Upgrade remain available. Cancel preserves the inventory | `sixty-confirmation.jpg` |

The preview was closed and its process stopped after testing. No installed user package, formal application or system permission was changed. The fixture emits diagnostics and does not perform actual administrator authorization. These checks cover affected package UI interactions, not formal installation identity, all themes, final narrow-window geometry, or complete global Liquid Glass/Figma acceptance. The coordinating chat owns those final checks. The earlier rendering-only and untested-interaction entries below describe the initial baseline and are superseded for these specific fixture interactions.

## Initial baseline

This report covers Homebrew and npm package management in the shared checkout. The coordinating chat owns the final global appearance, installation and native interaction acceptance.

| Check | Result | Evidence |
| --- | --- | --- |
| Integrated snapshot build | PASS | `CODE_SIGN_IDENTITY=- ./build.sh` in `build/package-validation/workspace`; app and Finder extension signature verification passed. Log: `build/package-validation/final-build.log` |
| Shared regression suite | PASS | 233 checks, including cleanup/uninstall regressions and 49 package checks. Log: `build/package-validation/final-tests.log` |
| Real npm lifecycle | PASS | Five assertions: install 1.0.0, detect 2.0.0 with outdated exit 1, upgrade to latest, uninstall, and report registry failure. Disposable global prefix/cache/config and loopback registry; no user package changes |
| Homebrew command fixture | PASS | Installation, upgrade and uninstallation call the selected CLI and reread actual fixture state; formula/cask selection and dependency protections checked |
| Real Homebrew parser | PARTIAL | `brew install --formula --dry-run -- jq` accepted the exact argument structure and produced an installation plan. No real package was installed. A real uninstall/upgrade lifecycle remains untested |
| Live inventory | PASS | Native preview loaded 143 Homebrew packages and 14 npm global packages through detected executables |
| Native page rendering | PASS | Real SwiftUI `MainView` and package pages in a private AppKit preview harness, Simplified Chinese, 1000×760 light and 880×660 dark. Unrelated services were lazy in the harness to avoid changing Finder configuration. Images: `build/package-validation/{brew,npm}-{light,dark-narrow}.png`; log: `build/package-validation/native.log` |
| Localization | PASS | Eight language entries and printf placeholders checked; compiled app/extension translations included in the shared regression suite |
| Final UI click acceptance | NOT RUN | No physical installation, confirmation, upgrade or uninstall button sequence is claimed. Final global Liquid Glass/Figma appearance and interaction acceptance belong to the coordinating chat |
| Real Homebrew package changes | NOT RUN | Existing user formulae and casks were preserved |
| Installed app replacement | NOT RUN | `/Applications/1Tool.app` was preserved; final installation is coordinated separately |

The isolated snapshot avoids concurrent writes to shared Swift sources and the shared `build/1Tool.app`. Its current package engine and page source match the workspace; shared visual files remain owned by the global UI task. Rendering captures establish functional layout and loaded data, not final approval of the evolving global design.

Reproduce the real npm test with `./test.sh --packages-integration`. The fixture uses a canonical temporary path because npm 11's Arborist can treat macOS `/var` symlinks as a linked root and skip its children during `npm outdated`.
