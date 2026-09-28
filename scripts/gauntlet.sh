#!/bin/bash
# Every layer, one command. Stops at the first red layer.
#   scripts/gauntlet.sh            full run (mutation takes ~5 min, integration downloads 3 files)
#   SKIP_INTEGRATION=1 scripts/gauntlet.sh   without the real-Dropbox layer (e.g. CI, no Dropbox)
set -euo pipefail
cd "$(dirname "$0")/.."
step() { echo; echo "=== $*"; }

step "toolchain";   swift --version 2>&1 | head -1; xcrun llvm-cov --version | grep -m1 version
step "lint";        swift format lint --strict -r Sources Tests Package.swift && echo "lint: clean"
step "build (zero warnings)"
if swift build 2>&1 | grep -E "warning:|error:"; then echo "build: warnings/errors" >&2; exit 1; fi
echo "build: clean"
step "tests x3 (flakiness), one run parallel"
for i in 1 2 3; do swift test 2>&1 | grep -E "^\s*Executed .* tests" | tail -1; done
swift test --parallel 2>&1 | tail -1
step "coverage";    scripts/coverage.sh | tail -1
step "mutation";    python3 scripts/mutate.py
step "mutation negative control (must report SURVIVED)"
if python3 scripts/mutate.py --control; then echo "control did not fail" >&2; exit 1; fi
step "release build"; scripts/build-release.sh | tail -1
if [ "${SKIP_INTEGRATION:-}" = 1 ]; then
    step "integration: SKIPPED (SKIP_INTEGRATION=1)"
else
    step "integration (real Dropbox, release binary)"; scripts/integration.sh bin/dropbox-hydrate-bin
fi
step "source state"; echo "commit $(git rev-parse --short HEAD)$(git diff --quiet || echo ' + uncommitted changes')"
echo; echo "GAUNTLET GREEN"
