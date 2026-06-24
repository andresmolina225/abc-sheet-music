#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PORT="${PORT:-8080}"

cat <<'USAGE'

  abcjs — local server
  ─────────────────────────────────────────────────────
  Usage:
    ./start-abcjs.sh              Start server on port 8080
    PORT=3000 ./start-abcjs.sh    Use a custom port

  UI (recommended):
    python3 app.py                      ABC editor + live sheet music

  Pages:
    http://localhost:PORT/app.html      ABC Sheet Music UI
    http://localhost:PORT/              Usage guide + sample render
    http://localhost:PORT/abcjs/examples/basic.html
    http://localhost:PORT/abcjs/examples/printable.html
    http://localhost:PORT/abcjs/examples/editor.html

  ABC → sheet music (no LLM, no images):
    ./abc2sheet.py coker.abc -o out/coker.html --open
    cat tune.abc | ./abc2sheet.py -o out/tune.html

  Print:
    Open the usage page and press the Print button, or use
    Cmd+P → Save as PDF for formatted sheet music.

  Press Ctrl+C to stop.
  ─────────────────────────────────────────────────────

USAGE

cd "$ROOT"

if command -v python3 >/dev/null 2>&1; then
  echo "Serving $ROOT on http://localhost:$PORT"
  exec python3 -m http.server "$PORT"
fi

echo "Serving $ROOT on http://localhost:$PORT (npx http-server)"
exec npx --yes http-server -p "$PORT" -c-1