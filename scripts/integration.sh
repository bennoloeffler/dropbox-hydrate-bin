#!/bin/bash
# Real execution against the running Dropbox app (S15, N2, N3).
#   scripts/integration.sh [BINARY] [FOLDER]
# Downloads up to 3 real placeholders from FOLDER (they stay downloaded afterwards).
# Checks: negative control (plain read leaves a placeholder at 0 bytes), the binary makes
# them non-empty with exit 0, no new GUI app appears, Dropbox logs no "Opening document".
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="${1:-.build/debug/dropbox-hydrate-bin}"
DIR="${2:-${HYDRATE_IT_DIR:-$HOME/VundS Dropbox/VundS/C_Klienten/S}}"
N=3
[ -x "$BIN" ] || { echo "integration: binary not found: $BIN" >&2; exit 1; }
[ -d "$DIR" ] || { echo "integration: folder not found: $DIR" >&2; exit 1; }
pgrep -xq Dropbox || { echo "integration: Dropbox app is not running" >&2; exit 1; }

FILES=()
while IFS= read -r -d '' f; do
    case "$(basename "$f")" in .* | '~$'*) continue ;; esac
    FILES+=("$f")
    [ "${#FILES[@]}" -ge "$N" ] && break
done < <(/usr/bin/find "$DIR" -type f -size 0 -not -path '*/.*' -print0)
[ "${#FILES[@]}" -ge 1 ] || { echo "integration: no placeholders left in $DIR — pass another FOLDER" >&2; exit 1; }
size() { /usr/bin/stat -f %z "$1"; }

# N3 negative control: a plain read must NOT download (else this test proves nothing).
head -c 16 "${FILES[0]}" >/dev/null
sleep 3
[ "$(size "${FILES[0]}")" = 0 ] || { echo "integration: plain read downloaded — control failed" >&2; exit 1; }
echo "control: plain read left it at 0 bytes"

apps() { lsappinfo list | grep -oE 'bundleID="[^"]+"' | sort -u; }
BEFORE_APPS=$(apps)
START=$(date "+%Y-%m-%d %H:%M:%S")

rc=0
"$BIN" --timeout 60 "${FILES[@]}" || rc=$?

for f in "${FILES[@]}"; do
    s=$(size "$f")
    echo "  $s bytes  $(basename "$f")"
    [ "$s" -gt 0 ] || { echo "integration: still empty: $f" >&2; exit 1; }
done
[ "$rc" = 0 ] || { echo "integration: exit $rc" >&2; exit 1; }

sleep 2
NEW_APPS=$(comm -13 <(echo "$BEFORE_APPS") <(apps))
[ -z "$NEW_APPS" ] || { echo "integration: new app(s) appeared: $NEW_APPS" >&2; exit 1; }
OPENED=$(/usr/bin/log show --start "$START" --style compact \
    --predicate 'process == "Dropbox" AND eventMessage CONTAINS "Opening document"' | grep -c "Opening document" || true)
[ "$OPENED" = 0 ] || { echo "integration: Dropbox handed $OPENED document(s) to an app" >&2; exit 1; }
echo "integration: ${#FILES[@]}/${#FILES[@]} downloaded, no app started, no document handed on"
