"""Register a physical pot so it can be claimed.

    python scripts/register_device.py f42dc9bb9f88 M9JV-ZTGF [--release]

`--release` also unbinds the current owner, for handing the pot to a
different account. Without it an existing claim is left alone.

Fills a gap in the flow that only showed up with real hardware. The claim
endpoint looks up an existing `devices` row by claim code — it deliberately
does not create one, because an endpoint that mints devices on demand would
let anyone register any device id and then claim it.

In production this is a factory step: device ids and codes are written to the
database when boards are flashed. On a bench there is no factory, so this
script stands in.

The proper fix, once the firmware has an HTTP client: the pot self-registers
on first boot, POSTing its device id and claim code over TLS. It is already
on Wi-Fi, so the only missing piece is the request. Until then, run this.
"""

from __future__ import annotations

import asyncio
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

os.environ.setdefault("GG_AUTH_MODE", "dev")
os.environ.setdefault("GG_ENV", "development")
os.environ.setdefault(
    "GG_DATABASE_URL",
    f"sqlite+aiosqlite:///{Path(__file__).resolve().parents[1] / 'greengenius.db'}",
)

from app.db.models import Base, Device  # noqa: E402
from app.db.session import get_engine, get_sessionmaker  # noqa: E402


async def main(device_id: str, claim_code: str, release: bool) -> int:
    async with get_engine().begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with get_sessionmaker()() as db:
        device = await db.get(Device, device_id)

        if device is None:
            device = Device(id=device_id, model="GG-POT-1", hw_serial="ggpcb3")
            db.add(device)
            action = "registered"
        elif device.claimed_by and not release:
            action = "updated (claim kept; pass --release to unbind)"
        else:
            action = "updated"

        device.claim_code = claim_code
        # The device-facing twin. Claiming consumes claim_code, so without
        # this the pot could never authenticate after its owner claimed it.
        device.bootstrap_token = claim_code
        # Generous window: the code is read off a serial log by hand, and a
        # 15-minute production TTL just means re-running this script.
        device.claim_code_expires_at = datetime.now(timezone.utc) + timedelta(days=30)

        # Re-registering an already-claimed device clears the binding, so a
        # pot can be handed to a different account without a factory reset.
        # Opt-in, because the common reason to re-run this is to set a
        # bootstrap token on an existing pot, and unclaiming forces the owner
        # through the whole pairing flow again for no reason.
        if device.claimed_by and release:
            print(f"  note: was claimed by {device.claimed_by}; releasing it")
            device.claimed_by = None
            device.claimed_at = None
            device.mqtt_secret_hash = None

        await db.commit()

    print(f"{action} {device_id} with claim code {claim_code}")
    print("Now pair in the app and enter that code when asked.")
    print("The pot uses the same value to bootstrap its telemetry secret,")
    print("so it must match what the firmware persisted in NVS.")
    return 0


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 2:
        print(__doc__)
        raise SystemExit(2)
    raise SystemExit(asyncio.run(
        main(args[0], args[1], release="--release" in sys.argv)))
