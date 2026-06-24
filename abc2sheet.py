#!/usr/bin/env python3
"""Convert ABC notation to printable sheet music (HTML via abcjs).

No LLM or images required — abcjs renders locally in the browser.

Examples:
  ./abc2sheet.py coker.abc -o coker-sheet.html --open
  cat tune.abc | ./abc2sheet.py -o out.html
  ./abc2sheet.py -                    # read ABC from stdin
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import webbrowser
from pathlib import Path

PROJ_ROOT = Path(__file__).resolve().parent
ABCJS_JS = PROJ_ROOT / "abcjs" / "dist" / "abcjs-basic.js"

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title}</title>
  <script src="{abcjs_src}"></script>
  <style>
    * {{ box-sizing: border-box; }}
    body {{
      font-family: system-ui, sans-serif;
      margin: 0;
      padding: 1.25rem 1.5rem 2rem;
      color: #1a1a1a;
      background: #fff;
    }}
    h1 {{
      font-size: 1.2rem;
      font-weight: 600;
      margin: 0 0 1rem;
    }}
    #paper {{
      overflow-x: auto;
    }}
    #warnings {{
      color: #9a3412;
      font-size: 0.85rem;
      white-space: pre-wrap;
      margin-top: 0.75rem;
    }}
    #warnings:empty {{ display: none; }}
    .no-print {{ margin-bottom: 0.75rem; }}
    button {{
      font: inherit;
      padding: 0.35rem 0.75rem;
      border: 1px solid #ddd;
      background: #fff;
      border-radius: 5px;
      cursor: pointer;
    }}
    @media print {{
      .no-print {{ display: none !important; }}
      body {{ padding: 0; }}
      #paper {{ overflow: visible; }}
    }}
  </style>
</head>
<body>
  <header class="no-print">
    <h1>{title}</h1>
    <button type="button" onclick="window.print()">Print / Save PDF</button>
  </header>
  <div id="paper"></div>
  <div id="warnings"></div>
  <script>
    const abc = {abc_json};
    const warningsEl = document.getElementById("warnings");
    const visualObjs = ABCJS.renderAbc("paper", abc, {{
      responsive: "resize",
      oneSvgPerLine: true,
      add_classes: true,
      staffwidth: 740,
      wrap: {{
        preferredMeasuresPerLine: {measures_per_line},
        minSpacing: 1.4,
        maxSpacing: 2.4
      }}
    }});
    const warnings = [];
    visualObjs.forEach((obj, i) => {{
      (obj.warnings || []).forEach((w) => {{
        warnings.push(`Tune ${{i + 1}}: ${{w.message}}`);
      }});
    }});
    if (warnings.length) warningsEl.textContent = warnings.join("\\n");
  </script>
</body>
</html>
"""


def read_abc(source: str | None) -> str:
    if source is None or source == "-":
        data = sys.stdin.read()
    else:
        data = Path(source).read_text(encoding="utf-8")
    data = data.strip()
    if not data:
        raise SystemExit("No ABC input (empty file or stdin).")
    return data


def parse_title(abc: str, override: str | None) -> str:
    if override:
        return override
    for line in abc.splitlines():
        if line.startswith("T:"):
            return line[2:].strip() or "Sheet Music"
    return "Sheet Music"


def abcjs_src_for(output: Path) -> str:
    if not ABCJS_JS.is_file():
        raise SystemExit(f"Missing abcjs build at {ABCJS_JS}")
    rel = os.path.relpath(ABCJS_JS, output.parent)
    return rel.replace(os.sep, "/")


def render_html(
    abc: str,
    *,
    title: str,
    output: Path,
    measures_per_line: int,
) -> None:
    html = HTML_TEMPLATE.format(
        title=title,
        abcjs_src=abcjs_src_for(output),
        abc_json=json.dumps(abc),
        measures_per_line=measures_per_line,
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(html, encoding="utf-8")


def default_output_path(input_path: str | None) -> Path:
    if input_path and input_path != "-":
        stem = Path(input_path).stem
        return PROJ_ROOT / "out" / f"{stem}.html"
    return PROJ_ROOT / "out" / "sheet.html"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert ABC notation to printable sheet music (HTML)."
    )
    parser.add_argument(
        "input",
        nargs="?",
        help="ABC file path, or '-' for stdin (default: stdin if piped)",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Output HTML path (default: proj/out/<name>.html)",
    )
    parser.add_argument("--title", help="Override page title")
    parser.add_argument(
        "--measures-per-line",
        type=int,
        default=1,
        metavar="N",
        help="Wrap layout: measures per staff line (default: 1)",
    )
    parser.add_argument(
        "--open",
        action="store_true",
        help="Open the generated HTML in the default browser",
    )
    args = parser.parse_args()

    source = args.input
    if source is None and not sys.stdin.isatty():
        source = "-"
    elif source is None:
        parser.error("Provide an ABC file, '-' for stdin, or pipe ABC on stdin.")

    abc = read_abc(source)
    title = parse_title(abc, args.title)
    output = args.output or default_output_path(source)

    render_html(
        abc,
        title=title,
        output=output.resolve(),
        measures_per_line=args.measures_per_line,
    )

    print(output.resolve())
    if args.open:
        webbrowser.open(output.resolve().as_uri())


if __name__ == "__main__":
    main()