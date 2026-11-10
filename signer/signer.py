#!/usr/bin/env python3
# ===================================
# Cherri Shortcuts Signer
# v0.0.4 BUILD 2026-11-09 21:04
# Small local web service that signs Shortcuts with macOS's own `shortcuts sign`, using the same JSON-in, signed-bytes-out protocol HubSign used.
# dev by @dastefster 🍒🔨
# ===================================

import ipaddress
import json
import os
import plistlib
import secrets
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


# ===================================
# CONFIG
# ===================================

# Listens on localhost only. The tunnel is the only thing that should reach it from outside.
HOST = "127.0.0.1"
PORT = int(os.environ.get("SIGNER_PORT", "8787"))

# Real shortcuts tested so far were 2 KB to 131 KB, so 2 MB is generous but still stops abuse.
MAX_BODY_BYTES = 2 * 1024 * 1024
MAX_NAME_LENGTH = 120

# Signing asks Apple's servers and takes about 4.5 s. Eight at once worked in testing, so keep a modest cap.
MAX_CONCURRENT_SIGNS = 4
QUEUE_WAIT_SECONDS = 25
SIGN_TIMEOUT_SECONDS = 40

# Per client, per minute. A person tapping Export a few times will never hit this.
RATE_LIMIT_COUNT = 12
RATE_LIMIT_WINDOW = 60

# One shared cap for everybody, so a flood from many different (or faked) addresses still can't hammer the Mac or Apple's signing.
GLOBAL_LIMIT_COUNT = 60
GLOBAL_KEY = "*all*"

# Set SIGNER_DEBUG=1 to log the address headers each request arrives with. Off by default.
DEBUG = os.environ.get("SIGNER_DEBUG") == "1"

SIGNED_MAGIC = b"AEA1"

# Rejected requests are counted and summed up once a minute, so a scanner hammering the URL can't flood the log file.
rejected_count = 0
rejected_reported = time.time()
rejected_lock = threading.Lock()

sign_slots = threading.BoundedSemaphore(MAX_CONCURRENT_SIGNS)
recent_hits = {}
recent_hits_lock = threading.Lock()


# ===================================
# LOGGING
# ===================================

# Never logs shortcut contents or names, only sizes and outcomes, so there is nothing sensitive on disk.
def log(message):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), message, flush=True)


def note_rejected():
    global rejected_count, rejected_reported
    with rejected_lock:
        rejected_count += 1
        if time.time() - rejected_reported >= 60:
            log("403 rejected {} request(s) without the app header in the last minute".format(rejected_count))
            rejected_count = 0
            rejected_reported = time.time()


# ===================================
# RATE LIMITING
# ===================================

def rate_limited(client):
    now = time.time()
    with recent_hits_lock:
        everyone = [t for t in recent_hits.get(GLOBAL_KEY, []) if now - t < RATE_LIMIT_WINDOW]
        if len(everyone) >= GLOBAL_LIMIT_COUNT:
            recent_hits[GLOBAL_KEY] = everyone
            return True

        hits = [t for t in recent_hits.get(client, []) if now - t < RATE_LIMIT_WINDOW]
        if len(hits) >= RATE_LIMIT_COUNT:
            recent_hits[client] = hits
            return True
        hits.append(now)
        recent_hits[client] = hits
        everyone.append(now)
        recent_hits[GLOBAL_KEY] = everyone

        # Keeps the table from growing forever.
        if len(recent_hits) > 5000:
            for key in [k for k, v in recent_hits.items() if not v or now - v[-1] >= RATE_LIMIT_WINDOW]:
                recent_hits.pop(key, None)
    return False


# ===================================
# SIGNING
# ===================================

# Returns signed bytes, or raises RuntimeError with a short plain-text reason.
def sign_plist(xml_bytes):
    if not sign_slots.acquire(timeout=QUEUE_WAIT_SECONDS):
        raise TimeoutError("busy")

    try:
        with tempfile.TemporaryDirectory(prefix="cherri-sign-") as work:
            source = os.path.join(work, "in.shortcut")
            target = os.path.join(work, "out.shortcut")
            with open(source, "wb") as handle:
                handle.write(xml_bytes)

            # One quiet retry, because an occasional single sign failed during parallel testing and then worked.
            last_error = "unknown error"
            for attempt in (1, 2):
                try:
                    run = subprocess.run(
                        ["shortcuts", "sign", "--mode", "anyone", "--input", source, "--output", target],
                        capture_output=True, text=True, timeout=SIGN_TIMEOUT_SECONDS,
                    )
                except subprocess.TimeoutExpired:
                    last_error = "signing timed out"
                    continue

                if run.returncode == 0 and os.path.exists(target):
                    with open(target, "rb") as handle:
                        signed = handle.read()
                    if signed.startswith(SIGNED_MAGIC):
                        return signed
                    last_error = "signer returned an unexpected file"
                else:
                    last_error = (run.stderr or run.stdout or "signing failed").strip().splitlines()[-1][:200]
                    if os.path.exists(target):
                        os.remove(target)

            raise RuntimeError(last_error)
    finally:
        sign_slots.release()


