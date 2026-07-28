"""Tests for Firebase ID token verification.

Until now only the dev-mode bypass was covered, which is exactly the half that
does not matter — it is disabled in production by a startup guard. This covers
the path that actually protects user data.

Tokens are minted locally with a throwaway RSA key and the verifier is pointed
at that key, so the whole thing runs offline with no Firebase project.
"""

from __future__ import annotations

import base64
import json
import time

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi import HTTPException
from jose import jwt

from app.core import auth as auth_module
from app.core.config import Settings

PROJECT = "greengenius-test"
KID = "test-key-1"


@pytest.fixture(scope="module")
def keypair():
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    private_pem = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode()
    public_pem = key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode()
    return private_pem, public_pem


@pytest.fixture(autouse=True)
def patched_keycache(keypair, monkeypatch):
    """Point the verifier at our key instead of Google's cert endpoint."""
    _, public_pem = keypair

    async def fake_get(kid: str):
        return public_pem if kid == KID else None

    monkeypatch.setattr(auth_module._key_cache, "get", fake_get)


@pytest.fixture
def settings():
    return Settings(
        env="development",
        auth_mode="firebase",
        firebase_project_id=PROJECT,
        database_url="sqlite+aiosqlite:///:memory:",
    )


def make_token(
    private_pem: str,
    *,
    sub: str = "user-123",
    aud: str = PROJECT,
    iss: str | None = None,
    exp_delta: int = 3600,
    kid: str = KID,
    email: str = "someone@example.com",
) -> str:
    now = int(time.time())
    claims = {
        "sub": sub,
        "aud": aud,
        "iss": iss or f"{auth_module.ISSUER_PREFIX}{PROJECT}",
        "iat": now,
        "exp": now + exp_delta,
        "email": email,
        "name": "Test User",
    }
    return jwt.encode(claims, private_pem, algorithm="RS256",
                      headers={"kid": kid})


pytestmark = pytest.mark.asyncio


class TestValidTokens:
    async def test_accepts_a_well_formed_token(self, keypair, settings):
        private_pem, _ = keypair
        token = make_token(private_pem)

        claims = await auth_module.verify_firebase_token(token, settings)
        assert claims["sub"] == "user-123"
        assert claims["email"] == "someone@example.com"


