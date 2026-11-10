#!/usr/bin/env python3
# ===================================
# Cherri Shortcuts Signer: App Attest Tests
# v0.0.3 BUILD 2026-11-09 21:32
# Builds fake Apple attestations and assertions with a throwaway root certificate and checks every way the real ones can pass or fail. Needs no device. Run with: .venv/bin/python -m unittest test_attest -v
# dev by @dastefster 🍒🔨
# ===================================

import base64
import datetime
import hashlib
import os
import struct
import tempfile
import time
import unittest

import cbor2
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID, ObjectIdentifier

import attest
from attest import AttestError, AttestStore

APP_ID = "B6A27JW462.com.dastefster.CherriApp"
NONCE_OID = ObjectIdentifier("1.2.840.113635.100.8.2")
PRODUCTION = b"appattest" + bytes(7)
DEVELOPMENT = b"appattestdevelop"


# ===================================
# FAKE APPLE
# ===================================

def b64(raw):
    return base64.b64encode(raw).decode()


def now():
    return datetime.datetime.now(datetime.timezone.utc)


class FakeRoot:
    def __init__(self):
        self.key = ec.generate_private_key(ec.SECP256R1())
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Test App Attest Root")])
        self.cert = (
            x509.CertificateBuilder().subject_name(name).issuer_name(name)
            .public_key(self.key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now() - datetime.timedelta(days=1)).not_valid_after(now() + datetime.timedelta(days=1))
            .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
            .add_extension(x509.KeyUsage(
                digital_signature=True, content_commitment=False, key_encipherment=False, data_encipherment=False,
                key_agreement=False, key_cert_sign=True, crl_sign=True, encipher_only=False, decipher_only=False,
            ), critical=True)
            .sign(self.key, hashes.SHA256())
        )

    @property
    def pem(self):
        return self.cert.public_bytes(serialization.Encoding.PEM)


class FakeDevice:
    # Plays the iPhone: one key, one attestation, then assertions with a rising counter.
    def __init__(self, root, app_id=APP_ID, aaguid=PRODUCTION):
        self.root = root
        self.app_id = app_id
        self.aaguid = aaguid
        self.key = ec.generate_private_key(ec.SECP256R1())
        point = self.key.public_key().public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)
        self.key_id = hashlib.sha256(point).digest()

    def attestation(self, challenge, counter=0, app_id=None, key_id_in_auth=None, root=None, wrong_nonce=False):
        signer = root or self.root
        auth_data = (
            hashlib.sha256((app_id or self.app_id).encode()).digest() + b"\x40" + struct.pack("!I", counter)
            + self.aaguid + struct.pack("!H", 32) + (key_id_in_auth or self.key_id) + cbor2.dumps({1: 2, 3: -7})
        )
        nonce = hashlib.sha256(auth_data + hashlib.sha256(challenge).digest()).digest()
        if wrong_nonce:
            nonce = bytes(32)
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "test leaf")])
        leaf = (
            x509.CertificateBuilder().subject_name(name).issuer_name(signer.cert.subject)
            .public_key(self.key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now() - datetime.timedelta(hours=1)).not_valid_after(now() + datetime.timedelta(hours=1))
            .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
            .add_extension(x509.KeyUsage(
                digital_signature=True, content_commitment=False, key_encipherment=False, data_encipherment=False,
                key_agreement=False, key_cert_sign=False, crl_sign=False, encipher_only=False, decipher_only=False,
            ), critical=True)
            # Apple wraps the nonce as SEQUENCE { [1] { OCTET STRING } }, six bytes of header before the 32-byte value.
            .add_extension(x509.UnrecognizedExtension(NONCE_OID, b"\x30\x24\xa1\x22\x04\x20" + nonce), critical=False)
            .sign(signer.key, hashes.SHA256())
        )
        return cbor2.dumps({
            "fmt": "apple-appattest",
            "attStmt": {
                "x5c": [leaf.public_bytes(serialization.Encoding.DER), signer.cert.public_bytes(serialization.Encoding.DER)],
                "receipt": b"",
            },
            "authData": auth_data,
        })

    def assertion(self, challenge, body, counter, app_id=None, signed_body=None):
        auth_data = hashlib.sha256((app_id or self.app_id).encode()).digest() + b"\x40" + struct.pack("!I", counter)
        client_data_hash = hashlib.sha256(challenge + hashlib.sha256(signed_body if signed_body is not None else body).digest()).digest()
        nonce = hashlib.sha256(auth_data + client_data_hash).digest()
        signature = self.key.sign(nonce, ec.ECDSA(hashes.SHA256()))
        return cbor2.dumps({"signature": signature, "authenticatorData": auth_data})


