"""HTTP ingest — the transport that lets the backend live on a free tier.

Weighted toward device authentication and the command downlink. Those are the
two things MQTT used to provide and that this endpoint now has to get right on
its own.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select

from app.db.models import Command, Device, Reading
from app.db.session import get_sessionmaker

pytestmark = pytest.mark.asyncio


@pytest.fixture
async def claimed(client, seeded_device):
    """A claimed device plus its one-time secret."""
    r = await client.post(
        "/v1/devices/claim",
        json={"claim_code": "TEST-CODE"},
        headers={"X-Dev-User": "alice"},
    )
    body = r.json()
    return body["device_id"], body["mqtt_password"], body["pot_id"]


def auth(secret: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {secret}"}


class TestDeviceAuth:
    async def test_valid_secret_accepted(self, client, claimed):
        device_id, secret, _ = claimed
        r = await client.post(
            "/v1/ingest/telemetry",
            json={"device_id": device_id, "samples": []},
            headers=auth(secret),
        )
        assert r.status_code == 200

    async def test_missing_header_rejected(self, client, claimed):
        device_id, _, _ = claimed
        r = await client.post(
            "/v1/ingest/telemetry",
            json={"device_id": device_id, "samples": []},
        )
        assert r.status_code == 401

    async def test_wrong_secret_rejected(self, client, claimed):
        device_id, _, _ = claimed
        r = await client.post(
            "/v1/ingest/telemetry",
            json={"device_id": device_id, "samples": []},
            headers=auth("not-the-secret"),
        )
        assert r.status_code == 401

    async def test_unknown_device_and_bad_secret_are_indistinguishable(
        self, client, claimed
    ):
        """Both 401 with the same body.

        Different responses would let an attacker enumerate which device ids
        exist by probing with a junk secret.
        """
        _, secret, _ = claimed

        unknown = await client.post(
            "/v1/ingest/telemetry",
            json={"device_id": "no-such-device", "samples": []},
            headers=auth(secret),
        )
        bad_secret = await client.post(
            "/v1/ingest/telemetry",
            json={"device_id": "testdev01", "samples": []},
            headers=auth("wrong"),
        )
        assert unknown.status_code == bad_secret.status_code == 401
        assert unknown.json() == bad_secret.json()

    async def test_unclaimed_device_rejected(self, client, seeded_device):
        """No secret exists until the device is claimed."""
        r = await client.post(
            "/v1/ingest/telemetry",
            json={"device_id": seeded_device, "samples": []},
            headers=auth("anything"),
        )
        assert r.status_code == 401


class TestIngest:
    async def test_samples_stored(self, client, claimed):
        device_id, secret, _ = claimed
        now = int(datetime.now(timezone.utc).timestamp())

        r = await client.post(
            "/v1/ingest/telemetry",
            json={
                "device_id": device_id,
                "samples": [
                    {"ts": now, "temp_c": 21.5, "rh": 50.0, "soil_pct": 42.0},
                    {"ts": now - 60, "temp_c": 21.4, "rh": 50.1, "soil_pct": 42.5},
                ],
            },
            headers=auth(secret),
        )
        assert r.status_code == 200
        assert r.json()["accepted"] == 2

        async with get_sessionmaker()() as db:
            rows = (await db.execute(select(Reading))).scalars().all()
        assert len(rows) == 2

    async def test_implausible_values_nulled_not_dropped(self, client, claimed):
        device_id, secret, _ = claimed
        now = int(datetime.now(timezone.utc).timestamp())

        r = await client.post(
            "/v1/ingest/telemetry",
            json={"device_id": device_id,
                  "samples": [{"ts": now, "temp_c": -3000.0, "rh": 50.0}]},
            headers=auth(secret),
        )
        assert r.json()["accepted"] == 1

        async with get_sessionmaker()() as db:
            row = (await db.execute(select(Reading))).scalar_one()
        assert row.temp_c is None      # implausible field discarded
        assert row.rh == 50.0          # the rest of the row survives

    async def test_epoch_zero_rejected(self, client, claimed):
        """An unsynced clock must not write 1970 into the table."""
        device_id, secret, _ = claimed
        r = await client.post(
            "/v1/ingest/telemetry",
            json={"device_id": device_id, "samples": [{"ts": 0, "temp_c": 21.0}]},
            headers=auth(secret),
        )
        assert r.json() == {**r.json(), "accepted": 0, "rejected": 1}

    async def test_null_ts_uses_arrival_time(self, client, claimed):
        """Contract: a device without SNTP sends null rather than guessing."""
        device_id, secret, _ = claimed
        r = await client.post(
            "/v1/ingest/telemetry",
            json={"device_id": device_id,
                  "samples": [{"ts": None, "temp_c": 21.0}]},
            headers=auth(secret),
        )
        assert r.json()["accepted"] == 1

    async def test_marks_device_online(self, client, claimed):
        device_id, secret, _ = claimed
        await client.post(
            "/v1/ingest/telemetry",
            json={"device_id": device_id, "samples": []},
            headers=auth(secret),
        )
        async with get_sessionmaker()() as db:
            assert (await db.get(Device, device_id)).online is True

    async def test_oversized_batch_rejected(self, client, claimed):
        device_id, secret, _ = claimed
        r = await client.post(
            "/v1/ingest/telemetry",
            json={"device_id": device_id,
                  "samples": [{"ts": None, "temp_c": 20.0}] * 200},
            headers=auth(secret),
        )
        assert r.status_code == 413

    async def test_server_time_returned(self, client, claimed):
        """Lets a device without SNTP still evaluate expires_at."""
        device_id, secret, _ = claimed
        r = await client.post(
            "/v1/ingest/telemetry",
            json={"device_id": device_id, "samples": []},
            headers=auth(secret),
        )
        assert abs(r.json()["server_time"]
                   - int(datetime.now(timezone.utc).timestamp())) < 10


class TestCommandDownlink:
    """The half that replaces MQTT's push."""

    async def test_pending_command_returned(self, client, claimed):
        device_id, secret, pot_id = claimed

        water = await client.post(
            f"/v1/pots/{pot_id}/water",
            json={"duration_s": 5},
            headers={"X-Dev-User": "alice"},
        )
        assert water.status_code == 202

        r = await client.post(
            "/v1/ingest/telemetry",
            json={"device_id": device_id, "samples": []},
            headers=auth(secret),
        )
        cmds = r.json()["commands"]
        assert len(cmds) == 1
        assert cmds[0]["op"] == "pump"
        assert cmds[0]["args"]["duration_s"] == 5
        assert cmds[0]["expires_at"] > 0

    async def test_command_not_resent_after_delivery(self, client, claimed):
        """Delivered once, not on every subsequent POST.

        Re-sending would water the plant repeatedly: the device may apply a
        command and lose power before acking, and a resend would run it again.
        """
        device_id, secret, pot_id = claimed
        await client.post(
            f"/v1/pots/{pot_id}/water",
            json={"duration_s": 5},
            headers={"X-Dev-User": "alice"},
        )

        first = await client.post(
            "/v1/ingest/telemetry",
            json={"device_id": device_id, "samples": []},
            headers=auth(secret),
        )
        assert len(first.json()["commands"]) == 1

        second = await client.post(
            "/v1/ingest/telemetry",
            json={"device_id": device_id, "samples": []},
            headers=auth(secret),
        )
        assert second.json()["commands"] == []

    async def test_expired_command_not_delivered(self, client, claimed):
        device_id, secret, _ = claimed

        async with get_sessionmaker()() as db:
            db.add(Command(
                device_id=device_id, op="pump", args={"duration_s": 5},
                expires_at=datetime.now(timezone.utc) - timedelta(minutes=1),
            ))
            await db.commit()

        r = await client.post(
            "/v1/ingest/telemetry",
            json={"device_id": device_id, "samples": []},
            headers=auth(secret),
        )
        assert r.json()["commands"] == []

    async def test_ack_updates_command(self, client, claimed):
        device_id, secret, pot_id = claimed
        w = await client.post(
            f"/v1/pots/{pot_id}/water",
            json={"duration_s": 5},
            headers={"X-Dev-User": "alice"},
        )
        cmd_id = w.json()["id"]

        r = await client.post(
            f"/v1/ingest/ack?device_id={device_id}",
            json={"id": cmd_id, "result": "ok"},
            headers=auth(secret),
        )
        assert r.status_code == 204

        async with get_sessionmaker()() as db:
            assert (await db.get(Command, cmd_id)).state == "acked"

    async def test_ack_rejection_records_reason(self, client, claimed):
        device_id, secret, pot_id = claimed
        w = await client.post(
            f"/v1/pots/{pot_id}/water",
            json={"duration_s": 5},
            headers={"X-Dev-User": "alice"},
        )
        cmd_id = w.json()["id"]

        await client.post(
            f"/v1/ingest/ack?device_id={device_id}",
            json={"id": cmd_id, "result": "rejected",
                  "error": "soil_already_wet"},
            headers=auth(secret),
        )
        async with get_sessionmaker()() as db:
            cmd = await db.get(Command, cmd_id)
        assert cmd.state == "rejected"
        assert cmd.error == "soil_already_wet"

    async def test_cannot_ack_another_devices_command(self, client, claimed):
        device_id, secret, pot_id = claimed
        w = await client.post(
            f"/v1/pots/{pot_id}/water",
            json={"duration_s": 5},
            headers={"X-Dev-User": "alice"},
        )
        cmd_id = w.json()["id"]

        async with get_sessionmaker()() as db:
            db.add(Device(id="other01", mqtt_secret_hash=None))
            await db.commit()

        r = await client.post(
            f"/v1/ingest/ack?device_id=other01",
            json={"id": cmd_id, "result": "ok"},
            headers=auth(secret),
        )
        # other01 has no secret, so it cannot authenticate at all.
        assert r.status_code == 401


