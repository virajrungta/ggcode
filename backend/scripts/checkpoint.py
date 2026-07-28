"""Checkpoint seed: makes the API demoable end-to-end with no hardware.

Creates a claimable device, claims it, and backfills 48h of realistic sensor
history so the charts and health engine have something to chew on.

    cd backend && .venv/bin/python scripts/checkpoint.py

Then browse http://localhost:8000/docs after starting the server.
"""

from __future__ import annotations

import asyncio
import math
import os
import random
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

os.environ.setdefault("GG_AUTH_MODE", "dev")
os.environ.setdefault("GG_ENV", "development")
os.environ.setdefault("GG_DATABASE_URL", "sqlite+aiosqlite:///./greengenius.db")

from app.db.models import Base, Device, PlantSpecies, Pot, Reading, User  # noqa: E402
from app.db.session import get_engine, get_sessionmaker  # noqa: E402

DEVICE_ID = "sim-checkpoint"
CLAIM_CODE = "DEMO-1234"


def synth_history(device_id: str, hours: int = 48) -> list[Reading]:
    """Physically-plausible history: soil dries then jumps on watering, light
    follows a diurnal cycle, temperature lags light. Uniform noise would make
    the charts look fine and tell you nothing about whether they work."""
    rows: list[Reading] = []
    now = datetime.now(timezone.utc)
    soil = 62.0
    temp = 21.0

    for i in range(hours * 12):  # every 5 minutes
        ts = now - timedelta(minutes=5 * (hours * 12 - i))
        hour = ts.hour + ts.minute / 60
        daylight = max(0.0, math.sin((hour - 6) / 12 * math.pi))

        soil -= 0.09 * (0.5 + daylight) * random.uniform(0.85, 1.15)
        if soil < 24:
            soil += random.uniform(32, 40)  # watering event

        target = 18 + daylight * 7
        temp += (target - temp) * 0.06 + random.uniform(-0.1, 0.1)

        rows.append(Reading(
            time=ts,
            device_id=device_id,
            temp_c=round(temp, 2),
            rh=round(max(25.0, min(92.0, 68 - daylight * 18 + random.uniform(-3, 3))), 1),
            soil_pct=round(max(0.0, min(100.0, soil)), 1),
            lux=round(daylight * 11000 * random.uniform(0.85, 1.15), 1),
            batt_mv=random.randint(3900, 4100),
            flags=0b00110000,
        ))
    return rows


async def main() -> None:
    async with get_engine().begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with get_sessionmaker()() as db:
        existing = await db.get(Device, DEVICE_ID)
        if existing:
            print(f"'{DEVICE_ID}' already seeded — delete greengenius.db to reset.")
            return

        user = User(firebase_uid="dev-user", email="dev-user@dev.local",
                    display_name="dev-user")
        db.add(user)
        await db.flush()

        device = Device(
            id=DEVICE_ID, model="GG-POT-1", fw_version="sim-1.0.0",
            claim_code=CLAIM_CODE,
            claim_code_expires_at=datetime.now(timezone.utc) + timedelta(days=365),
        )
        db.add(device)

        species = PlantSpecies(
            scientific_name="Monstera deliciosa", common_name="Swiss cheese plant",
            genus="Monstera", source="curated",
        )
        db.add(species)
        await db.flush()

        pot = Pot(user_id=user.id, device_id=DEVICE_ID, name="Living Room Monstera",
                  species_id=species.id, identify_confidence=94.2)
        db.add(pot)

        rows = synth_history(DEVICE_ID)
        db.add_all(rows)
        device.online = True
        device.last_seen_at = datetime.now(timezone.utc)

        await db.commit()
        pot_id = pot.id

    print(f"""
Seeded.

  pot_id      {pot_id}
  device_id   {DEVICE_ID}
  claim_code  {CLAIM_CODE}   (unclaimed second device? re-run after deleting the db)
  readings    {len(rows)} rows over 48h

Start the API:
  .venv/bin/uvicorn app.main:app --reload

Then:
  curl -s -H 'X-Dev-User: dev-user' localhost:8000/v1/pots | python3 -m json.tool
  curl -s -H 'X-Dev-User: dev-user' localhost:8000/v1/pots/{pot_id}/latest | python3 -m json.tool
  curl -s -H 'X-Dev-User: dev-user' 'localhost:8000/v1/pots/{pot_id}/readings?bucket=1h&hours=48' | python3 -m json.tool
  curl -s -H 'X-Dev-User: dev-user' localhost:8000/v1/pots/{pot_id}/health | python3 -m json.tool

Ownership check (must be 404 — this is the security boundary):
  curl -s -o /dev/null -w '%{{http_code}}\\n' -H 'X-Dev-User: mallory' localhost:8000/v1/pots/{pot_id}
""")


if __name__ == "__main__":
    asyncio.run(main())
