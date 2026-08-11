"""HTTP telemetry ingest — the transport that works on a sleeping host.

MQTT needs a subscriber that is always connected, which rules out every free
tier (see docs/HOSTING_PLAN.md). A POST wakes the service instead, so the same
data path survives on hosting that sleeps after 15 minutes idle.

The response carries any pending commands, which is what replaces MQTT's
downlink: no polling, no second connection, no broker. Worst-case latency for
a watering command is one telemetry interval.

Validation is shared with the MQTT worker — same clock-skew guard, same
plausibility clamp — so the two transports cannot drift apart.
"""

from __future__ import annotations

import logging
import secrets
from datetime import datetime, timezone
from typing import Annotated

from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError, VerificationError
from fastapi import APIRouter, Depends, Header, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Command, Device, Reading
from app.db.session import get_db
from app.workers.ingest import _parse_ts
from app.services.telemetry_codec import clamp_sample

log = logging.getLogger(__name__)
router = APIRouter(prefix="/ingest", tags=["ingest"])

_hasher = PasswordHasher()

# A pot batches 12 samples by contract. The ceiling allows a backlog flush
# after an outage without letting one request pin the event loop.
MAX_SAMPLES_PER_REQUEST = 120


class SampleIn(BaseModel):
    ts: float | None = None
    temp_c: float | None = None
    rh: float | None = None
    soil_pct: float | None = None
    soil2_pct: float | None = None
    lux: float | None = None
    batt_mv: int | None = None
    flags: int = 0


class TelemetryIn(BaseModel):
    v: int = 1
    device_id: str
    samples: list[SampleIn] = Field(default_factory=list)


class CommandOut(BaseModel):
    id: str
    op: str
    args: dict
    expires_at: int


class IngestResponse(BaseModel):
    accepted: int
    rejected: int
    # Empty almost always. This is the downlink: the device applies these and
    # reports the outcome on its next POST.
    commands: list[CommandOut]
    server_time: int


async def authenticate_device(
    device_id: str,
    authorization: Annotated[str | None, Header()],
    db: AsyncSession,
) -> Device:
    """Bearer token is the per-device secret issued at claim time.

    Same secret as the MQTT password, different transport. Only the argon2
    hash is stored, so a database leak does not yield working credentials.
    """
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED,
            "Missing device credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    secret = authorization.split(" ", 1)[1]

    device = await db.get(Device, device_id)

    # Same error whether the device is unknown or the secret is wrong —
    # distinguishing them would let an attacker enumerate valid device ids.
    unauthorized = HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid device credentials")

    if device is None or not device.mqtt_secret_hash:
        raise unauthorized
    try:
        _hasher.verify(device.mqtt_secret_hash, secret)
    except (VerifyMismatchError, VerificationError):
        raise unauthorized from None

    return device


