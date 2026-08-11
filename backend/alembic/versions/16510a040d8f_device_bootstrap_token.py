"""device bootstrap token

Adds `devices.bootstrap_token`, the device-facing twin of `claim_code`.

Claiming consumes `claim_code`, so a pot that authenticated with it had no way
to re-authenticate once its owner claimed it. `bootstrap_token` is never
consumed, so a pot can obtain its telemetry secret before or after claim.

Existing rows are backfilled from `claim_code` where one is still present.
A pot that was already claimed has a null token and must be re-registered with
scripts/register_device.py, which is a bench operation anyway.

Revision ID: 16510a040d8f
Revises: 0002_timescale
"""

from alembic import op
import sqlalchemy as sa

revision = "16510a040d8f"
down_revision = "0002_timescale"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("devices", sa.Column("bootstrap_token", sa.String(32), nullable=True))
    op.create_index("ix_devices_bootstrap_token", "devices", ["bootstrap_token"])

    # Unclaimed devices keep working without a re-register.
    op.execute(
        "UPDATE devices SET bootstrap_token = claim_code "
        "WHERE claim_code IS NOT NULL"
    )


def downgrade() -> None:
    op.drop_index("ix_devices_bootstrap_token", table_name="devices")
    op.drop_column("devices", "bootstrap_token")
