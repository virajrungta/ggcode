from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# --- devices --------------------------------------------------------------

class ClaimRequest(BaseModel):
    claim_code: str = Field(min_length=4, max_length=32)
    name: str | None = Field(default=None, max_length=120)


class ClaimResponse(BaseModel):
    device_id: str
    pot_id: str
    mqtt_username: str
    # Returned exactly once. Only the Argon2 hash is persisted, so a lost
    # secret means re-claiming the device rather than reading it back.
    mqtt_password: str
    mqtt_host: str
    mqtt_port: int
    mqtt_tls: bool


class DeviceOut(ORMModel):
    id: str
    model: str
    fw_version: str | None
    online: bool
    last_seen_at: datetime | None


# --- pots -----------------------------------------------------------------

class PotCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    device_id: str | None = None


class PotUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    auto_water_enabled: bool | None = None
    auto_water_threshold_pct: float | None = Field(default=None, ge=0, le=100)


class SpeciesOut(ORMModel):
    id: str
    scientific_name: str
    common_name: str | None


class PotOut(ORMModel):
    id: str
    name: str
    device_id: str | None
    photo_url: str | None
    identify_confidence: float | None
    auto_water_enabled: bool
    auto_water_threshold_pct: float
    created_at: datetime
    species: SpeciesOut | None = None


# --- readings -------------------------------------------------------------

class ReadingOut(BaseModel):
    time: datetime
    temp_c: float | None
    rh: float | None
    soil_pct: float | None
    lux: float | None
    batt_mv: int | None = None
    flags: int = 0


class LatestOut(BaseModel):
    pot_id: str
    device_id: str | None
    online: bool
    reading: ReadingOut | None
    health: dict[str, Any] | None


class SeriesPoint(BaseModel):
    bucket: datetime
    temp_c: float | None = None
    rh: float | None = None
    soil_pct: float | None = None
    lux: float | None = None
    samples: int = 0


class SeriesOut(BaseModel):
    pot_id: str
    bucket: str
    points: list[SeriesPoint]


# --- commands -------------------------------------------------------------

class WaterRequest(BaseModel):
    duration_s: float = Field(gt=0, le=30, description="Capped at the firmware interlock limit")


class CommandOut(ORMModel):
    id: str
    device_id: str
    op: str
    args: dict
    state: str
    issued_at: datetime
    expires_at: datetime
    acked_at: datetime | None
    result: str | None
    error: str | None


# --- identify -------------------------------------------------------------

class IdentifySuggestion(BaseModel):
    name: str
    probability: float
    similar_images: list[str] = Field(default_factory=list)


class IdentifyResponse(BaseModel):
    identified: bool
    top: IdentifySuggestion | None
    suggestions: list[IdentifySuggestion]
    confidence: float
    species_id: str | None = None
    message: str | None = None


# --- health ---------------------------------------------------------------

class ParameterOut(BaseModel):
    parameter: str
    label: str
    value: float | None
    status: Literal["good", "warning", "bad", "unknown"]
    message: str
    ideal_range: dict[str, Any] | None


class HealthOut(BaseModel):
    status: Literal["good", "warning", "bad", "unknown"]
    score: int | None
    confidence: Literal["species", "genus", "default"]
    profile_source: str
    parameters: list[ParameterOut]
    issues: list[str]
    recommendations: list[str]
    notes: list[str]
