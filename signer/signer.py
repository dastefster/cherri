#!/usr/bin/env python3
# ===================================
# Cherri Shortcuts Signer
# v0.0.5 BUILD 2026-11-09 21:32
# Small local web service that signs Shortcuts with macOS's own `shortcuts sign`, using the same JSON-in, signed-bytes-out protocol HubSign used. App Attest is wired in log-only: requests are checked and the result is logged, but nothing is refused for lacking it yet.
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

# Attestation is optional while it is rolled out, so a missing library or a broken database must never stop signing.
try:
    import attest
except Exception as import_error:
    attest = None
    ATTEST_IMPORT_ERROR = "{}: {}".format(type(import_error).__name__, import_error)


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

# Each kind of request counts against its own limits, so asking for challenges can never use up the signing allowance. Registering a device is the costly one (it parses certificates), so it is the tightest.
# Pairs are (per client, everybody) per minute.
LIMITS = {
    "sign": (RATE_LIMIT_COUNT, GLOBAL_LIMIT_COUNT),
    "challenge": (30, 300),
    "attest": (6, 60),
}

MAX_ATTEST_BODY_BYTES = 64 * 1024

# Set SIGNER_DEBUG=1 to log the address headers each request arrives with. Off by default.
DEBUG = os.environ.get("SIGNER_DEBUG") == "1"

SIGNED_MAGIC = b"AEA1"

# Rejected requests are counted and summed up once a minute, so a scanner hammering the URL can't flood the log file.
rejected_count = 0
rejected_reported = time.time()
rejected_lock = threading.Lock()

# Set up at startup. None means attestation is off, and requests are handled exactly as before.
attest_store = None

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

def rate_limited(client, scope="sign"):
    per_client, per_everyone = LIMITS[scope]
    client_key = "{}:{}".format(scope, client)
    global_key = "{}:{}".format(scope, GLOBAL_KEY)
    now = time.time()
    with recent_hits_lock:
        everyone = [t for t in recent_hits.get(global_key, []) if now - t < RATE_LIMIT_WINDOW]
        if len(everyone) >= per_everyone:
            recent_hits[global_key] = everyone
            return True

        hits = [t for t in recent_hits.get(client_key, []) if now - t < RATE_LIMIT_WINDOW]
        if len(hits) >= per_client:
            recent_hits[client_key] = hits
            return True
        hits.append(now)
        recent_hits[client_key] = hits
        everyone.append(now)
        recent_hits[global_key] = everyone

        # Keeps the table from growing forever.
        if len(recent_hits) > 5000:
            for key in [k for k, v in recent_hits.items() if not v or now - v[-1] >= RATE_LIMIT_WINDOW]:
                recent_hits.pop(key, None)
    return False


# ===================================
# APP ATTEST SETUP
# ===================================

def start_attestation():
    global attest_store
    if attest is None:
        log("App Attest is off: {}".format(ATTEST_IMPORT_ERROR))
        return
    try:
        attest_store = attest.AttestStore()
        log("App Attest is on (log only), {} registered device(s)".format(attest_store.count_keys()))
    except Exception as error:
        attest_store = None
        log("App Attest is off: {}: {}".format(type(error).__name__, error))


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

    # The app always identifies itself, so generic scanners and bots are turned away before they cost anything.
    def from_app(self):
        if (self.headers.get("User-Agent") or "").startswith("CherriApp/"):
            return True
        note_rejected()
        self.reply(403, "Not allowed.")
        return False

    def do_GET(self):
        if self.path == "/health":
            self.reply(200, "ok")
        elif self.path == "/challenge":
            self.handle_challenge()
        else:
            self.reply(404, "Not found")

    # Hands out a one-time challenge for the app to sign. A 503 tells a newer app that attestation isn't available, and it carries on without.
    def handle_challenge(self):
        client = self.client_id()
        if not self.from_app():
            return
        if attest_store is None:
            self.reply(503, "Not available.")
            return
        if rate_limited(client, "challenge"):
            self.reply(429, "Too many requests. Wait a minute and try again.", extra={"Retry-After": "30"})
            return
        try:
            challenge = attest_store.new_challenge()
        except attest.AttestError:
            self.reply(503, "Busy right now. Try again in a moment.", extra={"Retry-After": "10"})
            return
        self.reply(200, json.dumps({"challenge": challenge}), content_type="application/json")

    # Registers a device from its attestation. The reason a check failed goes to the log only.
    def handle_attest(self):
        client = self.client_id()
        if not self.from_app():
            return
        if attest_store is None:
            self.reply(503, "Not available.")
            return
        if rate_limited(client, "attest"):
            log("429 attest rate limited")
            self.reply(429, "Too many requests. Wait a minute and try again.", extra={"Retry-After": "30"})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_ATTEST_BODY_BYTES:
            self.reply(400, "Attestation failed.")
            return

        try:
            payload = json.loads(self.rfile.read(length))
            environment = attest_store.register(payload["keyId"], payload["attestation"], payload["challenge"])
        except attest.AttestError as error:
            log("400 attest failed [{}] {}".format(error.code, error.detail[:160]))
            if error.code == "busy":
                self.reply(503, "Busy right now. Try again in a moment.", extra={"Retry-After": "10"})
            else:
                self.reply(400, "Attestation failed.")
            return
        except Exception:
            log("400 attest bad request")
            self.reply(400, "Attestation failed.")
            return

        log("200 registered a {} device, {} known".format(environment, attest_store.count_keys()))
        self.reply(200, json.dumps({"ok": True}), content_type="application/json")

    # Log-only for now: says whether the request proved it came from the real app, and never refuses anything.
    def attestation_result(self, raw_body):
        key = self.headers.get("X-Attest-Key")
        assertion = self.headers.get("X-Attest-Assertion")
        challenge = self.headers.get("X-Attest-Challenge")
        if not (key and assertion and challenge):
            return "unattested"
        if attest_store is None:
            return "unattested (attestation off)"
        try:
            key_id, counter = attest_store.check_assertion(key, assertion, challenge, raw_body)
        except attest.AttestError as error:
            return "attest failed [{}]".format(error.code)
        except Exception as error:
            return "attest error [{}]".format(type(error).__name__)
        return "attested {} #{}".format(key_id.hex()[:8], counter)

    def do_POST(self):
        started = time.time()
        client = self.client_id()

        if self.path == "/attest":
            self.handle_attest()
            return

        if self.path != "/sign":
            self.reply(404, "Not found")
            return

        if not self.from_app():
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
            raw_body = self.rfile.read(length)
            payload = json.loads(raw_body)
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

        proof = self.attestation_result(raw_body)

        try:
            signed = sign_plist(xml_bytes)
        except TimeoutError:
            log("503 busy ({})".format(proof))
            self.reply(503, "Signing is busy right now. Try again in a moment.", extra={"Retry-After": "10"})
            return
        except RuntimeError as error:
            # The tool's own message can name paths or crash details, so it stays in the private log. The person gets a short
            # code instead, which is enough for them to report and for the log to be searched.
            code = secrets.token_hex(3)
            log("502 sign failed [{}] ({}): {}".format(code, proof, error))
            self.reply(502, "Signing failed. Try again, and if it keeps happening send feedback and mention code {}.".format(code))
            return

        log("200 signed {} bytes in, {} bytes out, {:.1f}s, {}".format(len(xml_bytes), len(signed), time.time() - started, proof))
        self.reply(200, signed, content_type="application/octet-stream")


# ===================================
# MAIN
# ===================================

if __name__ == "__main__":
    start_attestation()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    log("Cherri signer listening on http://{}:{}".format(HOST, PORT))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("Stopped")
