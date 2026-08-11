from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    JSON,
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def new_uuid() -> str:
    return str(uuid.uuid4())


class Base(DeclarativeBase):
    # JSON rather than JSONB so the same models run on SQLite for local dev.
    # The Postgres migration upgrades these columns to JSONB.
    type_annotation_map = {dict: JSON}


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    firebase_uid: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    email: Mapped[str | None] = mapped_column(String(320))
    display_name: Mapped[str | None] = mapped_column(String(120))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    pots: Mapped[list["Pot"]] = relationship(back_populates="user")


class Device(Base):
    """A physical pot. `id` is the ESP32 MAC-derived device_id used on the wire."""

    __tablename__ = "devices"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    hw_serial: Mapped[str | None] = mapped_column(String(64))
    model: Mapped[str] = mapped_column(String(32), default="GG-POT-1")
    fw_version: Mapped[str | None] = mapped_column(String(32))

    # Argon2 hash of the per-device secret used to authenticate telemetry.
    # The plaintext is returned exactly once, to the device at bootstrap, and
    # never stored.
    mqtt_secret_hash: Mapped[str | None] = mapped_column(String(255))

    # Device-facing twin of claim_code. Claiming consumes claim_code, so a
    # device that authenticated with it could never re-authenticate after its
    # owner claimed it. This column is never consumed, which lets a pot
    # bootstrap before or after claim, and again after a factory reset.
    #
    # It is not a lesser credential than claim_code: both are the same secret
    # printed on the pot, and holding it already allows claiming the device.
    bootstrap_token: Mapped[str | None] = mapped_column(String(32), index=True)

    claim_code: Mapped[str | None] = mapped_column(String(32), index=True)
    claim_code_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    claimed_by: Mapped[str | None] = mapped_column(ForeignKey("users.id"), index=True)
    claimed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    online: Mapped[bool] = mapped_column(Boolean, default=False)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class PlantSpecies(Base):
    __tablename__ = "plant_species"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    scientific_name: Mapped[str] = mapped_column(String(200), index=True)
    common_name: Mapped[str | None] = mapped_column(String(200))
    genus: Mapped[str | None] = mapped_column(String(100), index=True)
    plant_id_ref: Mapped[str | None] = mapped_column(String(64), index=True)

    # Heterogeneous by species (light hours, dormancy, pH, ...) and expected to
    # change as we learn what actually predicts plant health, so: document.
    care_profile: Mapped[dict] = mapped_column(JSON, default=dict)

    source: Mapped[str] = mapped_column(String(32), default="curated")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Pot(Base):
    __tablename__ = "pots"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    device_id: Mapped[str | None] = mapped_column(ForeignKey("devices.id"), index=True)
    species_id: Mapped[str | None] = mapped_column(ForeignKey("plant_species.id"))

    name: Mapped[str] = mapped_column(String(120))
    photo_url: Mapped[str | None] = mapped_column(Text)
    identify_confidence: Mapped[float | None] = mapped_column(Float)

    auto_water_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    auto_water_threshold_pct: Mapped[float] = mapped_column(Float, default=25.0)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )

    user: Mapped[User] = relationship(back_populates="pots")
    species: Mapped[PlantSpecies | None] = relationship()

    __table_args__ = (
        # One device drives one pot. Without this, two pots could bind the same
        # hardware and both would show the same readings.
        UniqueConstraint("device_id", name="uq_pots_device_id"),
    )


class Reading(Base):
    """Time-series sensor data. Becomes a Timescale hypertable in migration 0002.

    No surrogate primary key: hypertables are partitioned on `time`, and a
    serial id would add an index as large as the table for no query benefit.
    """

    __tablename__ = "readings"

    time: Mapped[datetime] = mapped_column(DateTime(timezone=True), primary_key=True)
    device_id: Mapped[str] = mapped_column(String(32), primary_key=True)

    temp_c: Mapped[float | None] = mapped_column(Float)
    rh: Mapped[float | None] = mapped_column(Float)
    soil_pct: Mapped[float | None] = mapped_column(Float)
    lux: Mapped[float | None] = mapped_column(Float)
    batt_mv: Mapped[int | None] = mapped_column(Integer)
    flags: Mapped[int] = mapped_column(Integer, default=0)

    __table_args__ = (Index("ix_readings_device_time", "device_id", "time"),)


class Command(Base):
    __tablename__ = "commands"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    device_id: Mapped[str] = mapped_column(ForeignKey("devices.id"), index=True)
    op: Mapped[str] = mapped_column(String(32))
    args: Mapped[dict] = mapped_column(JSON, default=dict)

    # queued -> sent -> acked | rejected | expired | failed
    state: Mapped[str] = mapped_column(String(16), default="queued", index=True)

    issued_by: Mapped[str | None] = mapped_column(ForeignKey("users.id"))
    issued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    acked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    result: Mapped[str | None] = mapped_column(String(64))
    error: Mapped[str | None] = mapped_column(String(128))


class CareEvent(Base):
    __tablename__ = "care_events"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    pot_id: Mapped[str] = mapped_column(ForeignKey("pots.id"), index=True)
    kind: Mapped[str] = mapped_column(String(32))
    volume_ml: Mapped[float | None] = mapped_column(Float)
    duration_s: Mapped[float | None] = mapped_column(Float)
    source: Mapped[str] = mapped_column(String(16), default="manual")
    note: Mapped[str | None] = mapped_column(Text)
    at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)


class Alert(Base):
    __tablename__ = "alerts"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    pot_id: Mapped[str] = mapped_column(ForeignKey("pots.id"), index=True)
    kind: Mapped[str] = mapped_column(String(48))
    severity: Mapped[str] = mapped_column(String(16), default="warning")
    message: Mapped[str] = mapped_column(Text)
    opened_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