class TestRejections:
    async def test_expired_token(self, keypair, settings):
        private_pem, _ = keypair
        token = make_token(private_pem, exp_delta=-60)

        with pytest.raises(HTTPException) as exc:
            await auth_module.verify_firebase_token(token, settings)
        assert exc.value.status_code == 401

    async def test_wrong_audience(self, keypair, settings):
        """A token minted for a different Firebase project must not work.

        Without the audience check, any Firebase project's tokens would
        authenticate against this backend — the classic confused-deputy.
        """
        private_pem, _ = keypair
        token = make_token(private_pem, aud="someone-elses-project")

        with pytest.raises(HTTPException) as exc:
            await auth_module.verify_firebase_token(token, settings)
        assert exc.value.status_code == 401

    async def test_wrong_issuer(self, keypair, settings):
        private_pem, _ = keypair
        token = make_token(private_pem, iss="https://evil.example.com/")

        with pytest.raises(HTTPException) as exc:
            await auth_module.verify_firebase_token(token, settings)
        assert exc.value.status_code == 401

    async def test_unknown_key_id(self, keypair, settings):
        """Signed correctly but with a kid the cert endpoint doesn't know."""
        private_pem, _ = keypair
        token = make_token(private_pem, kid="not-a-real-key")

        with pytest.raises(HTTPException) as exc:
            await auth_module.verify_firebase_token(token, settings)
        assert exc.value.status_code == 401
        assert "signing key" in exc.value.detail.lower()

    async def test_missing_key_id(self, keypair, settings):
        private_pem, _ = keypair
        now = int(time.time())
        token = jwt.encode(
            {"sub": "u", "aud": PROJECT,
             "iss": f"{auth_module.ISSUER_PREFIX}{PROJECT}",
             "exp": now + 60},
            private_pem, algorithm="RS256",
        )
        # python-jose emits no kid unless asked; if it ever does, skip.
        if jwt.get_unverified_header(token).get("kid"):
            pytest.skip("library now emits a kid by default")

        with pytest.raises(HTTPException) as exc:
            await auth_module.verify_firebase_token(token, settings)
        assert exc.value.status_code == 401

    async def test_signature_from_a_different_key(self, settings):
        """The core check: a token signed by anyone else is rejected."""
        attacker = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        attacker_pem = attacker.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        ).decode()

        token = make_token(attacker_pem)  # right kid, wrong key

        with pytest.raises(HTTPException) as exc:
            await auth_module.verify_firebase_token(token, settings)
        assert exc.value.status_code == 401

    async def test_garbage_string(self, settings):
        with pytest.raises(HTTPException) as exc:
            await auth_module.verify_firebase_token("not.a.token", settings)
        assert exc.value.status_code == 401

    async def test_unsigned_none_algorithm_token(self, settings):
        """`alg: none` must never be accepted.

        The canonical JWT vulnerability: a token with the signature stripped
        and the algorithm set to "none". `verify_firebase_token` pins RS256,
        so this must fail regardless of what the header claims.
        """
        # Hand-assembled: the library refuses to mint one, but an attacker
        # does not use the library.
        def b64(obj: dict) -> str:
            return (
                base64.urlsafe_b64encode(json.dumps(obj).encode())
                .rstrip(b"=")
                .decode()
            )

        header = b64({"alg": "none", "typ": "JWT", "kid": KID})
        payload = b64({
            "sub": "attacker",
            "aud": PROJECT,
            "iss": f"{auth_module.ISSUER_PREFIX}{PROJECT}",
            "exp": int(time.time()) + 60,
        })
        token = f"{header}.{payload}."  # empty signature

        with pytest.raises(HTTPException) as exc:
            await auth_module.verify_firebase_token(token, settings)
        assert exc.value.status_code == 401


class TestProductionGuards:
    """These exist so a misconfigured deploy fails at boot, not at runtime."""

    def test_dev_auth_rejected_in_production(self):
        with pytest.raises(ValueError, match="GG_AUTH_MODE=dev"):
            Settings(
                env="production", auth_mode="dev", mqtt_tls=True,
                database_url="postgresql+asyncpg://x/y",
            )

    def test_simulate_rejected_in_production(self):
        with pytest.raises(ValueError, match="GG_SIMULATE"):
            Settings(
                env="production", auth_mode="firebase", simulate=True,
                mqtt_tls=True, database_url="postgresql+asyncpg://x/y",
            )

    def test_plaintext_mqtt_rejected_in_production(self):
        with pytest.raises(ValueError, match="MQTT_TLS"):
            Settings(
                env="production", auth_mode="firebase", mqtt_tls=False,
                database_url="postgresql+asyncpg://x/y",
            )

    def test_wildcard_cors_rejected_in_production(self):
        with pytest.raises(ValueError, match="Wildcard CORS"):
            Settings(
                env="production", auth_mode="firebase", mqtt_tls=True,
                cors_origins=["*"],
                database_url="postgresql+asyncpg://x/y",
            )

    def test_sqlite_rejected_in_production(self):
        with pytest.raises(ValueError, match="SQLite"):
            Settings(
                env="production", auth_mode="firebase", mqtt_tls=True,
                database_url="sqlite+aiosqlite:///./x.db",
            )

    def test_valid_production_config_boots(self):
        s = Settings(
            env="production", auth_mode="firebase", mqtt_tls=True,
            cors_origins=["https://app.greengenius.example"],
            database_url="postgresql+asyncpg://user:pw@host/db",
        )
        assert s.env == "production"
