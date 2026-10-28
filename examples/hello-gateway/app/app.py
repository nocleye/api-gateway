import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


class Echo(BaseHTTPRequestHandler):
    def handle_any(self):
        url = urlsplit(self.path)
        length = int(self.headers.get("Content-Length") or 0)
        body = {
            "method": self.command,
            "path": url.path,
            "query": url.query,
            "headers": {k: v for k, v in self.headers.items()},
            "body": self.rfile.read(length).decode(errors="replace"),
        }
        payload = json.dumps(body, indent=2).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = handle_any


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8000), Echo).serve_forever()
