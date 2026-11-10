#!/usr/bin/env python3
# ===================================
# Cherri Shortcuts Signer: App Attest
# v0.0.3 BUILD 2026-11-09 21:32
# Checks that a request comes from a genuine copy of the Cherri app on a real Apple device. Hands out one-time challenges, registers a device from its attestation, and verifies the assertion that rides along with every request.
# dev by @dastefster 🍒🔨
# ===================================

import asyncio
import base64
import binascii
import hashlib
import os
import secrets
import sqlite3
import threading
import time

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from pyattest.assertion import Assertion
from pyattest.attestation import Attestation
from pyattest.configs.apple import AppleConfig
from pyattest.exceptions import InvalidCertificateChainException
from pyattest.verifiers.apple_attestation import AppleAttestationVerifier
from pyattest.verifiers.utils import _load_certificate
from pyhanko_certvalidator import CertificateValidator, ValidationContext
from pyhanko_certvalidator.errors import PathBuildingError, PathValidationError


# ===================================
# CONFIG
# ===================================

# Apple's App ID is the Team ID and bundle identifier joined by a dot. Every attestation and assertion carries a hash of it.
APP_ID = "B6A27JW462.com.dastefster.CherriApp"

DEFAULT_DB_PATH = os.environ.get("SIGNER_ATTEST_DB", os.path.join(os.path.dirname(os.path.abspath(__file__)), "attest.db"))

# A challenge is only good for one try and a few minutes, so a captured one is useless later.
CHALLENGE_BYTES = 32
CHALLENGE_TTL_SECONDS = 300

# Challenges live in memory, so this stops a flood of requests for them from filling it.
MAX_OUTSTANDING_CHALLENGES = 2000

# Real attestations are a few KB and assertions a few hundred bytes. These stop oversized junk before it is parsed.
MAX_ATTESTATION_BYTES = 20 * 1024
MAX_ASSERTION_BYTES = 2 * 1024
KEY_ID_BYTES = 32


# ===================================
# ERRORS
# ===================================

# The code is for the private log and for choosing a status. It never needs to reach the client in detail, so a caller can't learn which check failed.
class AttestError(Exception):
    def __init__(self, code, detail=""):
        super().__init__(code)
        self.code = code
        self.detail = detail


# ===================================
# STRICT CHAIN CHECK
# ===================================

# pyattest 1.0.5 builds its trust from Apple's root PLUS every root in the operating system's trust list, so a chain that ends at any other trusted root would pass. Apple's root is the only anchor that is meant to count, so this replaces the chain check with one that trusts nothing else.
class StrictAppleAttestationVerifier(AppleAttestationVerifier):
    async def verify_certificate_chain(self, chain):
        leaf = _load_certificate(chain.pop(0))
        context = ValidationContext(trust_roots=[self.attestation.config.root_ca])
        validator = CertificateValidator(leaf, [_load_certificate(item) for item in chain], validation_context=context)
        try:
            return await validator.async_validate_usage({"digital_signature"})
        except (PathBuildingError, PathValidationError) as error:
            raise InvalidCertificateChainException from error


class StrictAppleConfig(AppleConfig):
    attestation_verifier_class = StrictAppleAttestationVerifier


# ===================================
# HELPERS
# ===================================

def decode_base64(value, max_bytes):
    if not isinstance(value, str) or len(value) > max_bytes * 2:
        raise AttestError("bad-input")
    try:
        raw = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError):
        raise AttestError("bad-input")
    if not raw or len(raw) > max_bytes:
        raise AttestError("bad-input")
    return raw


def decode_key_id(value):
    raw = decode_base64(value, KEY_ID_BYTES)
    if len(raw) != KEY_ID_BYTES:
        raise AttestError("bad-input")
    return raw


# ===================================
# STORE
# ===================================

