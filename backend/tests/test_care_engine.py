from __future__ import annotations

import pytest

from app.services.care_engine import (
    Band, Confidence, Severity, assess, resolve_profile,
)

# Sits inside the *ideal* core of every Monstera deliciosa band, so any
# non-"good" result in these tests comes from the value under test.
HEALTHY = {"soil_pct": 45.0, "temp_c": 22.0, "rh": 65.0, "lux": 5000.0}


class TestBand:
    def test_ideal_core_is_good(self):
        assert Band(10, 80, 30, 60).classify(45) is Severity.GOOD

    def test_inside_range_outside_ideal_is_warning(self):
        b = Band(10, 80, 30, 60)
        assert b.classify(20) is Severity.WARNING
        assert b.classify(70) is Severity.WARNING

    def test_outside_range_is_bad(self):
        b = Band(10, 80, 30, 60)
        assert b.classify(5) is Severity.BAD
        assert b.classify(95) is Severity.BAD

    def test_boundaries_inclusive(self):
        b = Band(10, 80, 30, 60)
        assert b.classify(10) is Severity.WARNING
        assert b.classify(80) is Severity.WARNING
        assert b.classify(30) is Severity.GOOD
        assert b.classify(60) is Severity.GOOD

    def test_without_ideal_core_range_is_good(self):
        assert Band(10, 80).classify(15) is Severity.GOOD


class TestResolveProfile:
    def test_exact_species_wins(self):
        p = resolve_profile("Sansevieria trifasciata")
        assert p.confidence is Confidence.SPECIES
        assert p.source == "species:sansevieria-trifasciata"

    def test_falls_back_to_genus(self):
        p = resolve_profile("Monstera adansonii")  # not in SPECIES_PROFILES
        assert p.confidence is Confidence.GENUS
        assert p.source == "genus:monstera"

    def test_falls_back_to_global_default(self):
        p = resolve_profile("Quercus robur")
        assert p.confidence is Confidence.DEFAULT

    def test_no_name_is_default(self):
        assert resolve_profile(None).confidence is Confidence.DEFAULT

    def test_case_and_whitespace_insensitive(self):
        assert resolve_profile("  MONSTERA DELICIOSA  ").source == "species:monstera-deliciosa"

    def test_stored_profile_overrides(self):
        stored = {
            "soil_pct": {"min": 1, "max": 2, "ideal_min": 1, "ideal_max": 2, "unit": "%"},
            "source": "curated:test", "confidence": "species",
        }
        p = resolve_profile("Monstera deliciosa", stored)
        assert p.source == "curated:test"
        assert p.soil_pct.max == 2

    def test_malformed_stored_profile_falls_through(self):
        """A corrupt DB row must not crash the assessment path."""
        p = resolve_profile("Monstera deliciosa", {"soil_pct": {"min": "oops"}})
        assert p.source == "species:monstera-deliciosa"


class TestAssess:
    def test_healthy_reading(self):
        r = assess(HEALTHY, "Monstera deliciosa")
        assert r["status"] == "good"
        assert r["score"] == 100
        assert r["issues"] == []

    def test_dry_soil_flagged(self):
        r = assess({**HEALTHY, "soil_pct": 5.0}, "Monstera deliciosa")
        assert r["status"] == "bad"
        assert any("Soil Moisture" in i for i in r["issues"])
        assert any("Water the plant" in x for x in r["recommendations"])

    def test_overwatered_flagged(self):
        r = assess({**HEALTHY, "soil_pct": 95.0}, "Monstera deliciosa")
        assert r["status"] == "bad"
        assert any("drains freely" in x for x in r["recommendations"])

    def test_species_specificity_matters(self):
        """The whole point of the rewrite: 12% soil is ideal for a snake plant
        and dangerous for a monstera. The old engine could not tell them apart.

        Asserts on the soil parameter rather than overall status, since the two
        species also disagree about ideal humidity and that would confound it.
        """
        dry = {**HEALTHY, "soil_pct": 12.0}

        def soil_status(name: str) -> str:
            r = assess(dry, name)
            return next(p for p in r["parameters"] if p["parameter"] == "soil_pct")["status"]

        assert soil_status("Sansevieria trifasciata") == "good"
        assert soil_status("Monstera deliciosa") == "bad"

    def test_missing_sensor_is_unknown_not_bad(self):
        r = assess({**HEALTHY, "temp_c": None}, "Monstera deliciosa")
        temp = next(p for p in r["parameters"] if p["parameter"] == "temp_c")
        assert temp["status"] == "unknown"
        assert r["status"] == "good"  # one dead sensor is not an unhealthy plant

    def test_all_sensors_dead_scores_none(self):
        r = assess({"soil_pct": None, "temp_c": None, "rh": None, "lux": None})
        assert r["score"] is None
        assert r["status"] == "unknown"

    def test_confidence_is_surfaced(self):
        assert assess(HEALTHY, "Monstera deliciosa")["confidence"] == "species"
        assert assess(HEALTHY, "Monstera adansonii")["confidence"] == "genus"
        assert assess(HEALTHY, "Unknown plantus")["confidence"] == "default"

    def test_ideal_range_returned_for_ui(self):
        r = assess(HEALTHY, "Monstera deliciosa")
        soil = next(p for p in r["parameters"] if p["parameter"] == "soil_pct")
        assert soil["ideal_range"]["unit"] == "%"
        assert soil["ideal_range"]["ideal_min"] == 40

    def test_score_degrades_with_warnings(self):
        good = assess(HEALTHY, "Monstera deliciosa")["score"]
        warn = assess({**HEALTHY, "soil_pct": 28.0}, "Monstera deliciosa")["score"]
        bad = assess({**HEALTHY, "soil_pct": 5.0}, "Monstera deliciosa")["score"]
        assert good > warn > bad

    def test_empty_reading_does_not_crash(self):
        r = assess({})
        assert r["score"] is None and r["status"] == "unknown"

    @pytest.mark.parametrize("value", [-40.0, 0.0, 85.0])
    def test_extreme_but_valid_temps(self, value):
        r = assess({**HEALTHY, "temp_c": value}, "Monstera deliciosa")
        assert r["status"] in {"good", "warning", "bad"}
