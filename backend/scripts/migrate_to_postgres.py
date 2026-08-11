"""Copy the local SQLite database into a hosted Postgres.

    python scripts/migrate_to_postgres.py "postgresql+asyncpg://user:pw@host/db"

Without this, deploying starts from an empty database and every paired pot has
to be re-paired — including erasing the pot's NVS so it advertises again,
which is the fiddliest step in the whole flow.

Copies in dependency order so foreign keys resolve, and is safe to re-run:
rows that already exist are skipped rather than duplicated.

Run `alembic upgrade head` against the target first — this moves data, it does
not create schema.
"""

from __future__ import annotations

import asyncio
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

BACKEND = Path(__file__).resolve().parents[1]
os.environ.setdefault("GG_AUTH_MODE", "dev")
os.environ.setdefault("GG_ENV", "development")

from sqlalchemy import func, select  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine  # noqa: E402

from app.db.models import (  # noqa: E402
    Alert, CareEvent, Command, Device, PlantSpecies, Pot, Reading, User,
)

# Order matters: users before pots, devices before pots, species before pots.
# Readings reference devices. Getting this wrong surfaces as a foreign-key
# violation halfway through, with a partially populated database.
ORDER = [User, Device, PlantSpecies, Pot, Reading, Command, CareEvent, Alert]


def primary_key(model, row):
    """Composite for Reading (time, device_id); `id` for everything else."""
    if model is Reading:
        return (row.time, row.device_id)
    return row.id


async def main(target_url: str) -> int:
    source_url = f"sqlite+aiosqlite:///{BACKEND / 'greengenius.db'}"

    if not (BACKEND / "greengenius.db").exists():
        print(f"no source database at {BACKEND / 'greengenius.db'}")
        return 1
    if "sqlite" in target_url:
        print("target looks like SQLite; expected a Postgres URL")
        return 2

    src_engine = create_async_engine(source_url)
    dst_engine = create_async_engine(target_url)
    Src = async_sessionmaker(src_engine, expire_on_commit=False)
    Dst = async_sessionmaker(dst_engine, expire_on_commit=False)

    total_copied = 0

    for model in ORDER:
        async with Src() as src, Dst() as dst:
            rows = (await src.execute(select(model))).scalars().all()
            if not rows:
                print(f"{model.__tablename__:16} 0 rows, skipped")
                continue

            existing = {
                primary_key(model, r)
                for r in (await dst.execute(select(model))).scalars().all()
            }

            copied = 0
            for row in rows:
                if primary_key(model, row) in existing:
                    continue
                # Detach from the source session before attaching to the
                # target; a row still bound to another session cannot be added.
                data = {
                    c.name: getattr(row, c.name) for c in model.__table__.columns
                }
                dst.add(model(**data))
                copied += 1

            await dst.commit()
            total_copied += copied
            print(f"{model.__tablename__:16} {copied} copied "
                  f"({len(rows) - copied} already present)")

    async with Dst() as dst:
        pots = (await dst.execute(select(func.count()).select_from(Pot))).scalar()
        readings = (await dst.execute(
            select(func.count()).select_from(Reading))).scalar()

    await src_engine.dispose()
    await dst_engine.dispose()

    print(f"\ncopied {total_copied} rows")
    print(f"target now holds {pots} pots and {readings} readings")
    print("\nThe per-device MQTT secret is a hash and cannot be re-derived, so")
    print("any paired pot keeps working for the app but must be re-claimed")
    print("before it can post telemetry with a new secret.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        raise SystemExit(2)
    raise SystemExit(asyncio.run(main(sys.argv[1])))
