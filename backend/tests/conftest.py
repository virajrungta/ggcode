from __future__ import annotations

import os
import tempfile
from pathlib import Path

import pytest
import pytest_asyncio

# Must be set before any app module reads settings.
os.environ.update(
    GG_ENV="development",
    GG_AUTH_MODE="dev",
    GG_MQTT_HOST="localhost",
    GG_SIMULATE="0",
)


@pytest.fixture(scope="function")
def db_path():
    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    yield path
    Path(path).unlink(missing_ok=True)


@pytest_asyncio.fixture(scope="function")
async def client(db_path):
    """An httpx client bound to a fresh SQLite database per test."""
    os.environ["GG_DATABASE_URL"] = f"sqlite+aiosqlite:///{db_path}"

    from app.core.config import get_settings
    from app.db import session as session_module

    get_settings.cache_clear()
    await session_module.reset_engine()

    from app.db.models import Base
    from app.main import create_app
    from app.workers.ingest import reset_throttle

    reset_throttle()
    app = create_app()

    async with session_module.get_engine().begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    import httpx

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        yield c

    await session_module.reset_engine()
    get_settings.cache_clear()


def as_user(uid: str) -> dict[str, str]:
    """Headers identifying a caller under GG_AUTH_MODE=dev."""
    return {"X-Dev-User": uid}


@pytest_asyncio.fixture
async def alice(client):
    return as_user("alice")


@pytest_asyncio.fixture
async def bob(client):
    return as_user("bob")


@pytest_asyncio.fixture
async def seeded_device(db_path):
    """An unclaimed device with a valid claim code."""
    from datetime import datetime, timedelta, timezone

    from app.db.models import Device
    from app.db.session import get_sessionmaker

    async with get_sessionmaker()() as db:
        device = Device(
            id="testdev01",
            model="GG-POT-1",
            fw_version="1.0.0",
            claim_code="TEST-CODE",
            bootstrap_token="TEST-CODE",
            claim_code_expires_at=datetime.now(timezone.utc) + timedelta(minutes=15),
        )
        db.add(device)
        await db.commit()
    return "testdev01"
