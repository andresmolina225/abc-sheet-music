#!/usr/bin/env python3
"""Launch the ABC Sheet Music web UI.

Usage:
    python3 app.py              # start server + open browser
    python3 app.py --port 3000  # custom port
    python3 app.py --no-open    # server only
"""

from __future__ import annotations

import argparse
import http.server
import os
import socket
import socketserver
import sys
import threading
import webbrowser
from pathlib import Path

PROJ_ROOT = Path(__file__).resolve().parent


def find_free_port(start: int, host: str = "127.0.0.1") -> int:
    for port in range(start, start + 50):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            try:
                sock.bind((host, port))
                return port
            except OSError:
                continue
    raise SystemExit(f"No free port found near {start}")


def main() -> None:
    parser = argparse.ArgumentParser(description="ABC Sheet Music UI")
    parser.add_argument("--port", type=int, default=8080, help="Preferred port (default: 8080)")
    parser.add_argument("--host", default="127.0.0.1", help="Bind address (default: 127.0.0.1)")
    parser.add_argument("--no-open", action="store_true", help="Do not open the browser")
    args = parser.parse_args()

    port = find_free_port(args.port, args.host)
    url = f"http://{args.host}:{port}/app.html"

    handler = http.server.SimpleHTTPRequestHandler
    handler.extensions_map.update({".abc": "text/plain", ".html": "text/html"})

    class QuietHandler(handler):
        def log_message(self, fmt: str, *log_args: object) -> None:
            if log_args and str(log_args[1]).startswith("4"):
                super().log_message(fmt, *log_args)

    os.chdir(PROJ_ROOT)

    with socketserver.TCPServer((args.host, port), QuietHandler) as httpd:
        if port != args.port:
            print(f"Port {args.port} busy — using {port}", file=sys.stderr)
        print(f"\n  ABC Sheet Music UI")
        print(f"  ─────────────────────────────────")
        print(f"  {url}")
        print(f"  Press Ctrl+C to stop.\n")

        if not args.no_open:
            threading.Timer(0.4, lambda: webbrowser.open(url)).start()

        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped.")


if __name__ == "__main__":
    main()