# RESTART-PROMPT 001 — dropbox-hydrate-bin

Stand: 2026-09-28, 1.0.0 ausgeliefert (GitHub, ~/bin, Marketplace, lokales Plugin).

## ⏭️ RESUME HERE — TODOs

1. **Benno: SPEC nachträglich prüfen.** `docs/SPEC.md` wurde autonom gebaut (keine Freigabe vor dem Code).
   Stimmt das Verhalten (Timeout 60 s pro Datei, 4 parallel, Exit 0/1/2)? → `cat docs/SPEC.md`
2. Optional: File-Provider-Dropbox testen (falls der Mac migriert wird: Ordner liegt dann unter
   `~/Library/CloudStorage/`). → `scripts/integration.sh bin/dropbox-hydrate-bin "<neuer Ordner>"`
3. Optional: V&S Gate/Preflight-Pattern für das Skill `v-dropbox-hydrate` nachrüsten, falls gewünscht
   (bewusst weggelassen: keine Abhängigkeiten, Auftrag „nur das Binary").
4. Optional: CI-Workflow (GitHub Actions macOS-Runner) mit `SKIP_INTEGRATION=1 scripts/gauntlet.sh`.

## Was das ist

Swift-CLI, das Dropbox-„online only"-Platzhalter (0-Byte-Dateien) auf macOS kopflos herunterlädt:
ein `NSFileCoordinator`-coordinated-read pro Datei. Ersetzt den alten Weg `open -a Preview`, der
Preview startete, alte Fenster (Kunden-PDFs) wiederherstellte und versteckte Fehlerdialoge hinterließ.

## Stand (gemessen, `docs/EVIDENCE.md`, Log `docs/gauntlet-final.log`)

- 17 Tests ×3 grün + parallel, 100 % Zeilenabdeckung `HydrateCore`, 10/10 Mutanten getötet,
  Lint strict sauber, 0 Warnungen, Integration gegen echte Dropbox 3/3, keine App gestartet.
- Binary universal, sha256 `ae9280b6…ad3272`, deterministisch.
- GitHub public: https://github.com/bennoloeffler/dropbox-hydrate-bin (Release v1.0.0 mit Binary).
- `~/bin/dropbox-hydrate-bin` → `bin/dropbox-hydrate-bin`; `~/bin/dropbox-hydrate` (Python) nutzt es zuerst.
- Marketplace `vunds-plugins-skills` main e17a423: Skill `v-dropbox-hydrate` (nur Binary) in
  `v-dropbox` 0.2.0 + `v-angebot` 1.3.0; lokal installiertes `v-angebot` auf 1.3.0 aktualisiert
  (braucht Claude-Neustart), Binary dort per Integrationstest geprüft.

## Runbook (belmac)

```
cd ~/bin/drobox-hydrate-bin-dev
swift test                              # 2 s
scripts/gauntlet.sh                     # ~7 min, alles; lädt 3 echte Platzhalter
scripts/build-release.sh                # -> bin/
dropbox-hydrate-bin --dry-run "<ordner>"
```

Neue Version ausliefern: Schritte in `CLAUDE.md` („Releasing a new binary means three copies").

## Gotchas

- `open DATEI` → Dropbox öffnet die Datei danach in der Standard-App (Word!). `open -a Preview` →
  alte Fenster + versteckte Dialoge, die `quit` blockieren. Beides nie als „schneller Test".
- Hintergrund-App ohne UI als `open`-Ziel hydriert **nicht**; plain `read()` auch nicht.
- XCTest: `run`/`version` kollidieren mit XCTestCase-Membern → im Test `HydrateCore.run` qualifizieren.
- llvm-cov zeigt unabgedeckte Regionen nur mit `-show-line-counts-or-regions` (`^0`).
- `swift test --parallel` druckt keine „Executed"-Zeile; Zahl steht in `[17/17] …`.
- GNU-`stat` auf belmac: in Skripten `/usr/bin/stat -f %z`.
- Ordnername ist wirklich `drobox-…` (so beauftragt); Repo heißt korrekt `dropbox-hydrate-bin`.

## Was ehrlich fehlt

- Windows/Linux-Hinweise recherchiert, nicht ausgeführt. S16 (Nicht-macOS-Guard) nicht ausgeführt.
- Nur ein Mac/Dropbox-Version gemessen. Keine unabhängige Verifikation.
- Integrationstest lädt echte Kundendateien (read-only); heute ~250 Dateien, u. a. ganz `C_Klienten/S/Sollich`.

## Ready-to-paste Prompt

> Read and do RP.md in ~/bin/drobox-hydrate-bin-dev. Arbeite evidence-first (old-coder): SPEC-Revision
> anhängen, RED/GREEN, `scripts/gauntlet.sh` grün, EVIDENCE aktualisieren. Neue Binary-Version nach
> den Release-Schritten in CLAUDE.md in Marketplace + lokales Plugin bringen.

## Was Benno entscheiden muss

- SPEC nachträglich absegnen oder korrigieren (TODO 1).
- Ob das Skill das V&S-Preflight-Pattern bekommen soll (TODO 3).
