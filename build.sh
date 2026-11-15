#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
SDK="$(xcrun --show-sdk-path)"
# macOS 26.2 SDK can be newer than the installed Swift compiler.
if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk ]; then SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk; fi
CACHE="${TMPDIR:-/tmp}/usageedge-swift-cache"
mkdir -p "$CACHE" UsageEdge.app/Contents/MacOS UsageEdge.app/Contents/Resources
cp Tools/claude_status.py Tools/setup_claude.py UsageEdge.app/Contents/Resources/
swiftc -sdk "$SDK" -module-cache-path "$CACHE" Sources/Quota.swift Tests/QuotaTests.swift -o "${TMPDIR:-/tmp}/usageedge-tests"
"${TMPDIR:-/tmp}/usageedge-tests"
swiftc -sdk "$SDK" -module-cache-path "$CACHE" Sources/CodexAuth.swift Tests/AuthTests.swift -o "${TMPDIR:-/tmp}/usageedge-auth-tests"
"${TMPDIR:-/tmp}/usageedge-auth-tests"
swiftc -sdk "$SDK" -module-cache-path "$CACHE" Sources/APIProviders.swift Tests/APIProviderTests.swift -o "${TMPDIR:-/tmp}/usageedge-api-tests"
"${TMPDIR:-/tmp}/usageedge-api-tests"
swiftc -sdk "$SDK" -module-cache-path "$CACHE" Sources/KimiLocalRequest.swift Tests/KimiRequestTests.swift -o "${TMPDIR:-/tmp}/usageedge-kimi-tests"
"${TMPDIR:-/tmp}/usageedge-kimi-tests"
python3 Tests/test_claude_status.py
python3 Tests/test_claude_setup.py
python3 Tests/test_package_windows.py
python3 Tests/Integration/run.py "$SDK"
swiftc -sdk "$SDK" -module-cache-path "$CACHE" -target arm64-apple-macos13.0 Sources/Quota.swift Sources/CodexAuth.swift Sources/APIProviders.swift Sources/ProviderAccess.swift Sources/KimiLocalRequest.swift Sources/main.swift -o "$CACHE/UsageEdge-arm64"
swiftc -sdk "$SDK" -module-cache-path "$CACHE" -target x86_64-apple-macos13.0 Sources/Quota.swift Sources/CodexAuth.swift Sources/APIProviders.swift Sources/ProviderAccess.swift Sources/KimiLocalRequest.swift Sources/main.swift -o "$CACHE/UsageEdge-x86_64"
lipo -create "$CACHE/UsageEdge-arm64" "$CACHE/UsageEdge-x86_64" -output UsageEdge.app/Contents/MacOS/UsageEdge
codesign --force --deep --sign - UsageEdge.app