class TestBootstrap:
    """The device's own credential path.

    Nothing wrote a secret to the pot before this existed: claim returned one
    to the app, which dropped it, and the firmware's NVS key was never used.
    The pot was on Wi-Fi and unable to authenticate at all.
    """

    async def test_valid_token_returns_a_working_secret(self, client, seeded_device):
        r = await client.post(
            "/v1/ingest/bootstrap",
            json={"device_id": seeded_device, "token": "TEST-CODE",
                  "fw_version": "1.1.0"},
        )
        assert r.status_code == 200
        secret = r.json()["secret"]
        assert secret

        # The secret is only meaningful if it authenticates telemetry.
        r = await client.post(
            "/v1/ingest/telemetry",
            json={"v": 1, "device_id": seeded_device, "samples": [{"temp_c": 21.0}]},
            headers=auth(secret),
        )
        assert r.status_code == 200
        assert r.json()["accepted"] == 1

    async def test_wrong_token_rejected(self, client, seeded_device):
        r = await client.post(
            "/v1/ingest/bootstrap",
            json={"device_id": seeded_device, "token": "NOPE-NOPE"},
        )
        assert r.status_code == 401

    async def test_token_belonging_to_another_device_rejected(
        self, client, seeded_device
    ):
        """A valid token must not authenticate a different device id."""
        r = await client.post(
            "/v1/ingest/bootstrap",
            json={"device_id": "someoneelse", "token": "TEST-CODE"},
        )
        assert r.status_code == 401

    async def test_does_not_create_unknown_devices(self, client, db_path):
        """Squatting guard: bootstrap authenticates, it does not register."""
        r = await client.post(
            "/v1/ingest/bootstrap",
            json={"device_id": "ghostdev", "token": "ANY-TOKEN"},
        )
        assert r.status_code == 401

        async with get_sessionmaker()() as db:
            assert await db.get(Device, "ghostdev") is None

    async def test_survives_being_claimed(self, client, seeded_device):
        """The bug this column exists for.

        Claiming consumes claim_code. When the device authenticated with that
        same value it could never re-bootstrap afterwards, so any pot whose
        owner had claimed it was permanently locked out.
        """
        await client.post(
            "/v1/devices/claim",
            json={"claim_code": "TEST-CODE"},
            headers={"X-Dev-User": "alice"},
        )

        r = await client.post(
            "/v1/ingest/bootstrap",
            json={"device_id": seeded_device, "token": "TEST-CODE"},
        )
        assert r.status_code == 200

    async def test_claim_does_not_invalidate_a_bootstrapped_secret(
        self, client, seeded_device
    ):
        """Order independence: the pot may bootstrap before its owner claims.

        Claim used to mint unconditionally, which would 401 a pot that was
        already reporting.
        """
        secret = (await client.post(
            "/v1/ingest/bootstrap",
            json={"device_id": seeded_device, "token": "TEST-CODE"},
        )).json()["secret"]

        await client.post(
            "/v1/devices/claim",
            json={"claim_code": "TEST-CODE"},
            headers={"X-Dev-User": "alice"},
        )

        r = await client.post(
            "/v1/ingest/telemetry",
            json={"v": 1, "device_id": seeded_device, "samples": [{"temp_c": 20.0}]},
            headers=auth(secret),
        )
        assert r.status_code == 200

    async def test_rebootstrap_invalidates_the_old_secret(self, client, seeded_device):
        """Self-healing has a cost: only the newest secret works."""
        first = (await client.post(
            "/v1/ingest/bootstrap",
            json={"device_id": seeded_device, "token": "TEST-CODE"},
        )).json()["secret"]
        second = (await client.post(
            "/v1/ingest/bootstrap",
            json={"device_id": seeded_device, "token": "TEST-CODE"},
        )).json()["secret"]

        assert first != second
        body = {"v": 1, "device_id": seeded_device, "samples": [{"temp_c": 20.0}]}
        assert (await client.post("/v1/ingest/telemetry", json=body,
                                  headers=auth(first))).status_code == 401
        assert (await client.post("/v1/ingest/telemetry", json=body,
                                  headers=auth(second))).status_code == 200

    async def test_records_reported_firmware_version(self, client, seeded_device):
        await client.post(
            "/v1/ingest/bootstrap",
            json={"device_id": seeded_device, "token": "TEST-CODE",
                  "fw_version": "9.9.9"},
        )
        async with get_sessionmaker()() as db:
            assert (await db.get(Device, seeded_device)).fw_version == "9.9.9"
