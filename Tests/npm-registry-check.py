#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Offline real-npm integration: no changes to the user's global packages."""
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def package(version):
    content = json.dumps({"name": "onetool-fixture", "version": version}).encode()
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
        entry = tarfile.TarInfo("package/package.json")
        entry.size = len(content)
        archive.addfile(entry, io.BytesIO(content))
    return buffer.getvalue()


tarballs = {v: package(v) for v in ["1.0.0", "2.0.0"]}
latest = "1.0.0"


class Registry(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        global latest
        path = self.path.split("?", 1)[0]
        if path == "/advance":
            latest = "2.0.0"
            payload = b"ok"
        elif path == "/onetool-fixture":
            origin = "http://127.0.0.1:" + str(self.server.server_port)
            versions = {v: {"name": "onetool-fixture", "version": v,
                            "dist": {"tarball": origin + "/tarball/" + v,
                                     "shasum": hashlib.sha1(tarballs[v]).hexdigest()}}
                        for v in tarballs}
            payload = json.dumps({"name": "onetool-fixture", "dist-tags": {"latest": latest},
                                  "versions": versions}).encode()
        elif path.startswith("/tarball/") and path.rsplit("/", 1)[-1] in tarballs:
            payload = tarballs[path.rsplit("/", 1)[-1]]
        else:
            self.send_error(404, "Fixture package not found")
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream" if path.startswith("/tarball/") else "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)


def main():
    npm = shutil.which("npm")
    if not npm:
        sys.exit("NOT RUN: npm must be installed for --packages-integration")
    server = ThreadingHTTPServer(("127.0.0.1", 0), Registry)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        with tempfile.TemporaryDirectory(prefix="onetool-npm-check-") as root:
            # Arborist in npm 11 treats a /var → /private/var root as a Link;
            # npm outdated then skips its children. Use the canonical temp path.
            root = str(Path(root).resolve())
            env = os.environ.copy()
            env.update({"ONETOOL_TEST_NPM": npm, "npm_config_prefix": str(Path(root) / "prefix"),
                        "npm_config_cache": str(Path(root) / "cache"),
                        "npm_config_userconfig": str(Path(root) / "npmrc"),
                        "npm_config_globalconfig": str(Path(root) / "global-npmrc"),
                        "npm_config_registry": "http://127.0.0.1:" + str(server.server_port),
                        "npm_config_audit": "false", "npm_config_fund": "false",
                        "npm_config_update_notifier": "false", "npm_config_fetch_retries": "0"})
            result = subprocess.run([sys.argv[1]], env=env, timeout=120)
            return result.returncode
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    sys.exit(main())
