#!/usr/bin/env python3
"""Small OpenCode V2 fixture used by the headless tests."""

import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def send_json(self, code, value):
        body = json.dumps(value).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/api/info"):
            self.send_json(200, {"version": "2.0.0", "healthy": True})
        elif self.path.startswith("/api/error"):
            self.send_json(400, {"error": "bad request"})
        elif self.path.startswith("/api/event"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            events = [
                {"id": "1", "type": "server.connected", "data": {}},
                {
                    "id": "2",
                    "type": "session.status",
                    "data": {"sessionID": "s1", "status": {"type": "idle"}},
                },
            ]
            try:
                for event in events:
                    self.wfile.write(
                        ("data: " + json.dumps(event) + "\n\n").encode("utf-8")
                    )
                    self.wfile.flush()
                    time.sleep(0.05)
                self.wfile.write(b": heartbeat\n\n")
                self.wfile.flush()
                time.sleep(3)
            except (BrokenPipeError, ConnectionResetError):
                pass
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        if self.path.startswith("/api/echo"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_json(404, {"error": "not found"})


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18767
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