class AttestStore:
    # root_ca is only for tests, which sign fake attestations with their own root. In real use it stays None and Apple's root is used.
    def __init__(self, db_path=DEFAULT_DB_PATH, app_id=APP_ID, root_ca=None):
        self.app_id = app_id
        self.app_id_hash = hashlib.sha256(app_id.encode()).digest()
        self.root_ca = root_ca

        self._lock = threading.Lock()
        # The server answers requests on many threads that share one connection, so every database call takes this lock.
        self._db_lock = threading.Lock()
        self._challenges = {}

        # Autocommit, so every statement stands alone and the counter update below is atomic by itself.
        self._db = sqlite3.connect(db_path, check_same_thread=False, isolation_level=None)
        self._db.execute("PRAGMA journal_mode=WAL")
        self._db.execute(
            "CREATE TABLE IF NOT EXISTS keys ("
            "key_id BLOB PRIMARY KEY, public_key BLOB NOT NULL, counter INTEGER NOT NULL, "
            "environment TEXT NOT NULL, created REAL NOT NULL, last_used REAL)"
        )
        try:
            os.chmod(db_path, 0o600)
        except OSError:
            pass

    # ===================================
    # CHALLENGES
    # ===================================

    def new_challenge(self):
        now = time.time()
        with self._lock:
            for value in [v for v, expires in self._challenges.items() if expires < now]:
                del self._challenges[value]
            if len(self._challenges) >= MAX_OUTSTANDING_CHALLENGES:
                raise AttestError("busy")

            value = secrets.token_bytes(CHALLENGE_BYTES)
            self._challenges[value] = now + CHALLENGE_TTL_SECONDS
        return base64.b64encode(value).decode()

    # A challenge is spent the moment it is looked up, even when the check after it fails, so no challenge ever gets a second try.
    def take_challenge(self, encoded):
        value = decode_base64(encoded, CHALLENGE_BYTES)
        if len(value) != CHALLENGE_BYTES:
            raise AttestError("bad-input")

        with self._lock:
            expires = self._challenges.pop(value, None)
        if expires is None or expires < time.time():
            raise AttestError("unknown-challenge")
        return value

    # ===================================
    # REGISTER A DEVICE
    # ===================================

    # Verifies an attestation and remembers the device's key. Returns "production" or "development".
    def register(self, key_id_encoded, attestation_encoded, challenge_encoded):
        key_id = decode_key_id(key_id_encoded)
        raw = decode_base64(attestation_encoded, MAX_ATTESTATION_BYTES)
        challenge = self.take_challenge(challenge_encoded)

        if self._load_key(key_id) is not None:
            raise AttestError("known-key")

        # production=False accepts both Apple environments. Xcode builds attest as development and TestFlight and the App Store as production, and the environment is stored so it can be told apart later.
        config = StrictAppleConfig(key_id=key_id, app_id=self.app_id, production=False, root_ca=self.root_ca)
        attestation = Attestation(raw, challenge, config)
        try:
            asyncio.run(attestation.verify())
            verified = attestation.data
            leaf = verified["certs"].last
            if verified["data"]["raw"].get("fmt") != "apple-appattest":
                raise AttestError("bad-attestation", "unexpected format")

            public_key_der = leaf.public_key.dump()
            public_key = serialization.load_der_public_key(public_key_der)
            if not isinstance(public_key, ec.EllipticCurvePublicKey) or public_key.curve.name != "secp256r1":
                raise AttestError("bad-attestation", "key is not P-256")
            environment = "development" if verified["data"]["aaguid"] == b"appattestdevelop" else "production"
        except AttestError:
            raise
        except Exception as error:
            # Malformed input fails in many different ways, and all of them mean the same thing.
            raise AttestError("bad-attestation", "{}: {}".format(type(error).__name__, error))

        try:
            with self._db_lock:
                self._db.execute(
                    "INSERT INTO keys (key_id, public_key, counter, environment, created) VALUES (?, ?, 0, ?, ?)",
                    (key_id, public_key_der, environment, time.time()),
                )
        except sqlite3.IntegrityError:
            raise AttestError("known-key")
        return environment

    # ===================================
    # CHECK A REQUEST
    # ===================================

    # The client signs the hash of (challenge + hash of the request body), so a signature can't be reused for another body or another challenge. Returns the key id and the new counter.
    def check_assertion(self, key_id_encoded, assertion_encoded, challenge_encoded, body):
        key_id = decode_key_id(key_id_encoded)
        raw = decode_base64(assertion_encoded, MAX_ASSERTION_BYTES)
        challenge = self.take_challenge(challenge_encoded)

        stored = self._load_key(key_id)
        if stored is None:
            raise AttestError("unknown-key")

        try:
            public_key = serialization.load_der_public_key(stored[0])
        except ValueError:
            raise AttestError("unknown-key", "stored key could not be read")

        client_data_hash = hashlib.sha256(challenge + hashlib.sha256(body).digest()).digest()
        config = AppleConfig(key_id=key_id, app_id=self.app_id, production=False, root_ca=self.root_ca)
        assertion = Assertion(raw, client_data_hash, public_key, config)
        try:
            assertion.verify()
            data = assertion.data
            if len(data["authenticator_data"]) < 37:
                raise AttestError("bad-assertion", "authenticator data too short")
        except InvalidSignature:
            raise AttestError("bad-signature")
        except AttestError:
            raise
        except Exception as error:
            raise AttestError("bad-assertion", "{}: {}".format(type(error).__name__, error))

        # The library only checks the signature. These two checks are Apple's and are ours to make.
        if data["rp_id"] != self.app_id_hash:
            raise AttestError("bad-app")

        # The counter must go up on every request. Doing the comparison inside the UPDATE makes two simultaneous copies of one request race, and exactly one wins.
        counter = data["counter"]
        with self._db_lock:
            updated = self._db.execute(
                "UPDATE keys SET counter = ?, last_used = ? WHERE key_id = ? AND counter < ?",
                (counter, time.time(), key_id, counter),
            )
        if updated.rowcount != 1:
            raise AttestError("replay")
        return key_id, counter

    # ===================================
    # STORAGE
    # ===================================

    def _load_key(self, key_id):
        with self._db_lock:
            return self._db.execute("SELECT public_key, counter FROM keys WHERE key_id = ?", (key_id,)).fetchone()

    def count_keys(self):
        with self._db_lock:
            return self._db.execute("SELECT COUNT(*) FROM keys").fetchone()[0]
