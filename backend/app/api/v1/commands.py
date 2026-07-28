from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1 import schemas as S
from app.api.v1.deps import owned_pot, owned_pot_with_device
from app.core.auth import get_current_user
from app.core.config import Settings, get_settings
from app.db.models import CareEvent, Command, Pot, Reading, User
from app.db.session import get_db
from app.services.mqtt import publish_command

log = logging.getLogger(__name__)
router = APIRouter(prefix="/pots", tags=["commands"])

# Server-side guards. These duplicate the firmware interlocks on purpose: the
# firmware is authoritative because it still has to be safe when the cloud is
# wrong or unreachable, but rejecting obvious abuse here saves a round trip and
# gives the user a real error message instead of a silent `rejected` ack.
MAX_PUMP_SECONDS = 30.0
MIN_INTERVAL_BETWEEN_WATERINGS = timedelta(minutes=10)
SOIL_WET_THRESHOLD_PCT = 70.0


@router.post("/{pot_id}/water", response_model=S.CommandOut, status_code=status.HTTP_202_ACCEPTED)
async def water_pot(
    body: S.WaterRequest,
    pot: Pot = Depends(owned_pot_with_device),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
):
    now = datetime.now(timezone.utc)

    if body.duration_s > MAX_PUMP_SECONDS:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            f"Maximum single watering is {MAX_PUMP_SECONDS:g}s",
        )

    recent = await db.execute(
        select(CareEvent)
        .where(CareEvent.pot_id == pot.id, CareEvent.kind == "watered")
        .order_by(CareEvent.at.desc())
        .limit(1)
    )
    last = recent.scalar_one_or_none()
    if last is not None:
        last_at = last.at if last.at.tzinfo else last.at.replace(tzinfo=timezone.utc)
        if now - last_at < MIN_INTERVAL_BETWEEN_WATERINGS:
            wait = MIN_INTERVAL_BETWEEN_WATERINGS - (now - last_at)
            raise HTTPException(
                status.HTTP_429_TOO_MANY_REQUESTS,
                f"Watered recently. Try again in {int(wait.total_seconds() // 60) + 1} min.",
            )

    latest = await db.execute(
        select(Reading)
        .where(Reading.device_id == pot.device_id)
        .order_by(Reading.time.desc())
        .limit(1)
    )
    reading = latest.scalar_one_or_none()
    if reading and reading.soil_pct is not None and reading.soil_pct >= SOIL_WET_THRESHOLD_PCT:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"Soil is already at {reading.soil_pct:.0f}% moisture. Watering now risks root rot.",
        )

    command = Command(
        device_id=pot.device_id,
        op="pump",
        args={"duration_s": body.duration_s},
        issued_by=user.id,
        expires_at=now + timedelta(seconds=settings.command_default_ttl_seconds),
    )
    db.add(command)
    await db.flush()

    try:
        await publish_command(command)
        command.state = "sent"
    except Exception as exc:
        # Stays queued rather than failing the request: the device may simply
        # be briefly offline, and the row is the durable record either way.
        log.warning("could not publish command %s: %s", command.id, exc)

    return command


@router.get("/{pot_id}/commands", response_model=list[S.CommandOut])
async def list_commands(
    pot: Pot = Depends(owned_pot),
    db: AsyncSession = Depends(get_db),
    limit: int = 50,
):
    result = await db.execute(
        select(Command)
        .where(Command.device_id == pot.device_id)
        .order_by(Command.issued_at.desc())
        .limit(min(limit, 200))
    )
    return list(result.scalars())
