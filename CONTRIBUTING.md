# Contributing

Open an issue with the macOS version, Mac model, edition, steps to reproduce and expected behavior. For hardware problems, include the monitor and connection type. Remove private paths and account information from diagnostics.

Keep changes focused and preserve existing settings, GPL notices and file-safety checks. Use native SwiftUI/AppKit APIs; avoid new dependencies for platform features.

Before opening a pull request:

```sh
./build.sh
./test.sh
git diff --check
```

Run hardware checks only when your change affects those integrations and you can safely test the real device. Report PASS, NOT RUN and known limitations separately. Never add certificates, private keys, provisioning profiles or credentials to commits.
