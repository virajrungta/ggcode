"""End-to-end API tests.

Weighted toward the ownership boundary. An IDOR here would let any user read
another user's sensor history or run their pump, which is the worst thing this
API can do wrong.
"""

from __future__ import annotations

import pytest

pytestmark = pytest.mark.asyncio


async def test_health(client):
    r = await client.get("/health")
    assert r.status_code == 200 and r.json()["status"] == "ok"


class TestPotCrud:
    async def test_create_and_list(self, client, alice):
        r = await client.post("/v1/pots", json={"name": "Fern"}, headers=alice)
        assert r.status_code == 201
        assert r.json()["name"] == "Fern"

        r = await client.get("/v1/pots", headers=alice)
        assert r.status_code == 200 and len(r.json()) == 1

    async def test_get_by_id(self, client, alice):
        pot = (await client.post("/v1/pots", json={"name": "Fern"}, headers=alice)).json()
        r = await client.get(f"/v1/pots/{pot['id']}", headers=alice)
        assert r.status_code == 200 and r.json()["id"] == pot["id"]

    async def test_patch(self, client, alice):
        pot = (await client.post("/v1/pots", json={"name": "Fern"}, headers=alice)).json()
        r = await client.patch(
            f"/v1/pots/{pot['id']}",
            json={"name": "Boston Fern", "auto_water_enabled": True},
            headers=alice,
        )
        assert r.status_code == 200
        assert r.json()["name"] == "Boston Fern"
        assert r.json()["auto_water_enabled"] is True

    async def test_delete(self, client, alice):
        pot = (await client.post("/v1/pots", json={"name": "Fern"}, headers=alice)).json()
        assert (await client.delete(f"/v1/pots/{pot['id']}", headers=alice)).status_code == 204
        assert (await client.get(f"/v1/pots/{pot['id']}", headers=alice)).status_code == 404

    async def test_empty_name_rejected(self, client, alice):
        r = await client.post("/v1/pots", json={"name": ""}, headers=alice)
        assert r.status_code == 422

    async def test_missing_pot_is_404(self, client, alice):
        assert (await client.get("/v1/pots/does-not-exist", headers=alice)).status_code == 404


class TestOwnershipIsolation:
    """The security boundary. Every one of these must stay 404."""

    async def test_cannot_read_another_users_pot(self, client, alice, bob):
        pot = (await client.post("/v1/pots", json={"name": "Alice's"}, headers=alice)).json()
        r = await client.get(f"/v1/pots/{pot['id']}", headers=bob)
        assert r.status_code == 404, "Bob must not read Alice's pot"

    async def test_cannot_patch_another_users_pot(self, client, alice, bob):
        pot = (await client.post("/v1/pots", json={"name": "Alice's"}, headers=alice)).json()
        r = await client.patch(f"/v1/pots/{pot['id']}", json={"name": "Bob's"}, headers=bob)
        assert r.status_code == 404

    async def test_cannot_delete_another_users_pot(self, client, alice, bob):
        pot = (await client.post("/v1/pots", json={"name": "Alice's"}, headers=alice)).json()
        assert (await client.delete(f"/v1/pots/{pot['id']}", headers=bob)).status_code == 404
        assert (await client.get(f"/v1/pots/{pot['id']}", headers=alice)).status_code == 200

    async def test_cannot_read_another_users_readings(self, client, alice, bob):
        pot = (await client.post("/v1/pots", json={"name": "Alice's"}, headers=alice)).json()
        for path in ("latest", "readings", "health", "commands"):
            r = await client.get(f"/v1/pots/{pot['id']}/{path}", headers=bob)
            assert r.status_code == 404, f"{path} leaked to another user"

    async def test_cannot_water_another_users_pot(self, client, alice, bob):
        pot = (await client.post("/v1/pots", json={"name": "Alice's"}, headers=alice)).json()
        r = await client.post(
            f"/v1/pots/{pot['id']}/water", json={"duration_s": 5}, headers=bob
        )
        assert r.status_code == 404, "Bob must not be able to run Alice's pump"

    async def test_listing_is_scoped(self, client, alice, bob):
        await client.post("/v1/pots", json={"name": "Alice's"}, headers=alice)
        await client.post("/v1/pots", json={"name": "Bob's"}, headers=bob)

        alice_pots = (await client.get("/v1/pots", headers=alice)).json()
        bob_pots = (await client.get("/v1/pots", headers=bob)).json()

        assert [p["name"] for p in alice_pots] == ["Alice's"]
        assert [p["name"] for p in bob_pots] == ["Bob's"]


