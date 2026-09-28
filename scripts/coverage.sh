#!/bin/bash
# Line coverage of HydrateCore (all logic lives there; main.swift is 6 lines of glue,
# exercised by scripts/integration.sh). Fails when coverage < MIN (default 100).
set -euo pipefail
cd "$(dirname "$0")/.."
MIN="${MIN:-100}"

swift test --enable-code-coverage >/dev/null
BIN=".build/debug/dropbox-hydrate-binPackageTests.xctest/Contents/MacOS/dropbox-hydrate-binPackageTests"
PROF=".build/debug/codecov/default.profdata"
[ -x "$BIN" ] && [ -f "$PROF" ] || { echo "coverage: missing $BIN or $PROF" >&2; exit 1; }

LINE=$(xcrun llvm-cov report "$BIN" -instr-profile "$PROF" Sources/HydrateCore/Hydrate.swift |
    awk '/^TOTAL/ {print $10}')
PCT="${LINE%\%}"
[[ "$PCT" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "coverage: could not parse line coverage '$LINE'" >&2; exit 1; }
echo "coverage: HydrateCore lines $LINE (min $MIN%)"
if awk -v p="$PCT" -v m="$MIN" 'BEGIN { exit !(p < m) }'; then
    xcrun llvm-cov show "$BIN" -instr-profile "$PROF" Sources/HydrateCore/Hydrate.swift \
        -show-line-counts-or-regions | grep -B2 -E '\^0|\| +0\|' >&2 || true  # display only; fails below
    echo "coverage: FAIL" >&2
    exit 1
fi
