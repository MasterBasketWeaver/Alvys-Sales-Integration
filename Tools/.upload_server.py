#!/usr/bin/env python3
import http.server
import os
import re
import socketserver

UPLOAD_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # project root, above tools/
PORT = 9877

FORM = b"""<!doctype html>
<html><body style="font-family:sans-serif;max-width:480px;margin:40px auto">
<h2>Upload file</h2>
<form method="POST" enctype="multipart/form-data">
<input type="file" name="file"><br><br>
<input type="submit" value="Upload">
</form>
</body></html>"""


def safe_filename(name):
    name = os.path.basename(name)
    name = re.sub(r"[^A-Za-z0-9._-]", "_", name)
    return name or "upload.bin"


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(FORM)

    def do_POST(self):
        content_type = self.headers.get("Content-Type", "")
        m = re.search(r"boundary=(.+)", content_type)
        if "multipart/form-data" not in content_type or not m:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"Expected multipart/form-data")
            return

        boundary = m.group(1).strip('"').encode()
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)

        parts = body.split(b"--" + boundary)
        saved = []
        for part in parts:
            part = part.strip(b"\r\n")
            if not part or part == b"--":
                continue
            header_blob, _, data = part.partition(b"\r\n\r\n")
            headers = header_blob.decode(errors="replace")
            fname_match = re.search(r'filename="([^"]*)"', headers)
            if not fname_match or not fname_match.group(1):
                continue
            filename = safe_filename(fname_match.group(1))
            data = data.rstrip(b"\r\n") if data.endswith(b"\r\n") else data
            # strip trailing boundary marker remnants
            if data.endswith(b"--"):
                data = data[:-2].rstrip(b"\r\n")
            dest = os.path.join(UPLOAD_DIR, filename)
            with open(dest, "wb") as f:
                f.write(data)
            saved.append(filename)
            print(f"Saved: {dest} ({len(data)} bytes)")

        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        if saved:
            msg = "Uploaded: " + ", ".join(saved)
        else:
            msg = "No file received"
        self.wfile.write(f"<html><body><p>{msg}</p><a href=\"/\">Upload another</a></body></html>".encode())


if __name__ == "__main__":
    os.chdir(UPLOAD_DIR)
    with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
        print(f"Serving on 0.0.0.0:{PORT}, saving files to {UPLOAD_DIR}")
        httpd.serve_forever()
