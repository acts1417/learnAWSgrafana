#!/usr/bin/env python3
"""Static file + control server for the idle-shutdown countdown page.

Serves index.html/status.json from the working directory like a plain
static server, plus two POST endpoints so the countdown page's buttons
can act without going through Open WebUI:

  POST /api/shutdown -> stop the instance now
  POST /api/reset     -> mark activity now, pushing the idle deadline
                          back out to a full IDLE_MINUTES (read by
                          idle-shutdown.sh on its next check)

Runs as root (same as idle-shutdown.service) so it can call shutdown
directly, no sudoers setup needed.
"""
import json
import subprocess
import time
from http.server import SimpleHTTPRequestHandler, HTTPServer

PORT = 8081
RESET_FILE = "manual_reset_epoch"


class Handler(SimpleHTTPRequestHandler):
    def do_POST(self):
        if self.path == "/api/shutdown":
            self._respond(200, {"ok": True})
            subprocess.Popen(["shutdown", "-h", "now"])
        elif self.path == "/api/reset":
            with open(RESET_FILE, "w") as f:
                f.write(str(int(time.time())))
            self._respond(200, {"ok": True})
        else:
            self._respond(404, {"ok": False, "error": "not found"})

    def _respond(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
