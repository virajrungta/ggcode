"""Synthetic device for developing without hardware.

This is the deliberate replacement for the old `arduino_service.py`, which
returned `random.uniform()` values from the production `/status` endpoint with
nothing marking them as fake. The difference that matters:

  - it runs as a separate process, never inside a request handler;
  - it publishes over MQTT like a real pot, so it exercises the real ingest
    path rather than bypassing it;
  - it only starts when GG_SIMULATE=1, which Settings refuses in production;
  - its device ids are prefixed `sim-`, so simulated rows are identifiable in
    the database forever after.

    GG_SIMULATE=1 python -m app.workers.simulator

Physically-plausible dynamics rather than uniform noise: soil dries on an
exponential curve and jumps on watering, light follows a diurnal cycle,
temperature lags light. Charts built against uniform noise look fine and then
fall apart against real data.
"""

from __future__ import annotations

import asyncio
import json
import logging
import math
import random
from datetime import datetime, timezone

import aiomqtt

from app.core.config import get_settings
from app.services.mqtt import client_kwargs, topic

log = logging.getLogger("simulator")

SAMPLE_INTERVAL_S = 5.0     # faster than the real 60s so charts fill quickly
SAMPLES_PER_BATCH = 4


class SimulatedPot:
    def __init__(self, device_id: str, *, dry_rate: float = 0.4) -> None:
        self.device_id = device_id
        self.soil_pct = random.uniform(35, 55)
        self.dry_rate = dry_rate
        self.temp_c = 21.0
        self.uptime = 0
        self.pump_on = False

    def step(self, now: datetime) -> dict:
        # Diurnal light: peak at solar noon, dark at night.
        hour = now.hour + now.minute / 60
        daylight = max(0.0, math.sin((hour - 6) / 12 * math.pi))
        lux = round(daylight * 12000 * random.uniform(0.85, 1.15), 1)

        # Soil dries faster in brighter, warmer conditions.
        self.soil_pct -= self.dry_rate * (0.5 + daylight) * random.uniform(0.8, 1.2)

        # Auto-water at the dry threshold, as a real pot would.
        self.pump_on = False
        if self.soil_pct < 22:
            self.soil_pct += random.uniform(25, 35)
            self.pump_on = True
            log.info("%s: auto-watered -> %.1f%%", self.device_id, self.soil_pct)

        self.soil_pct = max(0.0, min(100.0, self.soil_pct))

        # Temperature lags light rather than tracking it instantly.
        target = 18 + daylight * 8
        self.temp_c += (target - self.temp_c) * 0.1 + random.uniform(-0.15, 0.15)

        rh = max(20.0, min(95.0, 70 - daylight * 20 + random.uniform(-3, 3)))
        self.uptime += int(SAMPLE_INTERVAL_S)

        return {
            "ts": int(now.timestamp()),
            "temp_c": round(self.temp_c, 2),
            "rh": round(rh, 1),
            "soil_pct": round(self.soil_pct, 1),
            "lux": lux,
            "batt_mv": random.randint(3900, 4100),
            "flags": 0b00110000 | (0b1 if self.pump_on else 0),
        }


async def run(device_ids: list[str] | None = None) -> None:
    settings = get_settings()
    if not settings.simulate:
        raise SystemExit("Refusing to run: set GG_SIMULATE=1 to enable the simulator")

    ids = device_ids or ["sim-thirsty01", "sim-steady02"]
    pots = [
        SimulatedPot(ids[0], dry_rate=1.2),   # dries fast, waters often
        *[SimulatedPot(i) for i in ids[1:]],
    ]
    log.info("simulating %d device(s): %s", len(pots), ", ".join(ids))

    async with aiomqtt.Client(**client_kwargs()) as client:
        for pot in pots:
            await client.publish(
                topic(pot.device_id, "status"),
                json.dumps({"online": True, "fw": "sim-1.0.0", "ts": int(datetime.now(timezone.utc).timestamp())}).encode(),
                qos=1, retain=True,
            )

        batches: dict[str, list[dict]] = {p.device_id: [] for p in pots}

        while True:
            now = datetime.now(timezone.utc)
            for pot in pots:
                batches[pot.device_id].append(pot.step(now))

                if len(batches[pot.device_id]) >= SAMPLES_PER_BATCH:
                    payload = {
                        "v": 1,
                        "device_id": pot.device_id,
                        "samples": batches[pot.device_id],
                    }
                    await client.publish(
                        topic(pot.device_id, "telemetry"),
                        json.dumps(payload).encode(), qos=1,
                    )
                    log.info("%s: published %d samples (soil %.1f%%)",
                             pot.device_id, len(batches[pot.device_id]), pot.soil_pct)
                    batches[pot.device_id] = []

            await asyncio.sleep(SAMPLE_INTERVAL_S)


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s"
    )
    asyncio.run(run())
