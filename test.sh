#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
xcrun swiftc -swift-version 5 -parse-as-library \
    Sources/Shared/*.swift Sources/OneTool/{PackageEngine,PackageEnvironments,UninstallEngine,CleanupEngine,StatusIcon,SuperRightClickTemplates,RightClick,InputSourceSelection,DefaultInputSourceCapsLock,InputSources,KeepAwake,HardwareBridge,DisplayHardware,Displays}.swift \
    Tests/Checks.swift Tests/CleanupChecks.swift Tests/UninstallChecks.swift Tests/PackageChecks.swift Tests/PackageEnvironmentChecks.swift -o build/checks
build/checks "$@"
xcrun swiftc -swift-version 5 -parse-as-library \
    Sources/Shared/Localization.swift Sources/OneTool/PackageEngine.swift Sources/OneTool/PackageEnvironments.swift Sources/OneTool/PackageManager.swift \
    Tests/PackageStateChecks.swift -o build/package-state-checks
build/package-state-checks
xcrun swiftc -swift-version 5 -parse-as-library \
    Sources/Shared/Localization.swift Sources/OneTool/CleanupEngine.swift Sources/OneTool/CleanupModel.swift \
    Tests/CleanupStateChecks.swift -o build/cleanup-state-checks
build/cleanup-state-checks
xcrun swiftc -swift-version 5 -parse-as-library \
    Sources/Shared/Localization.swift Sources/OneTool/SystemTheme.swift \
    Tests/SystemThemeChecks.swift -o build/system-theme-checks
build/system-theme-checks
if [[ " $* " == *" --packages-integration "* ]]; then
    xcrun swiftc -swift-version 5 -parse-as-library \
        Sources/Shared/Localization.swift Sources/OneTool/PackageEngine.swift \
        Tests/PackageNpmIntegration.swift -o build/package-npm-integration
    python3 Tests/npm-registry-check.py "$PWD/build/package-npm-integration"
fi
