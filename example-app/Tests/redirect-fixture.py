"""Loopback-only regression fixture; never contacts a tenant endpoint."""
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

hits = 0

class Target(BaseHTTPRequestHandler):
    def do_POST(self):
        global hits
        hits += 1
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{}')
    def log_message(self, *args):
        pass

class Origin(BaseHTTPRequestHandler):
    def do_POST(self):
        self.send_response(302)
        self.send_header('Location', f'http://127.0.0.1:{target.server_port}/alternate')
        self.end_headers()
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({'targetHits': hits}).encode())
    def log_message(self, *args):
        pass

target = ThreadingHTTPServer(('127.0.0.1', 0), Target)
origin = ThreadingHTTPServer(('127.0.0.1', 0), Origin)
threading.Thread(target=target.serve_forever, daemon=True).start()
print(json.dumps({'origin': origin.server_port}), flush=True)
origin.serve_forever()
