"""timescale hypertable, aggregates, compression, retention

Revision ID: 0002_timescale
Revises: 0f8b1e62be0a
Create Date: 2026-07-28

Everything here is Postgres/TimescaleDB-only and is skipped on SQLite, so the
same migration chain runs in local dev. The guard is on the dialect rather
than on a config flag: it should be impossible to run this against SQLite by
setting an env var wrong.

TimescaleDB ships in two editions and the difference is load-bearing here.
The Apache-2 edition — which is what Neon provides — has hypertables and
`time_bucket`, but compression, continuous aggregates and retention policies
are all Community-licensed and refuse to run. Requiring them made this
migration fail partway through on a managed Postgres, so each is attempted
individually and skipped if the licence rejects it.
"""
from __future__ import annotations

from alembic import op

revision = "0002_timescale"
down_revision = "0f8b1e62be0a"
branch_labels = None
depends_on = None

# Raw sensor rows. Kept 30 days, then dropped — the continuous aggregates
# below hold the long tail, and nobody charts per-minute data from last year.
RAW_RETENTION = "30 days"
COMPRESS_AFTER = "7 days"


def _is_postgres() -> bool:
    return op.get_bind().dialect.name == "postgresql"


def _has_timescale() -> bool:
    """Timescale may not be installed even on Postgres (e.g. plain RDS).

    Failing loudly here would block every deploy on a vanilla Postgres, so
    instead the table stays a normal table with its index and the app keeps
    working — just without compression or rollups.
    """
    row = op.get_bind().exec_driver_sql(
        "SELECT 1 FROM pg_available_extensions WHERE name = 'timescaledb'"
    ).fetchone()
    return row is not None


def _try_community(sql: str, label: str) -> bool:
    """Run a Community-licensed statement, tolerating an Apache-only server.

    Wrapped in a SAVEPOINT because a failed statement poisons the surrounding
    transaction: without it the licence error would abort the whole migration
    at the next statement rather than being skipped.

    Only licence rejections are swallowed. Anything else is a real error and
    is re-raised — silently ignoring those would hide a broken migration.
    """
    conn = op.get_bind()
    sp = conn.begin_nested()
    try:
        conn.exec_driver_sql(sql)
        sp.commit()
        return True
    except Exception as exc:  # noqa: BLE001 - inspected below, re-raised
        sp.rollback()
        if "license" not in str(exc).lower():
            raise
        print(f"  skipped {label}: not available under the Apache licence")
        return False


def upgrade() -> None:
    if not _is_postgres():
        return

    if not _has_timescale():
        print("timescaledb not available - skipping hypertable setup")
        return

    op.execute("CREATE EXTENSION IF NOT EXISTS timescaledb")

    # Hypertables and time_bucket are Apache-licensed, so these always work.
    # migrate_data handles the case where rows already exist.
    op.execute(
        "SELECT create_hypertable('readings', 'time', "
        "chunk_time_interval => INTERVAL '1 day', "
        "if_not_exists => TRUE, migrate_data => TRUE)"
    )

    compressed = _try_community(
        "ALTER TABLE readings SET ("
        "  timescaledb.compress,"
        "  timescaledb.compress_segmentby = 'device_id',"
        "  timescaledb.compress_orderby = 'time DESC'"
        ")",
        "compression",
    )
    if compressed:
        _try_community(
            f"SELECT add_compression_policy('readings', "
            f"INTERVAL '{COMPRESS_AFTER}')",
            "compression policy",
        )

    # Hourly rollup. A 90-day window at 60s sampling is ~130k rows per device.
    # Where this is unavailable the chart endpoint reads the raw table with
    # date_bin instead, which is why that endpoint does not reference these
    # views by name.
    rollup = _try_community(
        """
        CREATE MATERIALIZED VIEW IF NOT EXISTS readings_1h
        WITH (timescaledb.continuous) AS
        SELECT
            time_bucket(INTERVAL '1 hour', time) AS bucket,
            device_id,
            avg(temp_c)   AS temp_c,
            avg(rh)       AS rh,
            avg(soil_pct) AS soil_pct,
            avg(lux)      AS lux,
            min(soil_pct) AS soil_min,
            max(soil_pct) AS soil_max,
            count(*)      AS samples
        FROM readings
        GROUP BY bucket, device_id
        WITH NO DATA
        """,
        "readings_1h continuous aggregate",
    )

    if rollup:
        _try_community(
            "SELECT add_continuous_aggregate_policy('readings_1h',"
            "  start_offset => INTERVAL '3 days',"
            "  end_offset   => INTERVAL '1 hour',"
            "  schedule_interval => INTERVAL '1 hour')",
            "readings_1h refresh policy",
        )

        _try_community(
            """
            CREATE MATERIALIZED VIEW IF NOT EXISTS readings_1d
            WITH (timescaledb.continuous) AS
            SELECT
                time_bucket(INTERVAL '1 day', bucket) AS bucket,
                device_id,
                avg(temp_c)   AS temp_c,
                avg(rh)       AS rh,
                avg(soil_pct) AS soil_pct,
                avg(lux)      AS lux,
                min(soil_min) AS soil_min,
                max(soil_max) AS soil_max,
                sum(samples)  AS samples
            FROM readings_1h
            GROUP BY bucket, device_id
            WITH NO DATA
            """,
            "readings_1d continuous aggregate",
        )
        _try_community(
            "SELECT add_continuous_aggregate_policy('readings_1d',"
            "  start_offset => INTERVAL '30 days',"
            "  end_offset   => INTERVAL '1 day',"
            "  schedule_interval => INTERVAL '1 day')",
            "readings_1d refresh policy",
        )

        # Retention is deliberately inside the rollup branch. Dropping raw
        # rows after 30 days is only safe because the aggregates hold the long
        # tail; without them this would delete history outright.
        _try_community(
            f"SELECT add_retention_policy('readings', "
            f"INTERVAL '{RAW_RETENTION}')",
            "retention policy",
        )


def downgrade() -> None:
    if not _is_postgres():
        return
    op.execute("DROP MATERIALIZED VIEW IF EXISTS readings_1d CASCADE")
    op.execute("DROP MATERIALIZED VIEW IF EXISTS readings_1h CASCADE")
    # These functions do not exist at all under the Apache licence, so the
    # same tolerance the upgrade needs applies here.
    _try_community(
        "SELECT remove_retention_policy('readings', if_exists => TRUE)",
        "retention policy removal",
    )
    _try_community(
        "SELECT remove_compression_policy('readings', if_exists => TRUE)",
        "compression policy removal",
    )
