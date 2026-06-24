# ABC Sheet Music (Swift)

Native **macOS SwiftUI** app for Jerry Coker ABC practice patterns.

## Architecture

| Layer | Technology |
|-------|------------|
| UI, editor, file I/O, Coker logic | **Swift / SwiftUI** |
| Engraving, transposition, playback | **abcjs** (bundled, via thin `WKWebView` bridge) |

The WebView is only used for music rendering and `ABCJS.strTranspose` — not as the main app shell. This keeps expansion path clear: more features in Swift, notation stays in abcjs until you swap in a native renderer later.

## Requirements

- macOS 13+
- Swift 5.9+ (Xcode 15+ recommended)

## Run

```bash
cd ABCSheetMusic
swift run
```

Or open `Package.swift` in Xcode → Run.

## Project layout

```
Sources/ABCSheetMusic/
  ABCSheetMusicApp.swift    App entry
  AppState.swift            Observable app state
  Models/
    Instrument.swift        Transposition intervals
    ConcertBar.swift        13 hand-crafted Coker bars
  Services/
    ABCBridge.swift         WKWebView ↔ abcjs bridge
    CokerGenerator.swift    Chromatic cycle builder
    ABCUtilities.swift      ABC string helpers
  Views/
    ContentView.swift       Toolbar + split editor/score
    ScoreWebView.swift      WKWebView wrapper
  Resources/
    Bridge/                 Minimal HTML + abc-bridge.js
    abcjs/                  Vendored abcjs-basic.js + CSS
    coker.abc               Concert reference
```

## Features

- Gen Coker — full chromatic cycle with per-measure `[K:…]` key signatures
- Instruments: Tenor (+14 maj 9th), Alto (+9 maj 6th), Bb (+2 maj 2nd), Concert
- Live render, Play (concert-pitch synth), open/save `.abc`
- 4/4 rhythm fix: no mid-bar `|` before half notes

## Legacy web app

The original `app.html` / `app.py` UI remains in the repo root for browser use.