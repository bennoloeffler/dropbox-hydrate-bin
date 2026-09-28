# CLAUDE.md — dropbox-hydrate-bin

A Swift CLI that downloads Dropbox "online only" placeholders (0-byte files) on macOS
**headless**: one `NSFileCoordinator` coordinated read per file, no app, no window.
Why and how it was found: `README.md`. Contract: `docs/SPEC.md` (append-only).
Proof: `docs/EVIDENCE.md`. Handover between sessions: `RP.md`.

## Where things are

| What | Where |
|---|---|
| Project (this folder; the folder name really is `drobox`) | `~/bin/drobox-hydrate-bin-dev/` |
| GitHub (public) | https://github.com/bennoloeffler/dropbox-hydrate-bin |
| Binary (committed, universal, ad-hoc signed) | `bin/dropbox-hydrate-bin` |
| Symlink on PATH | `~/bin/dropbox-hydrate-bin` → `bin/dropbox-hydrate-bin` |
| Python wrapper (uses the binary first, Preview waves as fallback) | `~/bin/dropbox-hydrate` (not in this repo) |
| Marketplace copy (binary only) | `~/projects/ai/vunds-plugins-skills/skills/v-dropbox-hydrate/` (plugins `v-dropbox`, `v-angebot`) |
| Notes for all sessions | `~/.claude/CLAUDE_DROPBOX_HYDRATE.md` |

## Code

- `Sources/HydrateCore/Hydrate.swift`: all logic (`parse`, `isPlaceholder`, `collect`, `hydrate`,
  `coordinatedRead`, `run`). The Dropbox daemon is injected as a `Materializer` closure; tests fake it.
- `Sources/dropbox-hydrate-bin/main.swift`: glue plus the non-macOS guard (exit 3).
- `Tests/HydrateCoreTests/`: XCTest, one test per SPEC scenario (S1–S14, N1).

## Commands

```
swift test                       # 17 tests, ~2 s
scripts/gauntlet.sh              # everything, ~7 min: lint, zero warnings, tests x3 + parallel,
                                 # 100% line coverage, 10 mutants + control, release build,
                                 # real-Dropbox integration (downloads 3 placeholders)
SKIP_INTEGRATION=1 scripts/gauntlet.sh    # without Dropbox
scripts/build-release.sh         # universal binary -> bin/
scripts/integration.sh [BIN] [FOLDER]     # real Dropbox; default folder …/C_Klienten/S
python3 scripts/mutate.py [--control]
```

## Rules for changes

- **Evidence-first** (old-coder): SPEC scenario → RED test → GREEN → gauntlet → EVIDENCE.
  Never weaken a test, never edit test and code in one step.
- `swift format lint --strict` must stay clean. `.swift-format` sets 4 spaces and 110 columns, with no rules disabled.
- The coverage gate is 100% of `HydrateCore` lines. Restructure dead branches rather than adding
  tests that only touch lines.
- The mutation runner needs a clean `Sources/`. Save nothing in `Sources/` while it runs.
- **Releasing a new binary means three copies**: `scripts/build-release.sh`, commit and push here,
  copy the binary into the marketplace skill (check that `shasum -a 256` matches), bump `v-dropbox`
  **and** `v-angebot` in `marketplace.json`, then dev → main → push, then
  `claude plugin marketplace update vunds-plugins-skills && claude plugin update v-angebot@vunds-plugins-skills`,
  then run `scripts/integration.sh <installed-binary>`.
- The integration test really downloads client files (read-only). Point it at old folders.
- Never `open FILE` (Dropbox then opens it in its default app) and never `open -a Preview`
  (restores old windows, leaves hidden error dialogs) as a "quick test".
