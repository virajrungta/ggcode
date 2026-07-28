"""MQTT ingest worker.

Subscribes to the fleet's telemetry, status, event, and ack topics and writes
to Postgres/Timescale. Implements the ingest rules in contracts/telemetry.md.

    python -m app.workers.ingest
"""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timedelta, timezone
from typing import Any

import aiomqtt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.db.models import Alert, CareEvent, Command, Device, Pot, Reading
from app.db.session import get_sessionmaker
from app.services.mqtt import TOPIC_PREFIX, client_kwargs
from app.services.telemetry_codec import clamp_sample

log = logging.getLogger("ingest")

# Clock-skew guard. A device whose SNTP sync failed can report 1970 or a date
# far in the future; either would corrupt every chart and continuous aggregate
# built over this table.
MAX_FUTURE_SKEW = timedelta(hours=24)
MAX_PAST_SKEW = timedelta(days=30)

# `devices.last_seen_at` would otherwise be written once per sample per device.
# Process-local by design: each ingest worker throttling independently is fine,
# since the point is to shed writes, not to coordinate them.
LAST_SEEN_THROTTLE = timedelta(minutes=1)
_last_seen_written: dict[str, datetime] = {}


def reset_throttle() -> None:
    """Clear the throttle cache. Called between tests, which would otherwise
    be order-dependent — a device touched by an earlier test stays throttled."""
    _last_seen_written.clear()


def _parse_ts(raw: Any, arrival: datetime) -> datetime | None:
    """Resolve a sample timestamp, falling back to arrival time.

    A device that has not completed SNTP sends `null` by contract; substituting
    arrival time is far better than storing an epoch-zero row.
    """
    if raw is None:
        return arrival
    try:
        ts = datetime.fromtimestamp(float(raw), tz=timezone.utc)
    except (TypeError, ValueError, OSError, OverflowError):
        return arrival

    if ts > arrival + MAX_FUTURE_SKEW or ts < arrival - MAX_PAST_SKEW:
        log.warning("rejecting sample with implausible ts %s (arrival %s)", ts, arrival)
        return None
    return ts


async def handle_telemetry(db: AsyncSession, device_id: str, payload: dict) -> int:
    arrival = datetime.now(timezone.utc)
    samples = payload.get("samples") or []
    if not isinstance(samples, list):
        log.warning("device %s sent non-list samples", device_id)
        return 0

    rows: list[Reading] = []
    for sample in samples:
        if not isinstance(sample, dict):
            continue
        ts = _parse_ts(sample.get("ts"), arrival)
        if ts is None:
            continue

        cleaned, rejected = clamp_sample(sample)
        if rejected:
            log.info("device %s: nulled implausible %s", device_id, ", ".join(rejected))

        rows.append(Reading(
            time=ts,
            device_id=device_id,
            temp_c=cleaned.get("temp_c"),
            rh=cleaned.get("rh"),
            soil_pct=cleaned.get("soil_pct"),
            lux=cleaned.get("lux"),
            batt_mv=cleaned.get("batt_mv"),
            flags=int(cleaned.get("flags") or 0),
        ))

    if not rows:
        return 0

    db.add_all(rows)

    now = datetime.now(timezone.utc)
    if now - _last_seen_written.get(device_id, datetime.min.replace(tzinfo=timezone.utc)) > LAST_SEEN_THROTTLE:
        device = await db.get(Device, device_id)
        if device:
            device.last_seen_at = now
            device.online = True
        _last_seen_written[device_id] = now

    await db.commit()
    return len(rows)


async def handle_status(db: AsyncSession, device_id: str, payload: dict) -> None:
    device = await db.get(Device, device_id)
    if device is None:
        log.warning("status from unknown device %s", device_id)
        return
    device.online = bool(payload.get("online"))
    if payload.get("fw"):
        device.fw_version = payload["fw"]
    if device.online:
        device.last_seen_at = datetime.now(timezone.utc)
    await db.commit()