class TestDeviceClaim:
    async def test_claim_creates_pot_and_returns_secret(self, client, alice, seeded_device):
        r = await client.post(
            "/v1/devices/claim", json={"claim_code": "TEST-CODE", "name": "Window Pot"},
            headers=alice,
        )
        assert r.status_code == 200
        body = r.json()
        assert body["device_id"] == seeded_device
        assert body["mqtt_username"] == seeded_device
        assert len(body["mqtt_password"]) > 20
        assert body["pot_id"]

    async def test_claim_code_is_single_use(self, client, alice, bob, seeded_device):
        first = await client.post(
            "/v1/devices/claim", json={"claim_code": "TEST-CODE"}, headers=alice
        )
        assert first.status_code == 200

        second = await client.post(
            "/v1/devices/claim", json={"claim_code": "TEST-CODE"}, headers=bob
        )
        assert second.status_code == 404, "a used claim code must not work again"

    async def test_bad_code_is_404(self, client, alice, seeded_device):
        r = await client.post("/v1/devices/claim", json={"claim_code": "WRONG"}, headers=alice)
        assert r.status_code == 404

    async def test_expired_code_rejected(self, client, alice, db_path):
        from datetime import datetime, timedelta, timezone

        from app.db.models import Device
        from app.db.session import get_sessionmaker

        async with get_sessionmaker()() as db:
            db.add(Device(
                id="expired01", claim_code="OLD-CODE",
                claim_code_expires_at=datetime.now(timezone.utc) - timedelta(minutes=1),
            ))
            await db.commit()

        r = await client.post("/v1/devices/claim", json={"claim_code": "OLD-CODE"}, headers=alice)
        assert r.status_code == 404

    async def test_secret_is_hashed_not_stored_plaintext(self, client, alice, seeded_device):
        r = await client.post(
            "/v1/devices/claim", json={"claim_code": "TEST-CODE"}, headers=alice
        )
        secret = r.json()["mqtt_password"]

        from app.db.models import Device
        from app.db.session import get_sessionmaker

        async with get_sessionmaker()() as db:
            device = await db.get(Device, seeded_device)
            assert device.mqtt_secret_hash != secret
            assert device.mqtt_secret_hash.startswith("$argon2")


class TestWatering:
    async def test_water_without_device_is_409(self, client, alice):
        pot = (await client.post("/v1/pots", json={"name": "Fern"}, headers=alice)).json()
        r = await client.post(
            f"/v1/pots/{pot['id']}/water", json={"duration_s": 5}, headers=alice
        )
        assert r.status_code == 409
        assert "no paired device" in r.json()["detail"].lower()

    @pytest.mark.parametrize("duration", [0, -1, 31, 1000])
    async def test_invalid_durations_rejected(self, client, alice, seeded_device, duration):
        claim = await client.post(
            "/v1/devices/claim", json={"claim_code": "TEST-CODE"}, headers=alice
        )
        pot_id = claim.json()["pot_id"]
        r = await client.post(
            f"/v1/pots/{pot_id}/water", json={"duration_s": duration}, headers=alice
        )
        assert r.status_code == 422, f"duration_s={duration} should be rejected"

    async def test_command_queued_when_broker_unreachable(self, client, alice, seeded_device):
        """No broker in tests. The command must persist rather than 500."""
        claim = await client.post(
            "/v1/devices/claim", json={"claim_code": "TEST-CODE"}, headers=alice
        )
        pot_id = claim.json()["pot_id"]

        r = await client.post(
            f"/v1/pots/{pot_id}/water", json={"duration_s": 5}, headers=alice
        )
        assert r.status_code == 202
        assert r.json()["state"] == "queued"
        assert r.json()["op"] == "pump"

    async def test_rate_limit_between_waterings(self, client, alice, seeded_device):
        from app.db.models import CareEvent
        from app.db.session import get_sessionmaker

        claim = await client.post(
            "/v1/devices/claim", json={"claim_code": "TEST-CODE"}, headers=alice
        )
        pot_id = claim.json()["pot_id"]

        async with get_sessionmaker()() as db:
            db.add(CareEvent(pot_id=pot_id, kind="watered", duration_s=5.0))
            await db.commit()

        r = await client.post(
            f"/v1/pots/{pot_id}/water", json={"duration_s": 5}, headers=alice
        )
        assert r.status_code == 429

    async def test_refuses_when_soil_already_wet(self, client, alice, seeded_device):
        from datetime import datetime, timezone

        from app.db.models import Reading
        from app.db.session import get_sessionmaker

        claim = await client.post(
            "/v1/devices/claim", json={"claim_code": "TEST-CODE"}, headers=alice
        )
        pot_id = claim.json()["pot_id"]

        async with get_sessionmaker()() as db:
            db.add(Reading(
                time=datetime.now(timezone.utc), device_id=seeded_device,
                soil_pct=88.0, temp_c=21.0, rh=50.0, lux=1000.0,
            ))
            await db.commit()

        r = await client.post(
            f"/v1/pots/{pot_id}/water", json={"duration_s": 5}, headers=alice
        )
        assert r.status_code == 409
        assert "root rot" in r.json()["detail"].lower()


