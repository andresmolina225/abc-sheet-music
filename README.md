# ABC Sheet Music

Local web app for Jerry Coker-style practice patterns. Converts ABC notation to sheet music using a vendored [abcjs](https://github.com/paulrosen/abcjs) build — no LLM, no CDN.

## Quick start

```bash
git clone <your-repo-url>
cd abc-sheet-music   # or proj
python3 app.py
```

Opens **http://127.0.0.1:8080/app.html** in your browser.

## Features

- ABC editor with live preview
- **Gen Coker** — full chromatic cycle with per-measure key signatures
- Instrument transposition: Tenor Sax (Bb), Alto Sax (Eb), Bb Clarinet/Trumpet, Concert
- Playback via abcjs synth (concert pitch)
- Save/load `.abc`, export HTML, print/PDF

## Other commands

```bash
# CLI: ABC file → printable HTML
python3 abc2sheet.py coker.abc -o out/coker.html --open

# Simple HTTP server (no auto-open)
./start-abcjs.sh
```

## Project layout

| File | Purpose |
|------|---------|
| `app.html` | Main UI |
| `app.py` | Local server launcher |
| `abc2sheet.py` | Headless ABC → HTML converter |
| `coker.abc` | One-bar concert template |
| `abcjs/` | Local abcjs library (from paulrosen/abcjs) |

## Requirements

- Python 3.9+
- Modern browser with Web Audio support (for Play)

## License

App code: yours to use. `abcjs/` is MIT — see `abcjs/LICENSE.md`.