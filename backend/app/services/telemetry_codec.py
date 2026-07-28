"""Codec for the 15-byte BLE telemetry struct.

Authoritative spec: contracts/ble_gatt.md
Golden vectors:     contracts/vectors/telemetry.json (shared with the Dart tests)
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, asdict
from typing import Final

STRUCT_FORMAT: Final = "<IhHHIB"
STRUCT_SIZE: Final = struct.calcsize(STRUCT_FORMAT)
assert STRUCT_SIZE == 15, f"contract violation: struct is {STRUCT_SIZE} bytes, must be 15"

# Sentinels marking a failed sensor read. Distinct from a real zero, which is
# why they exist at all: a dead I2C bus must not look like 0.0 C.
TEMP_FAULT: Final = -32768
RH_FAULT: Final = 0xFFFF
SOIL_FAULT: Final = 0xFFFF
LUX_FAULT: Final = 0xFFFFFFFF

FLAG_PUMP_ON: Final = 1 << 0
FLAG_RESERVOIR_LOW: Final = 1 << 1
FLAG_SENSOR_FAULT: Final = 1 << 2
FLAG_UNCALIBRATED: Final = 1 << 3
FLAG_WIFI_CONNECTED: Final = 1 << 4
FLAG_MQTT_CONNECTED: Final = 1 << 5


@dataclass(frozen=True)
class Telemetry:
    uptime_s: int
    temp_c: float | None
    rh: float | None
    soil_pct: float | None
    lux: float | None
    flags: int

    @property
    def pump_on(self) -> bool:
        return bool(self.flags & FLAG_PUMP_ON)

    @property
    def reservoir_low(self) -> bool:
        return bool(self.flags & FLAG_RESERVOIR_LOW)

    @property
    def sensor_fault(self) -> bool:
        return bool(self.flags & FLAG_SENSOR_FAULT)

    @property
    def uncalibrated(self) -> bool:
        return bool(self.flags & FLAG_UNCALIBRATED)

    def to_dict(self) -> dict:
        return asdict(self)


def decode(raw: bytes) -> Telemetry:
    """Decode a BLE notification payload.

    Raises ValueError on a wrong-sized buffer rather than silently accepting a
    truncated read — a short frame means the contract is broken somewhere, and
    guessing at the missing bytes would put fiction into the database.
    """
    if len(raw) != STRUCT_SIZE:
        raise ValueError(f"expected {STRUCT_SIZE} bytes, got {len(raw)}")

    uptime, temp_raw, rh_raw, soil_raw, lux_raw, flags = struct.unpack(STRUCT_FORMAT, raw)

    return Telemetry(
        uptime_s=uptime,
        temp_c=None if temp_raw == TEMP_FAULT else temp_raw / 100.0,
        rh=None if rh_raw == RH_FAULT else rh_raw / 100.0,
        soil_pct=None if soil_raw == SOIL_FAULT else soil_raw / 100.0,
        lux=None if lux_raw == LUX_FAULT else lux_raw / 10.0,
        flags=flags,
    )


def encode(t: Telemetry) -> bytes:
    """Inverse of `decode`. Used by tests and the device simulator."""
    return struct.pack(
        STRUCT_FORMAT,
        t.uptime_s & 0xFFFFFFFF,
        TEMP_FAULT if t.temp_c is None else round(t.temp_c * 100),
        RH_FAULT if t.rh is None else round(t.rh * 100),
        SOIL_FAULT if t.soil_pct is None else round(t.soil_pct * 100),
        LUX_FAULT if t.lux is None else round(t.lux * 10),
        t.flags & 0xFF,
    )


# --- MQTT-side validation -------------------------------------------------

PLAUSIBLE_RANGES: Final[dict[str, tuple[float, float]]] = {
    "temp_c": (-40.0, 85.0),
    "rh": (0.0, 100.0),
    "soil_pct": (0.0, 100.0),
    "lux": (0.0, 200_000.0),
    "batt_mv": (0.0, 6000.0),
}


def clamp_sample(sample: dict) -> tuple[dict, list[str]]:
    """Null out physically impossible values before they reach the database.

    Returns the cleaned sample and the list of fields rejected. A shorted ADC
    pin reading -3000 C should not end up as a data point that flattens every
    temperature chart the user ever looks at.
    """
    cleaned = dict(sample)
    rejected: list[str] = []

    for field, (lo, hi) in PLAUSIBLE_RANGES.items():
        value = cleaned.get(field)
        if value is None:
            continue
        try:
            numeric = float(value)
        except (TypeError, ValueError):
            cleaned[field] = None
            rejected.append(field)
            continue
        if not (lo <= numeric <= hi):
            cleaned[field] = None
            rejected.append(field)

    if rejected:
        cleaned["flags"] = int(cleaned.get("flags") or 0) | FLAG_SENSOR_FAULT

    return cleaned, rejected
