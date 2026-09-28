#!/bin/bash
# Universal (arm64 + x86_64) release binary -> bin/dropbox-hydrate-bin, ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --arch arm64 --arch x86_64
OUT=".build/apple/Products/Release/dropbox-hydrate-bin"
[ -x "$OUT" ] || { echo "build-release: missing $OUT" >&2; exit 1; }
mkdir -p bin
cp "$OUT" bin/dropbox-hydrate-bin
codesign --force --sign - bin/dropbox-hydrate-bin
ARCHS=$(lipo -archs bin/dropbox-hydrate-bin)
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || { echo "build-release: not universal: $ARCHS" >&2; exit 1; }
echo "build-release: bin/dropbox-hydrate-bin ($ARCHS, $(bin/dropbox-hydrate-bin --version))"
