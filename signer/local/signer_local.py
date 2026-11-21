#!/usr/bin/env python3
# ===================================
# Cherri Local Signer (prototype)
# v0.0.2 BUILD 2026-11-21 04:00
# Signs Shortcuts on the user's own Mac for the Cherri Shortcuts app over the local network, so nothing goes through the developer's server. Same JSON-in, signed-bytes-out protocol as signer.py, guarded by a pairing code and announced over Bonjour.
# dev by @dastefster 🍒🔨
# ===================================

import atexit
import hmac
import json
import os
import plistlib
import secrets
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


# ===================================
# CONFIG
# ===================================

VERSION = "0.0.2"

# Listens on every network interface so the phone can reach it. Set SIGNER_LOCAL_HOST=127.0.0.1 to test from this Mac only.
HOST = os.environ.get("SIGNER_LOCAL_HOST", "0.0.0.0")
PORT = int(os.environ.get("SIGNER_LOCAL_PORT", "8788"))

# The app looks for this Bonjour service type to find the Mac without anyone typing an address.
SERVICE_TYPE = "_cherri-signer._tcp"

MAX_BODY_BYTES = 2 * 1024 * 1024
MAX_NAME_LENGTH = 120
MAX_CONCURRENT_SIGNS = 2
QUEUE_WAIT_SECONDS = 25
SIGN_TIMEOUT_SECONDS = 40

# A wrong pairing code can be guessed at, so too many misses in a minute shuts the door until the minute is up.
BAD_CODE_LIMIT = 10
BAD_CODE_WINDOW = 60

# Skips look-alike characters (0/O, 1/I) because the code gets typed on a phone.
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 10
STATE_DIR = os.path.expanduser("~/.cherri-local-signer")

SIGNED_MAGIC = b"AEA1"

sign_slots = threading.BoundedSemaphore(MAX_CONCURRENT_SIGNS)
bad_code_times = []
bad_code_lock = threading.Lock()
bonjour_process = None


# ===================================
# LOGGING
# ===================================

# Only sizes and outcomes are logged, never shortcut contents, names or addresses.
def log(message):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), message, flush=True)


# ===================================
# PAIRING CODE
# ===================================

# The code is made once and kept, so the phone only has to be paired one time.
def load_or_create_code():
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    path = os.path.join(STATE_DIR, "pairing-code")
    if os.path.exists(path):
        with open(path, "r") as handle:
            code = handle.read().strip()
        if len(code) == CODE_LENGTH:
            return code

    code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as handle:
        handle.write(code + "\n")
    return code


def too_many_bad_codes():
    now = time.time()
    with bad_code_lock:
        bad_code_times[:] = [t for t in bad_code_times if now - t < BAD_CODE_WINDOW]
        return len(bad_code_times) >= BAD_CODE_LIMIT


def note_bad_code():
    with bad_code_lock:
        bad_code_times.append(time.time())


# ===================================
# BONJOUR
# ===================================

# macOS's own dns-sd tool does the announcing, so there is no Bonjour code to maintain. It keeps running until this script stops.
def start_bonjour():
    global bonjour_process
    host_name = socket.gethostname().split(".")[0]
    try:
        bonjour_process = subprocess.Popen(
            ["dns-sd", "-R", "Cherri Signer ({})".format(host_name), SERVICE_TYPE, "local", str(PORT), "v=" + VERSION],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        atexit.register(stop_bonjour)
        log("Announcing over Bonjour as {}".format(SERVICE_TYPE))
    except Exception as error:
        log("Bonjour is off: {}: {}".format(type(error).__name__, error))


def stop_bonjour():
    if bonjour_process is not None and bonjour_process.poll() is None:
        bonjour_process.terminate()


# ===================================
# SIGNING
# ===================================

# Returns signed bytes, or raises RuntimeError with a short plain-text reason.
def sign_plist(xml_bytes):
    if not sign_slots.acquire(timeout=QUEUE_WAIT_SECONDS):
        raise TimeoutError("busy")

    try:
        with tempfile.TemporaryDirectory(prefix="cherri-local-sign-") as work:
            source = os.path.join(work, "in.shortcut")
            target = os.path.join(work, "out.shortcut")
            with open(source, "wb") as handle:
                handle.write(xml_bytes)

            # One quiet retry, because an occasional single sign failed during testing and then worked.
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
    server_version = "CherriLocalSigner/" + VERSION

    # Drops any connection that stalls while sending its request.
    timeout = 15

    def log_message(self, format, *args):
        # The default logger prints client addresses, so everything goes through log() instead.
        return

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

    # The app can ask who is answering before it pairs. Nothing private is in the answer, so it needs no code.
    def do_GET(self):
        if self.path == "/health":
            self.reply(200, json.dumps({"ok": True, "name": "Cherri Local Signer", "version": VERSION}), content_type="application/json")
        elif self.path == "/pair":
            # Lets the app check a typed pairing code before anyone tries to sign.
            if self.code_is_valid():
                self.reply(200, json.dumps({"ok": True}), content_type="application/json")
        else:
            self.reply(404, "Not found")

    def code_is_valid(self):
        if too_many_bad_codes():
            log("429 too many wrong pairing codes")
            self.reply(429, "Too many wrong pairing codes. Wait a minute and try again.", extra={"Retry-After": "60"})
            return False

        sent = self.headers.get("X-Cherri-Pair") or ""
        if hmac.compare_digest(sent.encode("utf-8"), pairing_code.encode("utf-8")):
            return True

        note_bad_code()
        log("401 wrong pairing code")
        self.reply(401, "Pairing code not recognized. Pair the app with this Mac again.")
        return False

    def do_POST(self):
        started = time.time()

        if self.path != "/sign":
            self.reply(404, "Not found")
            return

        if not (self.headers.get("User-Agent") or "").startswith("CherriApp/"):
            self.reply(403, "Not allowed.")
            return

        if not self.code_is_valid():
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
            code = secrets.token_hex(3)
            log("502 sign failed [{}]: {}".format(code, error))
            self.reply(502, "Signing failed on this Mac (code {}). Make sure it is signed in to iCloud and online.".format(code))
            return

        log("200 signed {} bytes in, {} bytes out, {:.1f}s".format(len(xml_bytes), len(signed), time.time() - started))
        self.reply(200, signed, content_type="application/octet-stream")


# ===================================
# MAIN
# ===================================

pairing_code = load_or_create_code()


def shut_down(*_):
    stop_bonjour()
    sys.exit(0)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, shut_down)
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    log("Cherri local signer {} listening on {}:{}".format(VERSION, HOST, PORT))
    log("Pairing code: {}".format(pairing_code))
    if HOST != "127.0.0.1":
        start_bonjour()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("Stopped")
