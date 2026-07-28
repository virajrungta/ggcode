"""Firebase ID token verification.

Firebase stays the identity provider (the Expo app already uses it, and users
should not have to re-register). Everything else moves to Postgres.

Tokens are verified locally against Google's public keys — no round-trip to
Firebase per request, and no Admin SDK dependency.
"""

from __future__ import annotations

import logging
import time
from typing import Any

import httpx
from fastapi import Depends, Header, HTTPException, Request, status
from jose import jwt
from jose.exceptions import JWTError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.db.models import User
from app.db.session import get_db

log = logging.getLogger(__name__)

CERT_URL = "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com"
ISSUER_PREFIX = "https://securetoken.google.com/"


class _KeyCache:
    """Caches Google's signing certs, honouring the Cache-Control max-age.

    Google rotates these roughly daily. Fetching per request would add ~100ms
    and make Google an availability dependency of every single API call.
    """

    def __init__(self) -> None:
        self._keys: dict[str, str] = {}
        self._expires_at: float = 0.0

    async def get(self, kid: str) -> str | None:
        if kid in self._keys and time.time() < self._expires_at:
            return self._keys[kid]
        await self._refresh()
        return self._keys.get(kid)

    async def _refresh(self) -> None:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(CERT_URL)
            resp.raise_for_status()
            self._keys = resp.json()

        max_age = 3600
        cache_control = resp.headers.get("cache-control", "")
        for part in cache_control.split(","):
            part = part.strip()
            if part.startswith("max-age="):
                try:
                    max_age = int(part.split("=", 1)[1])
                except ValueError:
                    pass
        self._expires_at = time.time() + max_age


_key_cache = _KeyCache()


async def verify_firebase_token(token: str, settings: Settings) -> dict[str, Any]:
    try:
        header = jwt.get_unverified_header(token)
    except JWTError as exc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Malformed token") from exc

    kid = header.get("kid")
    if not kid:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Token missing key id")

    cert = await _key_cache.get(kid)
    if not cert:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Unknown token signing key")

    try:
        claims = jwt.decode(
            token,
            cert,
            algorithms=["RS256"],
            audience=settings.firebase_project_id,
            issuer=f"{ISSUER_PREFIX}{settings.firebase_project_id}",
            options={"verify_at_hash": False},
        )
    except JWTError as exc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, f"Invalid token: {exc}") from exc

    # `sub` is the stable Firebase UID. Firebase also emits `user_id`; prefer sub.
    if not claims.get("sub"):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Token missing subject")

    return claims


async def get_current_user(
    request: Request,
    authorization: str | None = Header(default=None),
    x_dev_user: str | None = Header(default=None),
    db: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> User:
    """Resolve the caller to a `users` row, creating it on first sight.

    Auto-provisioning avoids a separate registration call: the Firebase account
    already exists by the time a token reaches us, so a local row is just a
    foreign-key target.
    """
    if settings.auth_mode == "dev":
        # Guarded by Settings._guard_production, which refuses to boot with
        # GG_ENV=production and GG_AUTH_MODE=dev.
        uid = x_dev_user or "dev-user"
        email = f"{uid}@dev.local"
        claims = {"sub": uid, "email": email, "name": uid}
    else:
        if not authorization or not authorization.lower().startswith("bearer "):
            raise HTTPException(
                status.HTTP_401_UNAUTHORIZED,
                "Missing bearer token",
                headers={"WWW-Authenticate": "Bearer"},
            )
        claims = await verify_firebase_token(authorization.split(" ", 1)[1], settings)

    uid = claims["sub"]
    user = (await db.execute(select(User).where(User.firebase_uid == uid))).scalar_one_or_none()

    if user is None:
        user = User(
            firebase_uid=uid,
            email=claims.get("email"),
            display_name=claims.get("name") or (claims.get("email") or "").split("@")[0],
        )
        db.add(user)
        await db.flush()
        log.info("provisioned local user for firebase uid %s", uid)

    request.state.user_id = user.id
    return user
