#!/usr/bin/env python3

import json
import os
import re
import subprocess
import tempfile
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent
RESULTS = ROOT / "Results"
ALLOWED_MODES = {"raw", "agent", "clean", "email", "article"}
ALLOWED_ORIGINS = {
    "http://127.0.0.1:4173",
    "http://localhost:4173",
}
WRITING_MODEL = (
    Path.home()
    / "Library/Application Support/is.ian.dictation/Models/writing/models/mlx-community/Qwen3.5-9B-MLX-4bit"
)


class CorpusHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/api/health":
            return self.send_json({"ok": True})
        if path == "/api/status":
            required = ["config.json", "tokenizer.json", "model.safetensors.index.json"]
            writing_installed = (
                all((WRITING_MODEL / name).exists() for name in required)
                and any(WRITING_MODEL.glob("*.safetensors"))
            )
            return self.send_json({"writingInstalled": writing_installed})
        if path == "/api/clipboard":
            completed = subprocess.run(
                ["/usr/bin/pbpaste"],
                check=False,
                capture_output=True,
                text=True,
                timeout=2,
            )
            return self.send_json({"text": completed.stdout})
        if path in {"/regression", "/delivery", "/repair"}:
            self.path = "/index.html"
        return super().do_GET()

    def do_POST(self):
        if not self.request_is_local():
            return self.send_json({"error": "origin not allowed"}, status=403)

        path = urlparse(self.path).path
        try:
            payload = self.read_json()
            if path == "/api/mode":
                return self.select_mode(payload)
            if path == "/api/results":
                return self.save_results(payload)
            return self.send_json({"error": "not found"}, status=404)
        except (ValueError, json.JSONDecodeError) as error:
            return self.send_json({"error": str(error)}, status=400)

    def request_is_local(self):
        origin = self.headers.get("Origin")
        return origin is None or origin in ALLOWED_ORIGINS

    def read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 10_000_000:
            raise ValueError("invalid body size")
        return json.loads(self.rfile.read(length))

    def select_mode(self, payload):
        mode = str(payload.get("mode", "")).lower()
        if mode not in ALLOWED_MODES:
            raise ValueError("unknown mode")
        subprocess.run(
            ["/usr/bin/open", "-g", f"ian-dictation://mode/{mode}"],
            check=True,
            timeout=5,
        )
        return self.send_json({"ok": True, "mode": mode})

    def save_results(self, payload):
        run_id = str(payload.get("runId", ""))
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", run_id):
            raise ValueError("invalid run id")
        if not isinstance(payload.get("results"), dict):
            raise ValueError("results must be an object")

        RESULTS.mkdir(parents=True, exist_ok=True)
        encoded = json.dumps(payload, indent=2, ensure_ascii=False).encode("utf-8") + b"\n"
        self.atomic_write(RESULTS / f"{run_id}.json", encoded)
        self.atomic_write(RESULTS / "latest.json", encoded)
        return self.send_json({"ok": True, "path": f"ProductCorpus/Results/{run_id}.json"})

    @staticmethod
    def atomic_write(destination, data):
        descriptor, temporary = tempfile.mkstemp(prefix=".result-", dir=RESULTS)
        try:
            with os.fdopen(descriptor, "wb") as handle:
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, destination)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)

    def send_json(self, payload, status=200):
        encoded = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


if __name__ == "__main__":
    RESULTS.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer(("127.0.0.1", 4173), CorpusHandler)
    print("Dictation corpus: http://127.0.0.1:4173", flush=True)
    print(f"Results: {RESULTS / 'latest.json'}", flush=True)
    server.serve_forever()
