"""Round-trips the golden vectors in contracts/vectors/telemetry.json.

The Dart suite (app/test/ble_codec_test.dart) decodes the same file, so a
struct change that is applied to only one side fails both builds instead of
silently corrupting readings on one platform.
"""

from __future__ import annotations

import json
import struct
from pathlib import Path

import pytest

from app.services import telemetry_codec as codec

VECTORS_PATH = Path(__file__).resolve().parents[2] / "contracts" / "vectors" / "telemetry.json"


def load_vectors() -> list[dict]:
    return json.loads(VECTORS_PATH.read_text())["vectors"]


def test_vectors_file_exists():
    assert VECTORS_PATH.exists(), f"missing contract vectors at {VECTORS_PATH}"


def test_struct_matches_contract():
    doc = json.loads(VECTORS_PATH.read_text())
    assert doc["struct_format_python"] == codec.STRUCT_FORMAT
    assert doc["size_bytes"] == codec.STRUCT_SIZE == 15


@pytest.mark.parametrize("vec", load_vectors(), ids=lambda v: v["name"])
def test_decode_matches_expected_fields(vec):
    raw = bytes.fromhex(vec["hex"])
    assert len(raw) == 15

    decoded = codec.decode(raw)
    expected = vec["decoded"]

    assert decoded.uptime_s == expected["uptime_s"]
    assert decoded.flags == expected["flags"]

    if expected["temp_c_x100"] == codec.TEMP_FAULT:
        assert decoded.temp_c is None
    else:
        assert decoded.temp_c == pytest.approx(expected["temp_c_x100"] / 100.0)

    if expected["rh_x100"] == codec.RH_FAULT:
        assert decoded.rh is None
    else:
        assert decoded.rh == pytest.approx(expected["rh_x100"] / 100.0)

    if expected["soil_pct_x100"] == codec.SOIL_FAULT:
        assert decoded.soil_pct is None
    else:
        assert decoded.soil_pct == pytest.approx(expected["soil_pct_x100"] / 100.0)

    if expected["lux_x10"] == codec.LUX_FAULT:
        assert decoded.lux is None
    else:
        assert decoded.lux == pytest.approx(expected["lux_x10"] / 10.0)


@pytest.mark.parametrize("vec", load_vectors(), ids=lambda v: v["name"])
def test_encode_decode_roundtrip(vec):
    raw = bytes.fromhex(vec["hex"])
    assert codec.encode(codec.decode(raw)) == raw


def test_fault_sentinels_decode_to_none():
    raw = struct.pack(
        codec.STRUCT_FORMAT, 1, codec.TEMP_FAULT, codec.RH_FAULT,
        codec.SOIL_FAULT, codec.LUX_FAULT, codec.FLAG_SENSOR_FAULT,
    )
    t = codec.decode(raw)
    assert (t.temp_c, t.rh, t.soil_pct, t.lux) == (None, None, None, None)
    assert t.sensor_fault


def test_zero_is_not_a_fault():
    """The distinction the sentinels exist for: real 0.0 must survive."""
    raw = struct.pack(codec.STRUCT_FORMAT, 0, 0, 0, 0, 0, 0)
    t = codec.decode(raw)
    assert t.temp_c == 0.0 and t.rh == 0.0 and t.soil_pct == 0.0 and t.lux == 0.0
    assert not t.sensor_fault


def test_negative_temperature():
    t = codec.decode(bytes.fromhex(next(
        v["hex"] for v in load_vectors() if v["name"] == "freezing"
    )))
    assert t.temp_c == pytest.approx(-12.5)


@pytest.mark.parametrize("size", [0, 1, 14, 16, 32])
def test_wrong_size_rejected(size):
    with pytest.raises(ValueError, match="expected 15 bytes"):
        codec.decode(b"\x00" * size)


class TestClampSample:
    def test_passes_plausible_values(self):
        sample = {"temp_c": 21.5, "rh": 47.0, "soil_pct": 38.0, "lux": 1200.0, "flags": 0}
        cleaned, rejected = codec.clamp_sample(sample)
        assert rejected == []
        assert cleaned["temp_c"] == 21.5

    def test_nulls_impossible_temperature(self):
        cleaned, rejected = codec.clamp_sample({"temp_c": -3000.0, "rh": 50.0})
        assert cleaned["temp_c"] is None
        assert rejected == ["temp_c"]
        assert cleaned["flags"] & codec.FLAG_SENSOR_FAULT

    def test_nulls_impossible_humidity(self):
        cleaned, rejected = codec.clamp_sample({"rh": 340.0})
        assert cleaned["rh"] is None and "rh" in rejected

    def test_preserves_none(self):
        cleaned, rejected = codec.clamp_sample({"temp_c": None, "rh": 50.0})
        assert cleaned["temp_c"] is None
        assert rejected == []

    def test_non_numeric_rejected(self):
        cleaned, rejected = codec.clamp_sample({"temp_c": "warm"})
        assert cleaned["temp_c"] is None and "temp_c" in rejected

    def test_boundaries_inclusive(self):
        cleaned, rejected = codec.clamp_sample({"temp_c": -40.0, "rh": 100.0})
        assert rejected == []
        assert cleaned["temp_c"] == -40.0 and cleaned["rh"] == 100.0