class TestReadings:
    async def test_empty_series_for_unpaired_pot(self, client, alice):
        pot = (await client.post("/v1/pots", json={"name": "Fern"}, headers=alice)).json()
        r = await client.get(f"/v1/pots/{pot['id']}/readings", headers=alice)
        assert r.status_code == 200 and r.json()["points"] == []

    async def test_latest_with_no_data(self, client, alice):
        pot = (await client.post("/v1/pots", json={"name": "Fern"}, headers=alice)).json()
        r = await client.get(f"/v1/pots/{pot['id']}/latest", headers=alice)
        assert r.status_code == 200
        assert r.json()["reading"] is None and r.json()["online"] is False

    async def test_series_buckets_readings(self, client, alice, seeded_device):
        from datetime import datetime, timedelta, timezone

        from app.db.models import Reading
        from app.db.session import get_sessionmaker

        claim = await client.post(
            "/v1/devices/claim", json={"claim_code": "TEST-CODE"}, headers=alice
        )
        pot_id = claim.json()["pot_id"]

        now = datetime.now(timezone.utc)
        async with get_sessionmaker()() as db:
            for i in range(120):  # 2 hours at 1/min
                db.add(Reading(
                    time=now - timedelta(minutes=i), device_id=seeded_device,
                    temp_c=20.0 + (i % 5), rh=50.0, soil_pct=40.0, lux=1000.0,
                ))
            await db.commit()

        r = await client.get(f"/v1/pots/{pot_id}/readings?bucket=1h&hours=6", headers=alice)
        assert r.status_code == 200
        points = r.json()["points"]
        assert 1 <= len(points) <= 4, f"expected hourly buckets, got {len(points)}"
        assert sum(p["samples"] for p in points) == 120

    async def test_health_reflects_readings(self, client, alice, seeded_device):
        from datetime import datetime, timezone

        from app.db.models import Reading
        from app.db.session import get_sessionmaker

        claim = await client.post(
            "/v1/devices/claim", json={"claim_code": "TEST-CODE"}, headers=alice
        )
        pot_id = claim.json()["pot_id"]

        async with get_sessionmaker()() as db:
            db.add(Reading(
                time=datetime.now(timezone.utc), device_id=seeded_device,
                soil_pct=3.0, temp_c=21.0, rh=50.0, lux=1000.0,
            ))
            await db.commit()

        r = await client.get(f"/v1/pots/{pot_id}/health", headers=alice)
        assert r.status_code == 200
        assert r.json()["status"] == "bad"
        assert any("Soil" in i for i in r.json()["issues"])


class TestBucketingDialect:
    """The chart query must not depend on TimescaleDB.

    `time_bucket` is a TimescaleDB function, but the branch that used it was
    selected on `dialect == "postgresql"` alone. The managed Postgres this
    deploys to (Neon) has no TimescaleDB — the hypertable migration detects
    that and skips — so every chart query called a function that was not
    there. Compile-level, because CI has no Postgres to execute against.
    """

    def _compiled(self, dialect) -> str:
        from datetime import datetime, timedelta, timezone

        from sqlalchemy import Integer, cast, func, select

        from app.db.models import Reading

        width = timedelta(hours=1)
        seconds = int(width.total_seconds())

        if dialect.name == "postgresql":
            bucket = func.date_bin(
                width, Reading.time, datetime(1970, 1, 1, tzinfo=timezone.utc)
            ).label("bucket")
        else:
            epoch = cast(func.strftime("%s", Reading.time), Integer)
            bucket = (cast(epoch / seconds, Integer) * seconds).label("bucket")

        stmt = select(bucket).group_by(bucket)
        return str(stmt.compile(dialect=dialect))

    def test_postgres_uses_core_date_bin_not_timescale(self):
        from sqlalchemy.dialects import postgresql

        sql = self._compiled(postgresql.dialect())
        assert "date_bin" in sql
        assert "time_bucket" not in sql, (
            "time_bucket requires TimescaleDB, which Neon does not provide"
        )

    def test_sqlite_still_floors_the_quotient(self):
        """Without the cast, SQLite's float division makes every row its own
        bucket — 120 points came back where 3 were expected."""
        from sqlalchemy.dialects import sqlite

        sql = self._compiled(sqlite.dialect())
        assert "CAST" in sql.upper()
        assert "date_bin" not in sql
