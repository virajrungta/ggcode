from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select

from app.db.models import Alert, CareEvent, Command, Device, Pot, Reading
from app.db.session import get_sessionmaker
from app.workers.ingest import (
    _parse_ts, dispatch, handle_event, handle_status, handle_telemetry,
)

pytestmark = pytest.mark.asyncio  # applies to async tests; sync ones below are unaffected


class TestParseTs:
    def test_none_falls_back_to_arrival(self):
        """Contract: a device without SNTP sync sends null rather than 1970."""
        arrival = datetime(2026, 7, 27, 12, 0, tzinfo=timezone.utc)
        assert _parse_ts(None, arrival) == arrival

    def test_valid_epoch(self):
        arrival = datetime(2026, 7, 27, 12, 0, tzinfo=timezone.utc)
        ts = arrival - timedelta(minutes=5)
        assert _parse_ts(ts.timestamp(), arrival) == ts

    def test_far_future_rejected(self):
        arrival = datetime(2026, 7, 27, 12, 0, tzinfo=timezone.utc)
        assert _parse_ts((arrival + timedelta(days=400)).timestamp(), arrival) is None

    def test_epoch_zero_rejected(self):
        """The unsynced-clock case that would wreck every chart."""
        arrival = datetime(2026, 7, 27, 12, 0, tzinfo=timezone.utc)
        assert _parse_ts(0, arrival) is None

    def test_garbage_falls_back(self):
        arrival = datetime(2026, 7, 27, 12, 0, tzinfo=timezone.utc)
        assert _parse_ts("not-a-number", arrival) == arrival


@pytest.fixture
async def device(client):
    async with get_sessionmaker()() as db:
        db.add(Device(id="dev01", model="GG-POT-1"))
        await db.commit()
    return "dev01"


class TestHandleTelemetry:
    async def test_inserts_samples(self, client, device):
        now = datetime.now(timezone.utc)
        payload = {"v": 1, "device_id": device, "samples": [
            {"ts": int(now.timestamp()), "temp_c": 21.5, "rh": 50.0,
             "soil_pct": 40.0, "lux": 1200.0, "batt_mv": 4000, "flags": 48},
        ]}
        async with get_sessionmaker()() as db:
            assert await handle_telemetry(db, device, payload) == 1

        async with get_sessionmaker()() as db:
            rows = (await db.execute(select(Reading))).scalars().all()
        assert len(rows) == 1 and rows[0].temp_c == 21.5

    async def test_implausible_values_nulled_not_dropped(self, client, device):
        """The row still lands — losing the timestamp entirely would leave a
        silent hole in the series. Only the bad field is discarded."""
        now = datetime.now(timezone.utc)
        payload = {"samples": [
            {"ts": int(now.timestamp()), "temp_c": -3000.0, "rh": 50.0, "soil_pct": 40.0},
        ]}
        async with get_sessionmaker()() as db:
            assert await handle_telemetry(db, device, payload) == 1

        async with get_sessionmaker()() as db:
            row = (await db.execute(select(Reading))).scalar_one()
        assert row.temp_c is None
        assert row.rh == 50.0

    async def test_skewed_samples_skipped(self, client, device):
        payload = {"samples": [
            {"ts": 0, "temp_c": 21.0},
            {"ts": int(datetime.now(timezone.utc).timestamp()), "temp_c": 22.0},
        ]}
        async with get_sessionmaker()() as db:
            assert await handle_telemetry(db, device, payload) == 1

    async def test_marks_device_online(self, client, device):
        payload = {"samples": [
            {"ts": int(datetime.now(timezone.utc).timestamp()), "temp_c": 21.0},
        ]}
        async with get_sessionmaker()() as db:
            await handle_telemetry(db, device, payload)

        async with get_sessionmaker()() as db:
            assert (await db.get(Device, device)).online is True

    async def test_malformed_samples_ignored(self, client, device):
        async with get_sessionmaker()() as db:
            assert await handle_telemetry(db, device, {"samples": "not-a-list"}) == 0
            assert await handle_telemetry(db, device, {"samples": [1, 2, 3]}) == 0
            assert await handle_telemetry(db, device, {}) == 0

    async def test_batch_insert(self, client, device):
        now = datetime.now(timezone.utc)
        samples = [
            {"ts": int((now - timedelta(minutes=i)).timestamp()), "temp_c": 20.0 + i}
            for i in range(12)
        ]
        async with get_sessionmaker()() as db:
            assert await handle_telemetry(db, device, {"samples": samples}) == 12


class TestHandleStatus:
    async def test_online_and_fw(self, client, device):
        async with get_sessionmaker()() as db:
            await handle_status(db, device, {"online": True, "fw": "1.2.3"})
        async with get_sessionmaker()() as db:
            d = await db.get(Device, device)
        assert d.online is True and d.fw_version == "1.2.3"

    async def test_lwt_marks_offline(self, client, device):
        async with get_sessionmaker()() as db:
            await handle_status(db, device, {"online": True})
        async with get_sessionmaker()() as db:
            await handle_status(db, device, {"online": False})
        async with get_sessionmaker()() as db:
            assert (await db.get(Device, device)).online is False

    async def test_unknown_device_ignored(self, client):
        async with get_sessionmaker()() as db:
            await handle_status(db, "ghost", {"online": True})  # must not raise


