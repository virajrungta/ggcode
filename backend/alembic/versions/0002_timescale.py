"""timescale hypertable, aggregates, compression, retention

Revision ID: 0002_timescale
Revises: 0f8b1e62be0a
Create Date: 2026-07-28

Everything here is Postgres/TimescaleDB-only and is skipped on SQLite, so the
same migration chain runs in local dev. The guard is on the dialect rather
than on a config flag: it should be impossible to run this against SQLite by
setting an env var wrong.
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


def upgrade() -> None:
    if not _is_postgres():
        return

    if not _has_timescale():
        print("timescaledb not available - skipping hypertable setup")
        return

    op.execute("CREATE EXTENSION IF NOT EXISTS timescaledb")

    # migrate_data handles the case where rows already exist.
    op.execute(
        "SELECT create_hypertable('readings', 'time', "
        "chunk_time_interval => INTERVAL '1 day', "
        "if_not_exists => TRUE, migrate_data => TRUE)"
    )

    op.execute(
        "ALTER TABLE readings SET ("
        "  timescaledb.compress,"
        "  timescaledb.compress_segmentby = 'device_id',"
        "  timescaledb.compress_orderby = 'time DESC'"
        ")"
    )
    op.execute(
        f"SELECT add_compression_policy('readings', INTERVAL '{COMPRESS_AFTER}')"
    )

    # Hourly rollup. The app's chart endpoint reads this, never the raw table:
    # a 90-day window at 60s sampling is ~130k rows per device.
    op.execute(
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
        """
    )
    op.execute(
        "SELECT add_continuous_aggregate_policy('readings_1h',"
        "  start_offset => INTERVAL '3 days',"
        "  end_offset   => INTERVAL '1 hour',"
        "  schedule_interval => INTERVAL '1 hour')"
    )

    op.execute(
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
        """
    )
    op.execute(
        "SELECT add_continuous_aggregate_policy('readings_1d',"
        "  start_offset => INTERVAL '30 days',"
        "  end_offset   => INTERVAL '1 day',"
        "  schedule_interval => INTERVAL '1 day')"
    )

    op.execute(
        f"SELECT add_retention_policy('readings', INTERVAL '{RAW_RETENTION}')"
    )


def downgrade() -> None:
    if not _is_postgres():
        return
    op.execute("DROP MATERIALIZED VIEW IF EXISTS readings_1d CASCADE")
    op.execute("DROP MATERIALIZED VIEW IF EXISTS readings_1h CASCADE")
    op.execute("SELECT remove_retention_policy('readings', if_exists => TRUE)")
    op.execute("SELECT remove_compression_policy('readings', if_exists => TRUE)")
