#!/usr/bin/env python3
"""Small OpenCode V2 fixture used by the headless tests."""

import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


PROMPTS = []
COMMAND_RUNS = []
PERMISSION_REPLIES = []
QUESTION_REPLIES = []
SESSIONS = [{"id": "s1", "title": "Fixture", "time": {"updated": 1}}]
COUNTER = [1]
MODELS = [
    {
        "id": "claude-3",
        "providerID": "anthropic",
        "modelID": "claude-3",
        "name": "Claude 3",
        "variants": ["fast", "deep"],
    },
    {
        "id": "gpt-4o",
        "providerID": "openai",
        "modelID": "gpt-4o",
        "name": "GPT-4o",
    },
]
AGENTS = [
    {"name": "build", "description": "Write and edit code"},
    {"name": "plan", "description": "Plan before editing"},
]
COMMANDS = [
    {"name": "review", "description": "Review the working tree", "argumentHint": "[path]"},
    {"name": "test", "description": "Run the test suite"},
]
MESSAGES = {
    "s1": [
        {
            "info": {"id": "m1", "role": "user", "time": {"created": 1}},
            "parts": [{"id": "p1", "type": "text", "text": "fixture question"}],
        }
    ]
}


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

    def read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        try:
            return json.loads(body.decode("utf-8"))
        except ValueError:
            return {}

    def session_id(self, prefix, suffix=""):
        path = self.path.split("?", 1)[0]
        if not path.startswith(prefix):
            return ""
        rest = path[len(prefix):]
        if suffix:
            if not rest.endswith(suffix):
                return ""
            rest = rest[: -len(suffix)]
        return rest.strip("/")

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path.startswith("/api/info"):
            self.send_json(200, {"version": "2.0.0", "healthy": True})
        elif path == "/api/command_runs":
            self.send_json(200, {"data": COMMAND_RUNS})
        elif path == "/api/permission_replies":
            self.send_json(200, {"data": PERMISSION_REPLIES})
        elif path == "/api/question_replies":
            self.send_json(200, {"data": QUESTION_REPLIES})
        elif path == "/api/model":
            self.send_json(200, {"data": MODELS})
        elif path == "/api/provider":
            self.send_json(
                200,
                {
                    "data": [
                        {
                            "id": "anthropic",
                            "name": "Anthropic",
                            "models": [MODELS[0]],
                        },
                        {
                            "id": "openai",
                            "name": "OpenAI",
                            "models": [MODELS[1]],
                        },
                    ]
                },
            )
        elif path == "/api/agent":
            self.send_json(200, {"data": AGENTS})
        elif path == "/api/command":
            self.send_json(200, {"data": COMMANDS})
        elif path.startswith("/api/session/") and path.endswith("/message"):
            session_id = self.session_id("/api/session/", "/message")
            self.send_json(200, {"data": MESSAGES.get(session_id, [])})
        elif path.startswith("/api/session"):
            self.send_json(200, {"data": SESSIONS})
        elif path.startswith("/api/prompts"):
            self.send_json(200, {"data": PROMPTS})
        elif path.startswith("/api/error"):
            self.send_json(400, {"error": "bad request"})
        elif path.startswith("/api/event"):
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
        path = self.path.split("?", 1)[0]
        if path.startswith("/api/session/") and path.endswith("/prompt"):
            payload = self.read_json()
            PROMPTS.append(payload)
            self.send_json(200, {"ok": True})
        elif path.startswith("/api/session/") and path.endswith("/permission/p1/reply"):
            payload = self.read_json()
            payload["requestID"] = "p1"
            PERMISSION_REPLIES.append(payload)
            self.send_json(200, {"ok": True})
        elif path.startswith("/api/session/") and path.endswith("/question/q1/reply"):
            payload = self.read_json()
            payload["requestID"] = "q1"
            QUESTION_REPLIES.append(payload)
            self.send_json(200, {"ok": True})
        elif path.startswith("/api/session/") and path.endswith("/command"):
            payload = self.read_json()
            payload["sessionID"] = self.session_id("/api/session/", "/command")
            COMMAND_RUNS.append(payload)
            self.send_json(200, {"ok": True})
        elif path.startswith("/api/session/") and path.endswith("/fork"):
            session_id = self.session_id("/api/session/", "/fork")
            source = next((s for s in SESSIONS if s["id"] == session_id), None)
            if source is None:
                self.send_json(404, {"error": "not found"})
                return
            COUNTER[0] += 1
            fork = {
                "id": "s" + str(COUNTER[0]),
                "title": source.get("title", "") + " (fork)",
                "parentID": session_id,
                "time": {"updated": COUNTER[0]},
            }
            SESSIONS.insert(0, fork)
            self.send_json(200, {"data": fork})
        elif path.startswith("/api/session/") and path.endswith("/command"):
            self.send_json(200, {"ok": True})
        elif path == "/api/session" or path == "/api/session/":
            payload = self.read_json()
            COUNTER[0] += 1
            session = {
                "id": "s" + str(COUNTER[0]),
                "title": payload.get("title", "New session"),
                "directory": payload.get("directory", ""),
                "time": {"updated": COUNTER[0]},
            }
            SESSIONS.insert(0, session)
            self.send_json(200, {"data": session})
        elif path.startswith("/api/echo"):
            body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_json(404, {"error": "not found"})

    def do_PATCH(self):
        path = self.path.split("?", 1)[0]
        session_id = self.session_id("/api/session/")
        session = next((s for s in SESSIONS if s["id"] == session_id), None)
        if session is None:
            self.send_json(404, {"error": "not found"})
            return
        payload = self.read_json()
        if "title" in payload:
            session["title"] = payload["title"]
        self.send_json(200, {"data": session})

    def do_DELETE(self):
        path = self.path.split("?", 1)[0]
        session_id = self.session_id("/api/session/")
        before = len(SESSIONS)
        SESSIONS[:] = [s for s in SESSIONS if s["id"] != session_id]
        if len(SESSIONS) == before:
            self.send_json(404, {"error": "not found"})
            return
        self.send_json(200, {"ok": True})


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18767
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