async def handle_event(db: AsyncSession, device_id: str, payload: dict) -> None:
    kind = payload.get("kind")
    data = payload.get("data") or {}

    pot = (await db.execute(select(Pot).where(Pot.device_id == device_id))).scalar_one_or_none()
    if pot is None:
        return

    if kind == "pump_stopped":
        db.add(CareEvent(
            pot_id=pot.id, kind="watered",
            duration_s=data.get("duration_s"),
            source=data.get("source", "device"),
            note=f"reason={data.get('reason')}",
        ))

    elif kind == "reservoir_empty":
        db.add(Alert(
            pot_id=pot.id, kind="reservoir_empty", severity="warning",
            message="Water reservoir is empty. Refill to resume automatic watering.",
        ))

    elif kind == "sensor_fault":
        db.add(Alert(
            pot_id=pot.id, kind="sensor_fault", severity="warning",
            message=f"Sensor fault reported: {data.get('sensor', 'unknown')}",
        ))

    elif kind == "safety_tripped":
        # Surfaced rather than logged: a tripped interlock means the pot tried
        # to do something unsafe, and the user should know.
        db.add(Alert(
            pot_id=pot.id, kind="safety_tripped", severity="bad",
            message=f"Watering safety interlock tripped: {data.get('interlock', 'unknown')}",
        ))

    await db.commit()


async def handle_ack(db: AsyncSession, device_id: str, payload: dict) -> None:
    command_id = payload.get("id")
    if not command_id:
        return
    command = await db.get(Command, command_id)
    if command is None or command.device_id != device_id:
        log.warning("ack for unknown/mismatched command %s from %s", command_id, device_id)
        return

    result = payload.get("result", "ok")
    command.state = "acked" if result == "ok" else result
    command.result = result
    command.error = payload.get("error")
    command.acked_at = datetime.now(timezone.utc)
    await db.commit()


HANDLERS = {
    "telemetry": handle_telemetry,
    "status": handle_status,
    "event": handle_event,
}


async def dispatch(topic: str, raw: bytes) -> None:
    parts = topic.split("/")
    # gg/v1/{device_id}/{leaf...}
    if len(parts) < 4 or parts[0] != "gg" or parts[1] != "v1":
        return
    device_id = parts[2]
    leaf = "/".join(parts[3:])

    try:
        payload = json.loads(raw)
    except (ValueError, UnicodeDecodeError):
        log.warning("undecodable payload on %s", topic)
        return
    if not isinstance(payload, dict):
        return

    # The broker ACL restricts each device to its own prefix, but a payload
    # claiming a different device_id than the topic is still worth refusing.
    claimed = payload.get("device_id")
    if claimed and claimed != device_id:
        log.warning("device %s claimed to be %s - dropped", device_id, claimed)
        return

    async with get_sessionmaker()() as db:
        try:
            if leaf == "cmd/ack":
                await handle_ack(db, device_id, payload)
            elif leaf in HANDLERS:
                await HANDLERS[leaf](db, device_id, payload)
        except Exception:
            await db.rollback()
            log.exception("handler failed for %s", topic)


async def run() -> None:
    settings = get_settings()
    log.info("ingest worker connecting to %s:%s", settings.mqtt_host, settings.mqtt_port)

    backoff = 1.0
    while True:
        try:
            async with aiomqtt.Client(**client_kwargs()) as client:
                await client.subscribe(f"{TOPIC_PREFIX}/+/telemetry", qos=1)
                await client.subscribe(f"{TOPIC_PREFIX}/+/status", qos=1)
                await client.subscribe(f"{TOPIC_PREFIX}/+/event", qos=1)
                await client.subscribe(f"{TOPIC_PREFIX}/+/cmd/ack", qos=1)
                log.info("subscribed; awaiting messages")
                backoff = 1.0

                async for message in client.messages:
                    await dispatch(str(message.topic), message.payload)

        except aiomqtt.MqttError as exc:
            log.warning("broker connection lost (%s); retrying in %.0fs", exc, backoff)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 60.0)


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s"
    )
    asyncio.run(run())
