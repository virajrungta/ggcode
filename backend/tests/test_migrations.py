"""Guards the migration chain against the models drifting away from it.

`app.main` calls `create_all` on SQLite for local convenience, which means a
model change works immediately in dev and only explodes on the first Postgres
deploy — where the schema is owned by Alembic. These tests close that gap:
the chain must build, round-trip, and produce exactly the model schema.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

BACKEND = Path(__file__).resolve().parents[1]
ALEMBIC = BACKEND / ".venv" / "bin" / "alembic"

pytestmark = pytest.mark.skipif(
    not ALEMBIC.exists(), reason="alembic not installed in .venv"
)


def run(*args: str, db: str) -> subprocess.CompletedProcess:
    env = {
        **os.environ,
        "GG_DATABASE_URL": f"sqlite+aiosqlite:///{db}",
        "GG_AUTH_MODE": "dev",
        "GG_ENV": "development",
    }
    return subprocess.run(
        [str(ALEMBIC), *args],
        cwd=BACKEND, env=env, capture_output=True, text=True,
    )


@pytest.fixture
def fresh_db():
    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    Path(path).unlink(missing_ok=True)  # let alembic create it
    yield path
    Path(path).unlink(missing_ok=True)


def test_upgrade_head_succeeds(fresh_db):
    result = run("upgrade", "head", db=fresh_db)
    assert result.returncode == 0, result.stderr


def test_no_drift_between_models_and_migrations(fresh_db):
    """The check that actually matters.

    `alembic check` autogenerates against the live schema and fails if it
    finds anything to do. A model field added without a migration fails here
    rather than on deploy.
    """
    assert run("upgrade", "head", db=fresh_db).returncode == 0

    result = run("check", db=fresh_db)
    assert result.returncode == 0, (
        "models and migrations have diverged — run:\n"
        "  .venv/bin/alembic revision --autogenerate -m 'describe change'\n\n"
        f"{result.stdout}\n{result.stderr}"
    )


def test_downgrade_to_base_and_back(fresh_db):
    assert run("upgrade", "head", db=fresh_db).returncode == 0

    down = run("downgrade", "base", db=fresh_db)
    assert down.returncode == 0, down.stderr

    up = run("upgrade", "head", db=fresh_db)
    assert up.returncode == 0, up.stderr


def test_expected_tables_exist(fresh_db):
    import sqlite3

    assert run("upgrade", "head", db=fresh_db).returncode == 0

    conn = sqlite3.connect(fresh_db)
    names = {r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'"
    )}
    conn.close()

    for table in [
        "users", "devices", "pots", "plant_species",
        "readings", "commands", "care_events", "alerts",
    ]:
        assert table in names, f"{table} missing after migration"


def test_timescale_migration_is_a_noop_on_sqlite(fresh_db):
    """The Postgres-only migration must not break the local dev chain.

    Guarded on the dialect rather than a config flag, so it cannot be run
    against SQLite by setting an env var wrong.

    Asserts on the resulting schema rather than on log output: the migration's
    own title contains the word "hypertable", so grepping the log would pass
    for the wrong reason.
    """
    import sqlite3

    assert run("upgrade", "head", db=fresh_db).returncode == 0

    conn = sqlite3.connect(fresh_db)
    rows = dict(conn.execute("SELECT name, type FROM sqlite_master"))
    version = [r[0] for r in conn.execute("SELECT version_num FROM alembic_version")]
    conn.close()

    # The migration ran... (head, not a pinned revision: pinning meant every
    # later migration broke this test for the wrong reason)
    assert version and version[0] != "0f8b1e62be0a"
    # ...and left `readings` an ordinary table with none of the Timescale
    # rollups alongside it.
    assert rows.get("readings") == "table"
    assert "readings_1h" not in rows
    assert "readings_1d" not in rows
