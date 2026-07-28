"""Verifies the C struct in firmware produces the same bytes as the Python codec.

Compiles firmware/test/pack_probe.c on the host and compares its output to
contracts/vectors/telemetry.json. This is the cross-language half of the
contract: the Python tests prove the codec is self-consistent, but only this
proves the *firmware's* layout agrees with it.

A padding or endianness mismatch here does not crash anything — it produces
plausible-looking wrong readings, which is far harder to notice and far worse.

Skipped when no C compiler is available.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
PROBE_SRC = ROOT / "firmware" / "test" / "pack_probe.c"
VECTORS = ROOT / "contracts" / "vectors" / "telemetry.json"

CC = shutil.which("cc") or shutil.which("gcc") or shutil.which("clang")

pytestmark = pytest.mark.skipif(
    CC is None or not PROBE_SRC.exists(),
    reason="no C compiler or probe source available",
)


@pytest.fixture(scope="module")
def probe(tmp_path_factory):
    out = tmp_path_factory.mktemp("firmware") / "pack_probe"
    result = subprocess.run(
        [CC, "-O1", "-Wall", "-Werror", "-o", str(out), str(PROBE_SRC)],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        pytest.fail(f"pack_probe failed to compile:\n{result.stderr}")
    return out


def load_vectors():
    return json.loads(VECTORS.read_text())["vectors"]


def test_struct_is_15_bytes(probe):
    """_Static_assert already enforces this at compile time; this makes the
    failure legible if someone weakens the assert."""
    out = subprocess.run([str(probe), "-size"], capture_output=True, text=True)
    assert out.stdout.strip() == "15"


@pytest.mark.parametrize("vec", load_vectors(), ids=lambda v: v["name"])
def test_c_layout_matches_vector(probe, vec):
    d = vec["decoded"]
    out = subprocess.run(
        [
            str(probe),
            str(d["uptime_s"]), str(d["temp_c_x100"]), str(d["rh_x100"]),
            str(d["soil_pct_x100"]), str(d["lux_x10"]), str(d["flags"]),
        ],
        capture_output=True, text=True, check=True,
    )
    assert out.stdout.strip() == vec["hex"], (
        f"C struct layout diverged from the contract for vector {vec['name']!r}"
    )


@pytest.mark.parametrize("vec", load_vectors(), ids=lambda v: v["name"])
def test_python_decodes_c_output(probe, vec):
    """Full round trip: C packs it, Python decodes it, values survive."""
    from app.services import telemetry_codec as codec

    d = vec["decoded"]
    out = subprocess.run(
        [
            str(probe),
            str(d["uptime_s"]), str(d["temp_c_x100"]), str(d["rh_x100"]),
            str(d["soil_pct_x100"]), str(d["lux_x10"]), str(d["flags"]),
        ],
        capture_output=True, text=True, check=True,
    )

    decoded = codec.decode(bytes.fromhex(out.stdout.strip()))
    assert decoded.uptime_s == d["uptime_s"]
    assert decoded.flags == d["flags"]

    if d["temp_c_x100"] != codec.TEMP_FAULT:
        assert decoded.temp_c == pytest.approx(d["temp_c_x100"] / 100.0)
