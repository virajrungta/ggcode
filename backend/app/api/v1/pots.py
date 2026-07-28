from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import Integer, cast, delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.v1 import schemas as S
from app.api.v1.deps import owned_pot
from app.core.auth import get_current_user
from app.db.models import Alert, CareEvent, Device, Pot, Reading, User
from app.db.session import get_db
from app.services import care_engine

router = APIRouter(prefix="/pots", tags=["pots"])

BUCKETS: dict[str, timedelta] = {
    "5m": timedelta(minutes=5),
    "1h": timedelta(hours=1),
    "1d": timedelta(days=1),
}


@router.get("", response_model=list[S.PotOut])
async def list_pots(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Pot)
        .options(selectinload(Pot.species))
        .where(Pot.user_id == user.id)
        .order_by(Pot.created_at.desc())
    )
    return list(result.scalars())


@router.post("", response_model=S.PotOut, status_code=status.HTTP_201_CREATED)
async def create_pot(
    body: S.PotCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if body.device_id:
        device = await db.get(Device, body.device_id)
        if device is None or device.claimed_by != user.id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Device not found or not claimed by you")
        existing = await db.execute(select(Pot).where(Pot.device_id == body.device_id))
        if existing.scalar_one_or_none():
            raise HTTPException(status.HTTP_409_CONFLICT, "Device is already paired to a pot")

    pot = Pot(user_id=user.id, name=body.name, device_id=body.device_id)
    db.add(pot)
    await db.flush()
    await db.refresh(pot, ["species"])
    return pot


@router.get("/{pot_id}", response_model=S.PotOut)
async def get_pot(pot: Pot = Depends(owned_pot)):
    return pot


@router.patch("/{pot_id}", response_model=S.PotOut)
async def update_pot(
    body: S.PotUpdate,
    pot: Pot = Depends(owned_pot),
    db: AsyncSession = Depends(get_db),
):
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(pot, field, value)
    await db.flush()
    return pot


@router.delete("/{pot_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_pot(
    pot: Pot = Depends(owned_pot),
    db: AsyncSession = Depends(get_db),
):
    # Children first — these tables have no ON DELETE CASCADE, and orphaned
    # rows would keep a deleted pot's history queryable.
    await db.execute(delete(CareEvent).where(CareEvent.pot_id == pot.id))
    await db.execute(delete(Alert).where(Alert.pot_id == pot.id))
    await db.delete(pot)


@router.get("/{pot_id}/latest", response_model=S.LatestOut)
async def get_latest(
    pot: Pot = Depends(owned_pot),
    db: AsyncSession = Depends(get_db),
):
    reading = None
    online = False

    if pot.device_id:
        device = await db.get(Device, pot.device_id)
        online = bool(device and device.online)
        result = await db.execute(
            select(Reading)
            .where(Reading.device_id == pot.device_id)
            .order_by(Reading.time.desc())
            .limit(1)
        )
        row = result.scalar_one_or_none()
        if row:
            reading = S.ReadingOut.model_validate(row, from_attributes=True)

    health = None
    if reading:
        health = care_engine.assess(
            reading.model_dump(),
            pot.species.scientific_name if pot.species else None,
            pot.species.care_profile if pot.species else None,
        )

    return S.LatestOut(
        pot_id=pot.id, device_id=pot.device_id, online=online,
        reading=reading, health=health,
    )


@router.get("/{pot_id}/readings", response_model=S.SeriesOut)
async def get_readings(
    pot: Pot = Depends(owned_pot),
    db: AsyncSession = Depends(get_db),
    bucket: Literal["5m", "1h", "1d"] = Query("1h"),
    hours: int = Query(24, ge=1, le=24 * 90),
):
    """Bucketed time series.

    Aggregation happens in SQL, not Python: a 90-day window at 60 s sampling is
    ~130k rows, and shipping those to the API process to average them would be
    both slow and pointless.

    On Postgres this targets Timescale's `time_bucket`; the SQLite path uses an
    epoch-division expression so local development produces the same shape.
    """
    if not pot.device_id:
        return S.SeriesOut(pot_id=pot.id, bucket=bucket, points=[])

    since = datetime.now(timezone.utc) - timedelta(hours=hours)
    width = BUCKETS[bucket]
    seconds = int(width.total_seconds())

    dialect = db.bind.dialect.name if db.bind else "sqlite"

    if dialect == "postgresql":
        bucket_expr = func.time_bucket(width, Reading.time).label("bucket")
    else:
        # SQLite: floor(epoch / width) * width. Two casts are needed --
        # `strftime('%s')` yields a string, and SQLite's `/` returns a float,
        # so without flooring the quotient this multiplies straight back to
        # the original timestamp and every row becomes its own bucket.
        epoch = cast(func.strftime("%s", Reading.time), Integer)
        bucket_expr = (cast(epoch / seconds, Integer) * seconds).label("bucket")

    stmt = (
        select(
            bucket_expr,
            func.avg(Reading.temp_c).label("temp_c"),
            func.avg(Reading.rh).label("rh"),
            func.avg(Reading.soil_pct).label("soil_pct"),
            func.avg(Reading.lux).label("lux"),
            func.count().label("samples"),
        )
        .where(Reading.device_id == pot.device_id, Reading.time >= since)
        .group_by(bucket_expr)
        .order_by(bucket_expr)
    )

    rows = (await db.execute(stmt)).all()

    points = []
    for row in rows:
        raw_bucket = row.bucket
        if isinstance(raw_bucket, (int, float)):
            ts = datetime.fromtimestamp(raw_bucket, tz=timezone.utc)
        elif isinstance(raw_bucket, str):
            ts = datetime.fromisoformat(raw_bucket).replace(tzinfo=timezone.utc)
        else:
            ts = raw_bucket
        points.append(S.SeriesPoint(
            bucket=ts,
            temp_c=round(row.temp_c, 2) if row.temp_c is not None else None,
            rh=round(row.rh, 2) if row.rh is not None else None,
            soil_pct=round(row.soil_pct, 2) if row.soil_pct is not None else None,
            lux=round(row.lux, 1) if row.lux is not None else None,
            samples=row.samples,
        ))

    return S.SeriesOut(pot_id=pot.id, bucket=bucket, points=points)


@router.get("/{pot_id}/health", response_model=S.HealthOut)
async def get_health(
    pot: Pot = Depends(owned_pot),
    db: AsyncSession = Depends(get_db),
):
    reading_dict: dict = {}
    if pot.device_id:
        result = await db.execute(
            select(Reading)
            .where(Reading.device_id == pot.device_id)
            .order_by(Reading.time.desc())
            .limit(1)
        )
        row = result.scalar_one_or_none()
        if row:
            reading_dict = {
                "temp_c": row.temp_c, "rh": row.rh,
                "soil_pct": row.soil_pct, "lux": row.lux,
            }

    return care_engine.assess(
        reading_dict,
        pot.species.scientific_name if pot.species else None,
        pot.species.care_profile if pot.species else None,
    )