@router.post("/telemetry", response_model=IngestResponse)
async def ingest_telemetry(
    body: TelemetryIn,
    authorization: Annotated[str | None, Header()] = None,
    db: AsyncSession = Depends(get_db),
):
    device = await authenticate_device(body.device_id, authorization, db)

    if len(body.samples) > MAX_SAMPLES_PER_REQUEST:
        raise HTTPException(
            status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            f"At most {MAX_SAMPLES_PER_REQUEST} samples per request",
        )

    arrival = datetime.now(timezone.utc)
    rows: list[Reading] = []
    rejected = 0

    for sample in body.samples:
        raw = sample.model_dump()

        # Null ts means the device has no SNTP sync yet; arrival time is
        # substituted rather than writing 1970 into the table, which would
        # wreck every chart built over it.
        ts = _parse_ts(raw.get("ts"), arrival)
        if ts is None:
            rejected += 1
            continue

        cleaned, bad_fields = clamp_sample(raw)
        if bad_fields:
            log.info("device %s: nulled implausible %s",
                     device.id, ", ".join(bad_fields))

        rows.append(Reading(
            time=ts,
            device_id=device.id,
            temp_c=cleaned.get("temp_c"),
            rh=cleaned.get("rh"),
            soil_pct=cleaned.get("soil_pct"),
            lux=cleaned.get("lux"),
            batt_mv=cleaned.get("batt_mv"),
            flags=int(cleaned.get("flags") or 0),
        ))

    if rows:
        db.add_all(rows)

    device.last_seen_at = arrival
    device.online = True

    # Only `queued`. Marking sent here makes delivery at-most-once: if the
    # response is lost in transit the command is dropped rather than retried.
    #
    # That is the right trade for a pump. At-least-once would mean a device
    # that applied a command and lost power before acking gets it again on the
    # next POST — watering twice. Missing one watering is recoverable; a
    # double dose into a pot is not, and the user can simply tap again.
    pending = (await db.execute(
        select(Command)
        .where(
            Command.device_id == device.id,
            Command.state == "queued",
            Command.expires_at > arrival,
        )
        .order_by(Command.issued_at)
        .limit(8)
    )).scalars().all()

    commands = []
    for cmd in pending:
        cmd.state = "sent"
        commands.append(CommandOut(
            id=cmd.id,
            op=cmd.op,
            args=cmd.args or {},
            expires_at=int(cmd.expires_at.replace(
                tzinfo=cmd.expires_at.tzinfo or timezone.utc).timestamp()),
        ))

    return IngestResponse(
        accepted=len(rows),
        rejected=rejected,
        commands=commands,
        # The device uses this to correct its clock when SNTP is unavailable,
        # which keeps expires_at meaningful without an NTP round trip.
        server_time=int(arrival.timestamp()),
    )


class BootstrapIn(BaseModel):
    device_id: str
    token: str
    fw_version: str | None = None


class BootstrapOut(BaseModel):
    secret: str
    server_time: int


@router.post("/bootstrap", response_model=BootstrapOut)
async def bootstrap_device(
    body: BootstrapIn,
    db: AsyncSession = Depends(get_db),
):
    """Issue the device its telemetry secret, proved by the token on the pot.

    Deliberately does not create the `devices` row. An endpoint that minted
    devices on demand would let anyone register an unused device id and squat
    it before the real pot ever booted. Registration stays a provisioning
    step; see scripts/register_device.py.

    Minting a fresh secret on every call is what makes the device
    self-healing: if its stored secret is ever invalidated it gets a 401,
    drops the secret and calls this again, rather than going silent until
    someone reflashes it.
    """
    result = await db.execute(
        select(Device).where(Device.bootstrap_token == body.token)
    )
    device = result.scalar_one_or_none()

    # Token must match *and* belong to the device claiming it, or a pot could
    # authenticate as its neighbour. Same error for both failures so the
    # response cannot be used to enumerate device ids.
    if device is None or device.id != body.device_id:
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED, "Invalid device credentials"
        )

    secret = secrets.token_urlsafe(32)
    device.mqtt_secret_hash = _hasher.hash(secret)
    if body.fw_version:
        device.fw_version = body.fw_version
    device.last_seen_at = datetime.now(timezone.utc)

    log.info("device %s bootstrapped a new secret", device.id)
    return BootstrapOut(
        secret=secret,
        server_time=int(datetime.now(timezone.utc).timestamp()),
    )


class AckIn(BaseModel):
    id: str
    result: str
    error: str | None = None


@router.post("/ack", status_code=status.HTTP_204_NO_CONTENT)
async def ack_command(
    body: AckIn,
    device_id: str,
    authorization: Annotated[str | None, Header()] = None,
    db: AsyncSession = Depends(get_db),
):
    device = await authenticate_device(device_id, authorization, db)

    cmd = await db.get(Command, body.id)
    # A pot must not be able to ack another pot's command.
    if cmd is None or cmd.device_id != device.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Command not found")

    cmd.state = "acked" if body.result == "ok" else body.result
    cmd.result = body.result
    cmd.error = body.error
    cmd.acked_at = datetime.now(timezone.utc)
