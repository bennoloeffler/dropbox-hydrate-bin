# SPEC — dropbox-hydrate-bin

Status: **autonomous run — spec approval not obtained** (the request came as a `/goal`;
this spec is the artifact to review after the fact). Append-only: revisions go to the end.

## Why

Dropbox's legacy sync engine on macOS stores "online only" files as real 0-byte files.
`cat`/`read()` return 0 bytes and trigger nothing. The old tool (`~/bin/dropbox-hydrate`)
downloads them with `open -a Preview`, which launches Preview, restores its old windows
and leaves hidden error dialogs behind.

Measured on 2026-09-26 (macOS 14.8.5, Dropbox 272.4): a **coordinated read**
(`NSFileCoordinator.coordinate(readingItemAt:)`) makes Dropbox download the file in about 0.5 s,
with no app, window or dialog. Control: a plain read on the same placeholder left it at 0 bytes.

## Behaviour (acceptance criteria)

CLI: `dropbox-hydrate-bin [--dry-run] [--timeout SEC] [--jobs N] PATH...`
(no PATH means `.`; also `--help`/`-h`, `--version`).

| # | Scenario | Expected |
|---|---|---|
| S1 | placeholder = regular file, size 0, name not starting with `.` or `~$` | counted |
| S2 | non-empty file, symlink, directory, missing path | not a placeholder |
| S3 | directory argument | walked recursively; hidden dirs (`.x`) skipped; hidden/`~$` files skipped |
| S4 | explicit file argument that is hidden but 0 bytes | counted (the user named it) |
| S5 | duplicates (same file via two args) | counted once, sorted output |
| S6 | `--dry-run` | lists the placeholders, touches nothing (the materializer is never called), exit 0 |
| S7 | nothing to do | prints "nothing to do", exit 0 |
| S8 | every placeholder gains bytes after its coordinated read | exit 0, summary "N/N local" |
| S9 | some stay 0 bytes (e.g. a file that is really empty) | exit 1, lists them on stderr |
| S10 | the materializer hangs longer than `--timeout` seconds for a file | that file counts as failed, the run goes on, exit 1 |
| S11 | `--jobs N` | at most N files are coordinated at the same time |
| S12 | unknown flag, missing value, non-positive number, nonexistent path | usage error on stderr, exit 2 |
| S13 | `--help` | usage text naming the Windows/Linux alternatives, exit 0 |
| S14 | `--version` | prints the version, exit 0 |
| S15 | real Dropbox placeholder (integration) | goes from 0 to >0 bytes; no GUI app started; Dropbox logs no "Opening document" |
| S16 | built on a non-macOS platform | the binary prints an error that points to the documented alternatives, exit 3 |

## Must NOT

- N1 never write to a file (read-only: no open-for-write, no xattr changes).
- N2 never launch an app or show UI (checked in the integration test S15).
- N3 plain reads must stay insufficient: the integration test carries a negative control
  (plain read → still 0 bytes) so a green run proves the *coordination* did it.
- N4 `~/bin/dropbox-hydrate` keeps its CLI (`--dry-run --timeout --batch PATH...`, exit 0/1/2).

## Windows / Linux

The binary is macOS only (Mach-O, universal arm64 + x86_64). Documented alternatives,
shown by `--help`, the SKILL.md and the README:
- **Windows** (Dropbox uses the Windows Cloud Files API): reading a placeholder downloads it;
  bulk: `attrib +P "<folder>" /s /d` ("Always keep on this device", Microsoft-documented
  pinned attribute) or Explorer → right-click → "Make available offline".
- **Linux**: Dropbox has no online-only files on Linux, so there is nothing to download. A 0-byte file is
  really empty, or excluded by selective sync (`dropbox exclude list`).

## Setup plan (authorized by this spec)

- Project `~/bin/drobox-hydrate-bin-dev/` (path exactly as requested), `git init`, commit at
  SPEC, GREEN, and gauntlet. SwiftPM: library `HydrateCore` (logic, tested),
  executable `dropbox-hydrate-bin` (thin `main.swift`), tests `HydrateCoreTests` (XCTest).
- **No dependencies** beyond Foundation/XCTest from Xcode 16 (Swift 6.0.3). Lint: `swift format lint`
  (ships with the toolchain).
- Files: `Package.swift`, `Sources/**`, `Tests/**`, `scripts/gauntlet.sh` (one entry point),
  `scripts/coverage.sh`, `scripts/mutate.sh`, `scripts/integration.sh`,
  `scripts/build-release.sh`, `README.md`, `LICENSE` (MIT), `docs/SPEC.md`, `docs/EVIDENCE.md`.
- GitHub: public repo `bennoloeffler/dropbox-hydrate-bin` (correct spelling; the local folder
  keeps the requested `drobox` name).
- `~/bin/dropbox-hydrate-bin` → symlink to `~/bin/drobox-hydrate-bin-dev/bin/dropbox-hydrate-bin`.
- `~/bin/dropbox-hydrate` (Python): hydrate with the binary first, keep the Preview waves only as
  a fallback for files that stay empty (backup first).
- Marketplace `~/projects/ai/vunds-plugins-skills` (branch `dev` → merge `main` → push, as the
  deploy rule says): new skill `skills/v-dropbox-hydrate/` = `SKILL.md` + `bin/dropbox-hydrate-bin`
  (the **binary only**, no source). Added to the `v-dropbox` and `v-angebot` plugins; versions bumped;
  `v-angebot-word-bel` points to it for 0-byte files. The installed `v-angebot` plugin gets updated here.

## Isolation

New repo, so there is no working tree to protect. The marketplace is changed on its `dev` branch.
Edits to `~/bin/dropbox-hydrate` and `~/.claude/*.md` get a `.claude-backup` first.