# ===================================
# REQUEST HANDLER
# ===================================

class Handler(BaseHTTPRequestHandler):
    server_version = "CherriSigner/0.0.1"

    # Drops any connection that stalls while sending its request, so slow or silent clients can't pile up threads.
    timeout = 15

    def log_message(self, format, *args):
        # The default logger prints client addresses and paths, so everything goes through log() instead.
        return

    def client_id(self):
        # Anything a visitor sends themselves lands at the START of X-Forwarded-For, and a proxy appends the real
        # address at the END, so only the last entry is trusted. Without the header, everyone shares the socket
        # address, which the global cap keeps safe.
        if DEBUG:
            log("debug headers: " + " | ".join("{}={}".format(k, v) for k, v in self.headers.items() if k.lower() != "content-type"))
        forwarded = [p.strip() for p in (self.headers.get("X-Forwarded-For") or "").split(",") if p.strip()]
        address = forwarded[-1] if forwarded else self.client_address[0]

        # A single IPv6 connection can switch between billions of addresses inside its /64, which would dodge a
        # per-address limit, so IPv6 visitors are grouped by that whole range.
        try:
            if ipaddress.ip_address(address).version == 6:
                return str(ipaddress.ip_network("{}/64".format(address), strict=False))
        except ValueError:
            pass
        return address

    def reply(self, status, body=b"", content_type="text/plain; charset=utf-8", extra=None):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self.reply(200, "ok")
        else:
            self.reply(404, "Not found")

    def do_POST(self):
        started = time.time()
        client = self.client_id()

        if self.path != "/sign":
            self.reply(404, "Not found")
            return

        # The app always identifies itself, so generic scanners and bots are turned away before they cost anything.
        if not (self.headers.get("User-Agent") or "").startswith("CherriApp/"):
            note_rejected()
            self.reply(403, "Not allowed.")
            return

        if rate_limited(client):
            log("429 rate limited")
            self.reply(429, "Too many requests. Wait a minute and try again.", extra={"Retry-After": "30"})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0:
            self.reply(400, "Missing request body.")
            return
        if length > MAX_BODY_BYTES:
            self.reply(413, "Shortcut is too large to sign.")
            return

        try:
            payload = json.loads(self.rfile.read(length))
            name = payload["shortcutName"]
            xml = payload["shortcut"]
            if not isinstance(name, str) or not isinstance(xml, str) or len(name) > MAX_NAME_LENGTH:
                raise ValueError("bad fields")
            xml_bytes = xml.encode("utf-8")

            # A real shortcut is a plist dictionary with an actions list, even when it has zero actions.
            parsed = plistlib.loads(xml_bytes)
            if not isinstance(parsed, dict) or not isinstance(parsed.get("WFWorkflowActions"), list):
                raise ValueError("not a shortcut")
        except Exception:
            log("400 bad request ({} bytes)".format(length))
            self.reply(400, "That does not look like a compiled Shortcut.")
            return

        try:
            signed = sign_plist(xml_bytes)
        except TimeoutError:
            log("503 busy")
            self.reply(503, "Signing is busy right now. Try again in a moment.", extra={"Retry-After": "10"})
            return
        except RuntimeError as error:
            # The tool's own message can name paths or crash details, so it stays in the private log. The person gets a short
            # code instead, which is enough for them to report and for the log to be searched.
            code = secrets.token_hex(3)
            log("502 sign failed [{}]: {}".format(code, error))
            self.reply(502, "Signing failed. Try again, and if it keeps happening send feedback and mention code {}.".format(code))
            return

        log("200 signed {} bytes in, {} bytes out, {:.1f}s".format(len(xml_bytes), len(signed), time.time() - started))
        self.reply(200, signed, content_type="application/octet-stream")


# ===================================
# MAIN
# ===================================

if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    log("Cherri signer listening on http://{}:{}".format(HOST, PORT))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("Stopped")
