#!/usr/bin/env python3
# ===================================
# Cherri Shortcuts Signer: Server Tests
# v0.0.1 BUILD 2026-11-09 21:32
# Starts the real server on a spare port and runs the whole App Attest flow against it with a fake device, signing with the real `shortcuts sign`, so it only runs on a Mac. Run with: .venv/bin/python -m unittest test_signer -v
# dev by @dastefster 🍒🔨
# ===================================

import base64
import http.client
import json
import os
import plistlib
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer

import attest
import signer
import test_attest as fake
from attest import AttestStore

APP_HEADER = {"User-Agent": "CherriApp/test"}


# ===================================
# HELPERS
# ===================================

def tiny_shortcut():
    return plistlib.dumps({
        "WFWorkflowActions": [{"WFWorkflowActionIdentifier": "is.workflow.actions.gettext", "WFWorkflowActionParameters": {"WFTextActionText": "hi"}}],
        "WFWorkflowClientVersion": "900", "WFWorkflowMinimumClientVersion": 900, "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {"WFWorkflowIconGlyphNumber": 59511, "WFWorkflowIconStartColor": 4282601983},
        "WFWorkflowImportQuestions": [], "WFWorkflowInputContentItemClasses": [], "WFWorkflowTypes": [],
    }).decode()


# ===================================
# TESTS
# ===================================

class ServerTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.root = fake.FakeRoot()
        self.device = fake.FakeDevice(self.root)
        signer.attest_store = AttestStore(db_path=os.path.join(self.folder.name, "a.db"), root_ca=self.root.pem)
        signer.recent_hits.clear()

        self.lines = []
        self.original_log = signer.log
        signer.log = self.lines.append

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), signer.Handler)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        signer.log = self.original_log
        signer.attest_store = None
        self.folder.cleanup()

    def call(self, method, path, body=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=90)
        connection.request(method, path, body=body, headers=headers if headers is not None else APP_HEADER)
        response = connection.getresponse()
        data = response.read()
        connection.close()
        return response.status, data

    def challenge(self):
        status, data = self.call("GET", "/challenge")
        self.assertEqual(status, 200)
        encoded = json.loads(data)["challenge"]
        return encoded, base64.b64decode(encoded)

    def register(self, device=None, **options):
        device = device or self.device
        encoded, raw = self.challenge()
        body = json.dumps({"keyId": fake.b64(device.key_id), "attestation": fake.b64(device.attestation(raw, **options)), "challenge": encoded}).encode()
        return self.call("POST", "/attest", body, {**APP_HEADER, "Content-Type": "application/json"})

    def sign(self, counter=None, device=None, tamper=False, **options):
        device = device or self.device
        body = json.dumps({"shortcutName": "t", "shortcut": tiny_shortcut()}).encode()
        headers = {**APP_HEADER, "Content-Type": "application/json"}
        if counter is not None:
            encoded, raw = self.challenge()
            headers.update({
                "X-Attest-Key": fake.b64(device.key_id),
                "X-Attest-Assertion": fake.b64(device.assertion(raw, body, counter, **options)),
                "X-Attest-Challenge": encoded,
            })
        if tamper:
            body = body.replace(b'"t"', b'"u"')
        return self.call("POST", "/sign", body, headers)

    def last_sign_line(self):
        return [line for line in self.lines if line.startswith(("200 signed", "502", "503"))][-1]

    # ----- registering

    def test_register_and_sign_attested(self):
        self.assertEqual(self.register()[0], 200)
        status, data = self.sign(counter=1)
        self.assertEqual(status, 200)
        self.assertTrue(data.startswith(b"AEA1"))
        self.assertIn("attested", self.last_sign_line())
        self.assertNotIn("failed", self.last_sign_line())

    def test_register_failure_is_generic(self):
        status, data = self.register(app_id="ABCDE12345.com.someone.else")
        self.assertEqual(status, 400)
        self.assertEqual(data, b"Attestation failed.")
        self.assertTrue(any("attest failed [bad-attestation]" in line for line in self.lines))

    def test_register_requires_app_header(self):
        status, _ = self.call("POST", "/attest", b"{}", {"User-Agent": "curl/8"})
        self.assertEqual(status, 403)

    def test_register_garbage_body(self):
        self.assertEqual(self.call("POST", "/attest", b"not json", APP_HEADER)[0], 400)

    # ----- signing in log-only mode

    def test_unattested_still_signs(self):
        status, data = self.sign()
        self.assertEqual(status, 200)
        self.assertIn("unattested", self.last_sign_line())

    def test_bad_assertion_still_signs_but_is_logged(self):
        self.register()
        self.sign(counter=1)
        status, _ = self.sign(counter=1)
        self.assertEqual(status, 200)
        self.assertIn("attest failed [replay]", self.last_sign_line())

    def test_tampered_body_is_logged(self):
        self.register()
        status, _ = self.sign(counter=1, tamper=True)
        self.assertEqual(status, 200)
        self.assertIn("attest failed [bad-signature]", self.last_sign_line())

    def test_unknown_device_is_logged(self):
        status, _ = self.sign(counter=1, device=fake.FakeDevice(self.root))
        self.assertEqual(status, 200)
        self.assertIn("attest failed [unknown-key]", self.last_sign_line())

    # ----- challenges and limits

    def test_challenge_requires_app_header(self):
        self.assertEqual(self.call("GET", "/challenge", headers={"User-Agent": "curl/8"})[0], 403)

    def test_challenge_off_when_attestation_off(self):
        signer.attest_store = None
        self.assertEqual(self.call("GET", "/challenge")[0], 503)
        self.assertEqual(self.sign()[0], 200)

    def test_challenge_has_its_own_limit(self):
        limit = signer.LIMITS["challenge"][0]
        for _ in range(limit):
            self.assertEqual(self.call("GET", "/challenge")[0], 200)
        self.assertEqual(self.call("GET", "/challenge")[0], 429)
        self.assertEqual(self.sign()[0], 200)

    def test_bad_requests_leak_nothing(self):
        status, data = self.call("POST", "/sign", b'{"shortcutName":"t","shortcut":"<plist>"}', {**APP_HEADER, "Content-Type": "application/json"})
        self.assertEqual(status, 400)
        self.assertNotIn(b"Traceback", data)

    def test_health_and_unknown_paths(self):
        self.assertEqual(self.call("GET", "/health")[0], 200)
        self.assertEqual(self.call("GET", "/nope")[0], 404)
        self.assertEqual(self.call("POST", "/nope", b"{}")[0], 404)


if __name__ == "__main__":
    unittest.main()
