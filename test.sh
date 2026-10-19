#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
xcrun swiftc -swift-version 5 -parse-as-library \
    Sources/Shared/*.swift Sources/OneTool/{SuperRightClickTemplates,RightClick,InputSourceSelection,DefaultInputSourceCapsLock,InputSources,KeepAwake,HardwareBridge,DisplayHardware,Displays}.swift \
    Tests/Checks.swift -o build/checks
build/checks "$@"
