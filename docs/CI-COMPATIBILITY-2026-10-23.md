# CI compatibility repair — October 23, 2026

The final code commit is `1bdd97a34c22a0e3700e9e9d0560ce8e7743867a`. [GitHub workflow 39966290677](https://github.com/crazyniu/onetool/actions/runs/39966290677) completed successfully: universal application build, core checks, DMG packaging and `unsigned-dmg` artifact upload.

Two failures were addressed:

1. The CI Swift compiler timed out on two overloaded string expressions inside package views. Commit `91fb46d` moves the text into explicit `String` computations using `append`, preserving version omission, separators and upgrade fallbacks. The next CI run passed compilation.
2. That run exposed the minimum visible-height filter rejecting `puzzlepiece.fill` on the CI macOS version. Commit `1bdd97a` permits readable wide glyphs down to 12 points high on the existing 22-point canvas. The lower bound still rejects thin marks such as `minus`. All 32 gallery choices, template/active rendering, silhouette and color checks pass on both the local host and CI.

Other chats began developing automatic updates in the shared working directory. The final local validation used a separate snapshot in `build/ci-compat-workspace`; all 102 tracked files were compared byte-for-byte against commit `1bdd97a`. Their uncommitted work was retained and excluded from these fixes.

Local universal build and 327 checks passed: 279 shared + 32 package state + 5 cleanup state + 11 system appearance. No package operation behavior changed, so the previous isolated npm lifecycle acceptance remains applicable. Build/test/package logs are `build/ci-compat-workspace/ci-{build,tests,package}.log`.

The local development-signed package is `dist/1Tool-1.0.0-universal-development-ci-fix.dmg`, SHA-256 `7b84a965aeb1d50e36c1ece14eec5f77eba60efb6445be74d4f95e04dc2b0a29`. Integrity verification, read-only mount and deep/strict app signature verification passed. The packaged executable matches the tested build: SHA-256 `2096ca16b47e68890434a63e8dc1626e7c6dc5336c487ce360d81258b76c9037`. The mount was ejected. The app is Apple Development signed and not notarized; the CI artifact is separately labeled unsigned. The installed application was not replaced.
