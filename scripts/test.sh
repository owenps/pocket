#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_PATH="${DEVELOPER_DIR:-$(xcode-select -p)}"
FRAMEWORKS="$DEVELOPER_PATH/Library/Developer/Frameworks"
TEST_LIBS="$DEVELOPER_PATH/Library/Developer/usr/lib"
SWIFT_TEST=(swift test --package-path "$ROOT")

# Some CLT-only installations ship Swift Testing without SwiftPM search paths.
if [[ "$DEVELOPER_PATH" == */CommandLineTools && -d "$FRAMEWORKS/Testing.framework" ]]; then
    SWIFT_TEST+=(--disable-xctest
        -Xswiftc -F -Xswiftc "$FRAMEWORKS"
        -Xlinker -F -Xlinker "$FRAMEWORKS"
        -Xlinker -rpath -Xlinker "$FRAMEWORKS"
        -Xlinker -rpath -Xlinker "$TEST_LIBS")
fi

# Report fast failures first; don't interleave native clocks with the unit suite.
if [[ $# -eq 0 ]]; then
    "${SWIFT_TEST[@]}" --filter PocketTests
    exec "${SWIFT_TEST[@]}" --skip-build --filter PocketAnimationTests --no-parallel
fi

exec "${SWIFT_TEST[@]}" "$@"
