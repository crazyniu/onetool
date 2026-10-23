# UI, uninstall and npm fixes — October 23, 2026

## Changes

- Input-source rule rows group the popup with its removal button at the right edge. The reserved popup width no longer separates the two controls.
- All 1Tool npm subprocesses use `~/Library/Caches/com.shopkivoo.onetool/npm`. The original `~/.npm` link and npm configuration remain unchanged. The copied recovery command carries the same cache override, paired Node and global prefix, and clears conflicting uppercase cache overrides.
- A permission failure moving the selected app into recovery now falls back to `NSWorkspace.recycle` on the main run loop. This is restricted to the validated application at index zero; data-directory permission errors never use authorization. A denied/cancelled native operation leaves app and data untouched. Data moves only after application removal succeeds. The recovery manifest records the actual native Trash destination when this path is used.
- Permissions now includes App Management, with a verified System Settings deep link. Uninstall permission diagnostics distinguish applications from protected app containers and provide relevant settings/restart/rescan guidance. No global authorization state is inferred from an access-denied error.

## Validation

- Isolated universal build: PASS. Tests: 286 shared + 32 package state + 5 cleanup state + 11 system appearance + 5 disposable npm integration = 339 PASS. Logs under `build/issue-fixes-workspace/`.
- New regression tests cover broken user-cache symlinks without mutating them, cancelled native Trash preserving app/data, app-first ordering after native Trash, and recording the native destination in the recovery manifest.
- Real npm read-only checks: 12 global packages, 8 available updates, successful checking, inventory unchanged. The original broken `~/.npm` symlink remains unchanged. Native preview shows “8 updates available” and enables Upgrade All (8), without the ENOTDIR error. No real package was installed, upgraded or uninstalled.
- Native input-source preview: both controls are adjacent; removing the iTerm fixture rule removes only that rule, retaining Termius. The isolated input-switching setting remained off; real user rules were not modified.
- Native uninstall UI: inspected a disposable app, confirmed the exact fixture path, and moved it to recoverable Trash with a manifest. Its first scan was correctly rejected after filesystem metadata changed; an explicit rescan and new confirmation succeeded. Real CaffeineBar and its data remain in place. A user attempt in the original app exposed POSIX EACCES (13) at the app path, independently of the protected-container read failure.
- App Management link opens the correct macOS settings page. No App Management or Full Disk Access grant was changed.
- NOT RUN: administrator approval and actual removal of the user's root-owned CaffeineBar; granting access to and deleting its protected app container. The native authorization fallback is covered by injected cancellation/success tests; the real OS authentication interaction still requires user acceptance.

Native evidence: `build/issue-native/input-alignment.png`, `uninstall-result.ax.txt`, `uninstall-result.png`, `npm-updates.ax.txt`, `npm-updates.png`. The preview app has a separate bundle identifier and was stopped after review.

The snapshot excludes another chat's unfinished app-update feature. Source changes shared with that feature are staged selectively; its work is retained.

## Delivered 1.0.2 (build 3)

[Release v1.0.2](https://github.com/crazyniu/onetool/releases/tag/v1.0.2), code `87b382b15c8403455d046fa0ffef4c0ca71754be`, [successful tag workflow 39976673499](https://github.com/crazyniu/onetool/actions/runs/39976673499). CI passed universal build, 334 core/state checks, signing, notarization and publication; the 5 isolated npm lifecycle checks also passed locally.

Downloaded Release DMG SHA-256 `213fa912a8b824b6bee561ebc53dcfc5a70d2426d5d2fde461dbdfec37b0cb25` matches the published checksum. DMG/app signatures, stapled tickets and Gatekeeper acceptance were verified. The official package was installed to `/Applications/1Tool.app`; its executable SHA-256 `c41fbb09d3fc88c13e0afe994196ac5b3f72dc2e3bf67dba495f200a7000dc9d` matches the mounted release app. The previous app is backed up at `build/1Tool-before-issue-fixes-1.0.2.app`; verification mount ejected.

Formal installed-app review confirmed that the user's enabled input-source settings, WeChat global input source and iTerm/Termius ABC rules are retained, with the new control grouping. npm shows 12 installed packages and 8 updates without the earlier error. The original active indefinite keep-awake session and display-on setting were restored after normal quit/install/relaunch. The app is left on Input Sources for review. Native installed evidence: `build/issue-native/installed-{input,npm}.{png,ax.txt}`. The real app/permission acceptance limitations listed above remain applicable.
