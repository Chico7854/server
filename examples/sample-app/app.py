"""A tiny app that follows the server's app contract (see README.md).

It only uses Python's standard library, so it needs no dependencies.

- GET <BASE_PATH>/health  -> 200 "ok"
- anything else under <BASE_PATH>/ -> JSON describing the request it received
  (path, headers, environment), which the routing tests check.
"""

import json
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "3000"))
BASE_PATH = os.environ.get("BASE_PATH", "").rstrip("/")
APP_ENV = os.environ.get("APP_ENV", "unknown")


class Handler(BaseHTTPRequestHandler):
    def _reply(self, status, body, content_type):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def _handle(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)

        path = self.path.split("?", 1)[0]
        if path == f"{BASE_PATH}/health":
            return self._reply(200, "ok\n", "text/plain")
        if not path.startswith(f"{BASE_PATH}/"):
            return self._reply(404, "not found\n", "text/plain")

        body = {
            "env": APP_ENV,
            "base_path": BASE_PATH,
            "hostname": socket.gethostname(),
            "method": self.command,
            "path": self.path,
            "headers": {k.lower(): v for k, v in self.headers.items()},
        }
        self._reply(200, json.dumps(body, indent=2) + "\n", "application/json")

    do_GET = do_HEAD = do_POST = do_PUT = do_DELETE = _handle

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    print(f"Listening on :{PORT}, serving {BASE_PATH}/ ({APP_ENV})", flush=True)
    ThreadingHTTPServer(("", PORT), Handler).serve_forever()
