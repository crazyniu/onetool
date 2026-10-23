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
