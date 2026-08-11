from __future__ import annotations

import secrets
from datetime import datetime, timezone

from argon2 import PasswordHasher
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1 import schemas as S
from app.core.auth import get_current_user
from app.core.config import Settings, get_settings
from app.db.models import Device, Pot, User
from app.db.session import get_db

router = APIRouter(prefix="/devices", tags=["devices"])

_hasher = PasswordHasher()


@router.post("/claim", response_model=S.ClaimResponse)
async def claim_device(
    body: S.ClaimRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
):
    """Bind a physical pot to the calling user.

    The app reads `claim_code` from the device over an encrypted BLE link, so
    possessing a valid code proves physical proximity. Codes expire after
    `claim_code_ttl_seconds` and are single-use.
    """
    now = datetime.now(timezone.utc)

    result = await db.execute(select(Device).where(Device.claim_code == body.claim_code))
    device = result.scalar_one_or_none()

    # Same error for "no such code" and "expired code" — distinguishing them
    # would let an attacker enumerate which codes ever existed.
    if device is None or device.claim_code_expires_at is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Invalid or expired claim code")

    expires = device.claim_code_expires_at
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=timezone.utc)
    if expires < now:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Invalid or expired claim code")

    if device.claimed_by and device.claimed_by != user.id:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "This device is already registered to another account. "
            "Factory-reset it to transfer ownership.",
        )

    # Only mint if the device has not already bootstrapped its own secret.
    # Overwriting would 401 a pot that is already reporting, and the app never
    # uses this value — it is returned for the MQTT path, which HTTP ingest
    # has replaced. The device obtains its credential from /v1/ingest/bootstrap.
    if device.mqtt_secret_hash:
        secret = ""
    else:
        secret = secrets.token_urlsafe(32)
        device.mqtt_secret_hash = _hasher.hash(secret)

    device.claimed_by = user.id
    device.claimed_at = now
    device.claim_code = None            # single use
    device.claim_code_expires_at = None

    existing = await db.execute(select(Pot).where(Pot.device_id == device.id))
    pot = existing.scalar_one_or_none()
    if pot is None:
        pot = Pot(user_id=user.id, device_id=device.id, name=body.name or "My Plant")
        db.add(pot)
        await db.flush()

    return S.ClaimResponse(
        device_id=device.id,
        pot_id=pot.id,
        mqtt_username=device.id,
        mqtt_password=secret,
        mqtt_host=settings.mqtt_host,
        mqtt_port=settings.mqtt_port,
        mqtt_tls=settings.mqtt_tls,
    )


@router.get("", response_model=list[S.DeviceOut])
async def list_devices(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Device).where(Device.claimed_by == user.id))
    return list(result.scalars())


def verify_device_secret(device: Device, secret: str) -> bool:
    """Used by the broker auth hook."""
    if not device.mqtt_secret_hash:
        return False
    try:
        _hasher.verify(device.mqtt_secret_hash, secret)
        return True
    except Exception:
        return False