# ===================================
# TESTS
# ===================================

class AttestTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self.folder.name, "attest.db")
        self.root = FakeRoot()
        self.store = AttestStore(db_path=self.db_path, root_ca=self.root.pem)
        self.device = FakeDevice(self.root)

    def tearDown(self):
        self.folder.cleanup()

    def challenge(self):
        encoded = self.store.new_challenge()
        return encoded, base64.b64decode(encoded)

    def register(self, device=None, **options):
        device = device or self.device
        encoded, raw = self.challenge()
        return self.store.register(b64(device.key_id), b64(device.attestation(raw, **options)), encoded)

    def sign_request(self, counter, body=b'{"shortcut":"x"}', device=None, **options):
        device = device or self.device
        encoded, raw = self.challenge()
        return self.store.check_assertion(b64(device.key_id), b64(device.assertion(raw, body, counter, **options)), encoded, body)

    def assertFails(self, code, call, *args, **kwargs):
        with self.assertRaises(AttestError) as caught:
            call(*args, **kwargs)
        self.assertEqual(caught.exception.code, code, caught.exception.detail)

    # ----- registering

    def test_register_production(self):
        self.assertEqual(self.register(), "production")
        self.assertEqual(self.store.count_keys(), 1)

    def test_register_development(self):
        development = FakeDevice(self.root, aaguid=DEVELOPMENT)
        self.assertEqual(self.register(development), "development")

    def test_register_wrong_app(self):
        self.assertFails("bad-attestation", self.register, app_id="ABCDE12345.com.someone.else")
        self.assertEqual(self.store.count_keys(), 0)

    def test_register_other_root(self):
        self.assertFails("bad-attestation", self.register, root=FakeRoot())

    def test_register_chain_from_os_trusted_root(self):
        # The stock library also trusts every root the operating system does. Pretend the OS trusts another root, and a chain ending there must still be refused.
        import pyhanko_certvalidator.registry as registry
        from pyattest.verifiers.utils import _load_certificate

        other = FakeRoot()
        original = registry._system_trust_roots
        registry._system_trust_roots = lambda: [_load_certificate(other.pem)]
        try:
            self.assertFails("bad-attestation", self.register, root=other)
        finally:
            registry._system_trust_roots = original
        self.assertEqual(self.store.count_keys(), 0)

    def test_register_wrong_nonce(self):
        self.assertFails("bad-attestation", self.register, wrong_nonce=True)

    def test_register_nonzero_counter(self):
        self.assertFails("bad-attestation", self.register, counter=1)

    def test_register_key_id_mismatch(self):
        self.assertFails("bad-attestation", self.register, key_id_in_auth=bytes(32))

    def test_register_twice(self):
        self.register()
        self.assertFails("known-key", self.register)

    def test_register_garbage(self):
        encoded, _ = self.challenge()
        self.assertFails("bad-attestation", self.store.register, b64(self.device.key_id), b64(b"not cbor at all"), encoded)

    def test_register_bad_input(self):
        encoded, _ = self.challenge()
        self.assertFails("bad-input", self.store.register, "not base64!!", b64(b"x"), encoded)
        self.assertFails("bad-input", self.store.register, b64(b"short"), b64(b"x"), encoded)
        self.assertFails("bad-input", self.store.register, b64(self.device.key_id), b64(b"x" * (attest.MAX_ATTESTATION_BYTES + 1)), self.store.new_challenge())

    # ----- challenges

    def test_challenge_single_use(self):
        encoded, raw = self.challenge()
        attestation = b64(self.device.attestation(raw))
        self.store.register(b64(self.device.key_id), attestation, encoded)
        other = FakeDevice(self.root)
        self.assertFails("unknown-challenge", self.store.register, b64(other.key_id), b64(other.attestation(raw)), encoded)

    def test_challenge_unknown_and_expired(self):
        self.assertFails("unknown-challenge", self.store.take_challenge, b64(os.urandom(32)))
        encoded, _ = self.challenge()
        original = attest.CHALLENGE_TTL_SECONDS
        try:
            self.store._challenges = {k: time.time() - 1 for k in self.store._challenges}
            self.assertFails("unknown-challenge", self.store.take_challenge, encoded)
        finally:
            attest.CHALLENGE_TTL_SECONDS = original

    def test_challenge_cap(self):
        original = attest.MAX_OUTSTANDING_CHALLENGES
        attest.MAX_OUTSTANDING_CHALLENGES = 3
        try:
            for _ in range(3):
                self.store.new_challenge()
            self.assertFails("busy", self.store.new_challenge)
        finally:
            attest.MAX_OUTSTANDING_CHALLENGES = original

    # ----- assertions

    def test_assertion_counts_up(self):
        self.register()
        self.assertEqual(self.sign_request(1)[1], 1)
        self.assertEqual(self.sign_request(2)[1], 2)
        self.assertEqual(self.sign_request(5)[1], 5)

    def test_assertion_replay(self):
        self.register()
        self.sign_request(1)
        self.sign_request(2)
        self.assertFails("replay", self.sign_request, 2)
        self.assertFails("replay", self.sign_request, 1)

    def test_assertion_counter_must_beat_zero(self):
        self.register()
        self.assertFails("replay", self.sign_request, 0)

    def test_assertion_other_body(self):
        self.register()
        self.assertFails("bad-signature", self.sign_request, 1, body=b'{"shortcut":"x"}', signed_body=b'{"shortcut":"y"}')

    def test_assertion_wrong_app(self):
        self.register()
        self.assertFails("bad-app", self.sign_request, 1, app_id="ABCDE12345.com.someone.else")

    def test_assertion_unknown_key(self):
        stranger = FakeDevice(self.root)
        self.assertFails("unknown-key", self.sign_request, 1, device=stranger)

    def test_assertion_other_devices_key(self):
        self.register()
        stranger = FakeDevice(self.root)
        encoded, raw = self.challenge()
        body = b"{}"
        forged = b64(stranger.assertion(raw, body, 1))
        self.assertFails("bad-signature", self.store.check_assertion, b64(self.device.key_id), forged, encoded, body)

    def test_assertion_challenge_reuse(self):
        self.register()
        encoded, raw = self.challenge()
        body = b"{}"
        assertion = b64(self.device.assertion(raw, body, 1))
        self.store.check_assertion(b64(self.device.key_id), assertion, encoded, body)
        self.assertFails("unknown-challenge", self.store.check_assertion, b64(self.device.key_id), b64(self.device.assertion(raw, body, 2)), encoded, body)

    def test_assertion_garbage(self):
        self.register()
        encoded, _ = self.challenge()
        self.assertFails("bad-assertion", self.store.check_assertion, b64(self.device.key_id), b64(b"junk"), encoded, b"{}")

    def test_assertion_simultaneous_copies(self):
        # Two copies of one request racing: exactly one may win.
        import threading
        self.register()
        body = b"{}"
        prepared = []
        for _ in range(8):
            encoded, raw = self.challenge()
            prepared.append((encoded, b64(self.device.assertion(raw, body, 1))))

        results = []
        def attempt(encoded, assertion):
            try:
                self.store.check_assertion(b64(self.device.key_id), assertion, encoded, body)
                results.append("ok")
            except AttestError as error:
                results.append(error.code)

        threads = [threading.Thread(target=attempt, args=pair) for pair in prepared]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(results.count("ok"), 1, results)
        self.assertEqual(results.count("replay"), 7, results)

    # ----- storage

    def test_counter_survives_restart(self):
        self.register()
        self.sign_request(3)
        reopened = AttestStore(db_path=self.db_path, root_ca=self.root.pem)
        self.store = reopened
        self.assertFails("replay", self.sign_request, 3)
        self.assertEqual(self.sign_request(4)[1], 4)


if __name__ == "__main__":
    unittest.main()
