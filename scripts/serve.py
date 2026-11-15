#!/usr/bin/env python3
# De Als-Dan webapp op http://localhost:8321, vanuit de map web/ (start.command roept dit aan).
import http.server as h


class Handler(h.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')   # anders houdt Chrome na een wijziging de oude scripts vast
        super().end_headers()


h.ThreadingHTTPServer(('127.0.0.1', 8321), Handler).serve_forever()
