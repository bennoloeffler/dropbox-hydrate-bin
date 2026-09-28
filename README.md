# dropbox-hydrate-bin

Download Dropbox **"online only"** files on macOS from the command line: **headless**, with no app
launched, no window, no dialog.

```
dropbox-hydrate-bin [--dry-run] [--timeout SEC] [--jobs N] [PATH ...]
```

Folders are searched recursively for placeholders (0-byte files), and each one is downloaded.
Exit `0` = all local, `1` = some stayed empty (listed on stderr), `2` = usage error.

## Why this exists

With Dropbox's classic sync engine on macOS (Dropbox folder in your home folder, not under
`~/Library/CloudStorage`), online-only files are real 0-byte files. Most ways of opening them from
the command line do nothing:

| Tried | Result |
|---|---|
| `cat`, `head`, `read()` | 0 bytes, no download |
| `qlmanage`, `mdimport` | no download |
| `open file` | downloads, but Dropbox then opens the file in its default app (Word, …) |
| `open -a Preview file` | downloads, but launches Preview, restores its old windows, leaves hidden error dialogs |
| background app with no UI as the `open` target | no download |
| **coordinated read** (`NSFileCoordinator`) | **downloads in about 0.5 s, nothing visible** ← this tool |

Each placeholder carries a Launch Services "open with Dropbox.app" attribute, and Dropbox also answers
coordinated reads, which is the call a well-behaved Mac app makes before reading a file. That call is
all this tool does. It is read-only: it reads at most one byte, never writes, never changes attributes.

Measured on macOS 14.8 with Dropbox 272.4. `docs/EVIDENCE.md` has the full test record.

## Install

```
git clone https://github.com/bennoloeffler/dropbox-hydrate-bin && cd dropbox-hydrate-bin
scripts/build-release.sh            # universal binary -> bin/dropbox-hydrate-bin
ln -s "$PWD/bin/dropbox-hydrate-bin" ~/bin/dropbox-hydrate-bin
```

A prebuilt universal binary (arm64 + x86_64, ad-hoc signed) is in `bin/` and on the release page.

## Windows and Linux

The binary is macOS only. Documented alternatives:

- **Windows**: Dropbox uses the Windows Cloud Files API, so simply reading a placeholder downloads
  it. For a whole folder: `attrib +P "<folder>" /s /d` (the "Always keep on this device" pinned
  attribute), or Explorer → right-click → **Make available offline**.
- **Linux**: Dropbox has no online-only files on Linux. A 0-byte file is really empty, or it is
  excluded by selective sync (`dropbox exclude list`).

## Development

```
swift test                 # 17 unit tests
scripts/gauntlet.sh        # lint, zero warnings, tests x3, 100% line coverage, 10 mutants,
                           # release build, real-Dropbox integration test
```

The spec is in `docs/SPEC.md`, the evidence in `docs/EVIDENCE.md`. MIT license.