@pytest.fixture
async def paired_pot(client, device):
    async with get_sessionmaker()() as db:
        from app.db.models import User
        user = User(firebase_uid="u1", email="u@test")
        db.add(user)
        await db.flush()
        pot = Pot(user_id=user.id, device_id=device, name="Test")
        db.add(pot)
        await db.commit()
        return pot.id


class TestHandleEvent:
    async def test_pump_stopped_logs_care_event(self, client, device, paired_pot):
        async with get_sessionmaker()() as db:
            await handle_event(db, device, {
                "kind": "pump_stopped",
                "data": {"duration_s": 5.0, "reason": "completed"},
            })
        async with get_sessionmaker()() as db:
            events = (await db.execute(select(CareEvent))).scalars().all()
        assert len(events) == 1
        assert events[0].kind == "watered" and events[0].duration_s == 5.0

    async def test_reservoir_empty_raises_alert(self, client, device, paired_pot):
        async with get_sessionmaker()() as db:
            await handle_event(db, device, {"kind": "reservoir_empty", "data": {}})
        async with get_sessionmaker()() as db:
            alerts = (await db.execute(select(Alert))).scalars().all()
        assert len(alerts) == 1 and alerts[0].kind == "reservoir_empty"

    async def test_safety_trip_is_surfaced_as_bad(self, client, device, paired_pot):
        async with get_sessionmaker()() as db:
            await handle_event(db, device, {
                "kind": "safety_tripped", "data": {"interlock": "max_runtime"},
            })
        async with get_sessionmaker()() as db:
            alert = (await db.execute(select(Alert))).scalar_one()
        assert alert.severity == "bad" and "max_runtime" in alert.message

    async def test_event_for_unpaired_device_ignored(self, client, device):
        async with get_sessionmaker()() as db:
            await handle_event(db, device, {"kind": "reservoir_empty", "data": {}})


class TestDispatch:
    async def test_spoofed_device_id_dropped(self, client, device):
        """Topic says dev01, payload claims victim. Must be refused."""
        import json

        await dispatch(
            f"gg/v1/{device}/telemetry",
            json.dumps({
                "device_id": "victim-device",
                "samples": [{"ts": int(datetime.now(timezone.utc).timestamp()), "temp_c": 21.0}],
            }).encode(),
        )
        async with get_sessionmaker()() as db:
            assert (await db.execute(select(Reading))).scalars().all() == []

    async def test_undecodable_payload_ignored(self, client, device):
        await dispatch(f"gg/v1/{device}/telemetry", b"\xff\xfe not json")

    async def test_wrong_namespace_ignored(self, client, device):
        import json

        await dispatch("other/v1/dev01/telemetry", json.dumps({"samples": []}).encode())

    async def test_short_topic_ignored(self, client):
        await dispatch("gg/v1", b"{}")


class TestHandleAck:
    async def test_ack_marks_command(self, client, device):
        from app.workers.ingest import handle_ack

        async with get_sessionmaker()() as db:
            cmd = Command(
                device_id=device, op="pump", args={"duration_s": 5},
                expires_at=datetime.now(timezone.utc) + timedelta(minutes=3),
            )
            db.add(cmd)
            await db.commit()
            cmd_id = cmd.id

        async with get_sessionmaker()() as db:
            await handle_ack(db, device, {"id": cmd_id, "result": "ok"})

        async with get_sessionmaker()() as db:
            assert (await db.get(Command, cmd_id)).state == "acked"

    async def test_rejection_records_reason(self, client, device):
        from app.workers.ingest import handle_ack

        async with get_sessionmaker()() as db:
            cmd = Command(
                device_id=device, op="pump", args={},
                expires_at=datetime.now(timezone.utc) + timedelta(minutes=3),
            )
            db.add(cmd)
            await db.commit()
            cmd_id = cmd.id

        async with get_sessionmaker()() as db:
            await handle_ack(db, device, {
                "id": cmd_id, "result": "rejected", "error": "soil_already_wet",
            })

        async with get_sessionmaker()() as db:
            cmd = await db.get(Command, cmd_id)
        assert cmd.state == "rejected" and cmd.error == "soil_already_wet"

    async def test_ack_from_wrong_device_ignored(self, client, device):
        """A pot must not be able to ack another pot's command."""
        from app.workers.ingest import handle_ack

        async with get_sessionmaker()() as db:
            db.add(Device(id="other01"))
            cmd = Command(
                device_id=device, op="pump", args={},
                expires_at=datetime.now(timezone.utc) + timedelta(minutes=3),
            )
            db.add(cmd)
            await db.commit()
            cmd_id = cmd.id

        async with get_sessionmaker()() as db:
            await handle_ack(db, "other01", {"id": cmd_id, "result": "ok"})

        async with get_sessionmaker()() as db:
            assert (await db.get(Command, cmd_id)).state == "queued"
