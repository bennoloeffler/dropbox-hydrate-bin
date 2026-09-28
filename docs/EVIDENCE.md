# EVIDENCE — dropbox-hydrate-bin 1.0.0

- **Spec approval: not obtained (autonomous run).** The work came as a `/goal`; `docs/SPEC.md` was
  committed first (2cb1632) and is the artifact to review after the fact. Confidence is lower accordingly.
- Tier 2 (small tool). Some Tier 3 care because it touches client files: it is read-only, and that is checked by N1/M9.
- Independent verification: **not performed**.
- Source state of the final run: commit `41761d9`. The untracked `CLAUDE.md` and the log did not affect the build.
  Full log: `docs/gauntlet-final.log`. Rerun everything with `scripts/gauntlet.sh`.
- Toolchain: Apple Swift 6.0.3 (Xcode 16), Apple LLVM 16.0.0, macOS 14.8.5 arm64, Dropbox 272.4.3731.
- Released binary: `bin/dropbox-hydrate-bin`, universal x86_64 + arm64, ad-hoc signed,
  sha256 `ae9280b68fdd10af5ff8d9aa7621dc9a3a63b8c488915531af208244f9ad3272`. Builds deterministically:
  three builds gave the same hash.

## Scenarios → tests

| SPEC | Verified by |
|---|---|
| S1 placeholder = empty regular file | `testEmptyRegularFileIsPlaceholder` |
| S2 non-empty / symlink / dir / missing | `testNonEmptySymlinkDirectoryAndMissingAreNotPlaceholders` (passed against the stub → proven by mutant M1) |
| S3 recursive, hidden + `~$` skipped | `testDirectoryWalkIsRecursiveAndSkipsHiddenAndOfficeLockFiles` (M2, M3) |
| S4 explicit hidden file counted | `testExplicitHiddenFileIsCounted` |
| S5 duplicates once, sorted | `testDuplicatesAreCountedOnceAndSorted` |
| S6 dry run never downloads | `testDryRunListsAndNeverCallsTheMaterializer` (M7) |
| S7 nothing to do | `testNothingToDo` |
| S8 all hydrated → exit 0 | `testAllPlaceholdersHydratedExitsZero` |
| S9 some stay empty → exit 1, stderr | `testFilesThatStayEmptyExitOneAndAreListedOnStderr` (M8) |
| S10 timeout per file, run goes on | `testHangingFileTimesOutAndTheRunGoesOn` (M6) |
| S11 `--jobs` limits concurrency | `testJobsLimitsConcurrency` (M5) |
| S12 usage errors → exit 2 | `testUsageErrorsExitTwo`, `testParseDefaultsAndValues` (M4, M10) |
| S13 help names Windows/Linux alternatives | `testHelpNamesTheWindowsAndLinuxAlternatives` |
| S14 version | `testVersion` |
| S15 real Dropbox, no app | `scripts/integration.sh`, run against the dev build, the release binary **and the binary installed from the marketplace** (all 3/3) |
| S16 non-macOS → error, exit 3 | **not executed**: no Linux/Windows toolchain here. The guard is compiled out on macOS; only reviewed by reading it |
| N1 never writes | `testCoordinatedReadIsReadOnly` (passed against the stub → proven by mutant M9) |
| N2 no app / UI | integration: `lsappinfo` before/after + Dropbox log "Opening document" = 0 |
| N3 plain read insufficient | integration negative control (plain read → still 0 bytes after 3 s), on every run |
| N4 `dropbox-hydrate` keeps its CLI | manual real runs (below). It lives outside this repo and has no test suite |

## Gauntlet (final fresh run, `scripts/gauntlet.sh`, exit 0)

| Layer | Result |
|---|---|
| Lint `swift format lint --strict` (4 spaces, 110 cols, no rules disabled) | clean |
| Build | zero warnings, zero errors |
| Tests ×3 + 1 parallel (flakiness) | 17/17, 17/17, 17/17; parallel `[17/17]` |
| Coverage `HydrateCore` lines, gate `MIN=100`, exits nonzero below | **100.00%** |
| Mutation (manual, persisted `scripts/mutate.py`, proves each mutant applied via `git diff`, restores via git) | **10/10 killed** |
| Release build | universal x86_64 + arm64, 1.0.0 |
| Integration (release binary, real Dropbox) | 3/3 downloaded (273 346 / 504 521 / 226 759 bytes), no app started, no document handed on |
| Supply chain | no dependencies (Foundation/XCTest only); capabilities: file reads plus threads, no network, no subprocess, no writes |

## Negative controls (each checker shown failing on a known-bad input)

| Checker | Control | Result |
|---|---|---|
| coverage gate | real run at 99.35% before a refactor | `coverage: FAIL`, exit 1 |
| mutation runner | `mutate.py --control` (harmless comment edit) | `C0 SURVIVED`, exit 1 (also inside every gauntlet run) |
| integration: size check | "binary" that does nothing | `still empty`, exit 1 |
| integration: no-app check | "binary" that uses `open -a Preview` | `new app(s) appeared: com.apple.Preview`, exit 1 |

Limit: a control proves that one known-bad case reaches the failure path, not that every
violation is recognized. For example, the no-app check only sees apps that register with Launch Services.

## Downstream (outside this repo), checked for real

- `~/bin/dropbox-hydrate-bin` symlink resolves, `--version` 1.0.0.
- `~/bin/dropbox-hydrate` (Python): binary first, Preview waves only as fallback.
  - One file: 1/1, exit 0.
  - A whole folder (`C_Klienten/S/Sollich`, picked by accident instead of a small one): 228/228, exit 0, Preview never started.
  - A genuinely empty file: binary → fallback → exit 1, Preview terminated again.
  - `--dry-run`: exit 0.
- Marketplace `vunds-plugins-skills` e17a423 (dev → main, pushed): skill `v-dropbox-hydrate` = SKILL.md +
  binary (mode 100755, same sha256), in `v-dropbox` 0.2.0 and `v-angebot` 1.3.0. CI checks rerun locally:
  JSON, skill paths, `overview.py --check`, README regenerated, `claude plugin validate .` passed.
- Installed plugin `v-angebot` 1.0.0 → 1.3.0: the binary in the plugin cache has the same sha256, no quarantine flag,
  and `scripts/integration.sh <installed binary>` passed 3/3.

## Honest limits

- Measured on one Mac (macOS 14.8.5, Dropbox 272.4, legacy sync engine). It is not known whether a future
  Dropbox version keeps answering coordinated reads. The integration test would catch that (N3 control plus size check).
- On Dropbox's newer File-Provider setup it should work too (coordinated reads are the official path there), but that is **untested**.
- Windows/Linux: the text alternatives are researched (Microsoft's documented `attrib +P` pinned attribute;
  Dropbox docs: no online-only files on Linux), **not executed**.
- The skill does not follow the V&S Gate/Preflight pattern (no `SKILL_INSTALLED.md`, no preflight scripts).
  It has no dependencies to install, and the goal asked for "only the binary". The `v-angebot` skills don't follow it either.
- Every integration run downloads 3 real client files (read-only). All controls and runs today together downloaded
  about 250 files, mostly from `C_Klienten/S`.
