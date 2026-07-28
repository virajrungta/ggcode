"""Species-aware plant health assessment.

Replaces the original `analysis_service.py`, which applied fixed 20/80 moisture
thresholds to every plant and read Trefle's annual *precipitation* figure as a
proxy for soil moisture. Those are different physical quantities; a cactus and a
fern were being judged identically.

Resolution order for a care profile:
    species profile -> genus default -> global default
Every assessment reports which tier it used, because "we know this plant needs
40-60% soil moisture" and "we are guessing" should never look the same in the UI.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Iterable


class Severity(str, Enum):
    GOOD = "good"
    WARNING = "warning"
    BAD = "bad"
    UNKNOWN = "unknown"


class Confidence(str, Enum):
    SPECIES = "species"   # curated profile for this exact species
    GENUS = "genus"       # inherited from the genus
    DEFAULT = "default"   # global fallback — little better than a guess


@dataclass(frozen=True)
class Band:
    """An acceptable range with a comfortable core inside it."""

    min: float
    max: float
    ideal_min: float | None = None
    ideal_max: float | None = None
    unit: str = ""

    def classify(self, value: float) -> Severity:
        if value < self.min or value > self.max:
            return Severity.BAD
        lo = self.ideal_min if self.ideal_min is not None else self.min
        hi = self.ideal_max if self.ideal_max is not None else self.max
        return Severity.GOOD if lo <= value <= hi else Severity.WARNING


@dataclass
class CareProfile:
    soil_pct: Band | None = None
    temp_c: Band | None = None
    rh: Band | None = None
    lux: Band | None = None
    confidence: Confidence = Confidence.DEFAULT
    source: str = "default"
    notes: list[str] = field(default_factory=list)


# A deliberately conservative fallback: wide enough that a mis-identified plant
# is not nagged constantly, narrow enough to catch genuine neglect.
GLOBAL_DEFAULT = CareProfile(
    soil_pct=Band(15, 75, 30, 60, "%"),
    temp_c=Band(8, 32, 16, 26, "°C"),
    rh=Band(20, 90, 40, 70, "%"),
    lux=Band(200, 60_000, 1_000, 20_000, "lx"),
    confidence=Confidence.DEFAULT,
    source="global-default",
)

# Seed set. Expand via the curated dataset described in the implementation plan;
# the shape matters more than the coverage at this stage.
GENUS_PROFILES: dict[str, CareProfile] = {
    "sansevieria": CareProfile(
        soil_pct=Band(5, 45, 10, 30, "%"), temp_c=Band(10, 35, 18, 27, "°C"),
        rh=Band(20, 70, 30, 50, "%"), lux=Band(500, 50_000, 2_000, 15_000, "lx"),
        confidence=Confidence.GENUS, source="genus:sansevieria",
        notes=["Drought-adapted. Overwatering is the usual cause of death."],
    ),
    "dracaena": CareProfile(
        soil_pct=Band(20, 65, 30, 50, "%"), temp_c=Band(15, 30, 18, 26, "°C"),
        rh=Band(30, 80, 40, 60, "%"), lux=Band(500, 30_000, 1_500, 10_000, "lx"),
        confidence=Confidence.GENUS, source="genus:dracaena",
    ),
    "monstera": CareProfile(
        soil_pct=Band(25, 70, 40, 60, "%"), temp_c=Band(16, 30, 20, 27, "°C"),
        rh=Band(40, 90, 60, 80, "%"), lux=Band(800, 25_000, 2_000, 12_000, "lx"),
        confidence=Confidence.GENUS, source="genus:monstera",
        notes=["Prefers bright indirect light; direct sun scorches leaves."],
    ),
    "ficus": CareProfile(
        soil_pct=Band(25, 70, 35, 55, "%"), temp_c=Band(15, 30, 18, 26, "°C"),
        rh=Band(40, 85, 50, 70, "%"), lux=Band(1_000, 40_000, 3_000, 15_000, "lx"),
        confidence=Confidence.GENUS, source="genus:ficus",
        notes=["Dislikes being moved; leaf drop after relocation is normal."],
    ),
    "epipremnum": CareProfile(
        soil_pct=Band(20, 70, 35, 55, "%"), temp_c=Band(15, 32, 18, 28, "°C"),
        rh=Band(30, 90, 50, 70, "%"), lux=Band(300, 25_000, 1_000, 10_000, "lx"),
        confidence=Confidence.GENUS, source="genus:epipremnum",
    ),
    "spathiphyllum": CareProfile(
        soil_pct=Band(35, 80, 50, 70, "%"), temp_c=Band(16, 30, 20, 27, "°C"),
        rh=Band(40, 95, 60, 80, "%"), lux=Band(200, 15_000, 800, 8_000, "lx"),
        confidence=Confidence.GENUS, source="genus:spathiphyllum",
        notes=["Wilts visibly when thirsty and recovers quickly after watering."],
    ),
    "succulent": CareProfile(
        soil_pct=Band(5, 40, 8, 25, "%"), temp_c=Band(5, 38, 18, 30, "°C"),
        rh=Band(10, 60, 20, 45, "%"), lux=Band(2_000, 100_000, 10_000, 50_000, "lx"),
        confidence=Confidence.GENUS, source="genus:succulent",
        notes=["Soil must dry fully between waterings."],
    ),
}

SPECIES_PROFILES: dict[str, CareProfile] = {
    "sansevieria trifasciata": CareProfile(
        soil_pct=Band(5, 40, 10, 25, "%"), temp_c=Band(10, 35, 18, 27, "°C"),
        rh=Band(20, 70, 30, 50, "%"), lux=Band(500, 50_000, 2_000, 15_000, "lx"),
        confidence=Confidence.SPECIES, source="species:sansevieria-trifasciata",
        notes=["Snake plant. Water roughly every 2-6 weeks depending on light."],
    ),
    "monstera deliciosa": CareProfile(
        soil_pct=Band(25, 70, 40, 60, "%"), temp_c=Band(18, 30, 20, 27, "°C"),
        rh=Band(40, 90, 60, 80, "%"), lux=Band(1_000, 25_000, 2_500, 12_000, "lx"),
        confidence=Confidence.SPECIES, source="species:monstera-deliciosa",
    ),
    "epipremnum aureum": CareProfile(
        soil_pct=Band(20, 70, 35, 55, "%"), temp_c=Band(15, 32, 18, 28, "°C"),
        rh=Band(30, 90, 50, 70, "%"), lux=Band(300, 25_000, 1_000, 10_000, "lx"),
        confidence=Confidence.SPECIES, source="species:epipremnum-aureum",
        notes=["Golden pothos. Very tolerant; good beginner plant."],
    ),
}

PARAMETER_LABELS = {
    "soil_pct": "Soil Moisture",
    "temp_c": "Temperature",
    "rh": "Humidity",
    "lux": "Light",
}


def _band_from_dict(raw: dict[str, Any] | None) -> Band | None:
    if not raw:
        return None
    try:
        return Band(
            min=float(raw["min"]), max=float(raw["max"]),
            ideal_min=raw.get("ideal_min"), ideal_max=raw.get("ideal_max"),
            unit=raw.get("unit", ""),
        )
    except (KeyError, TypeError, ValueError):
        return None


def resolve_profile(
    scientific_name: str | None = None,
    stored_profile: dict[str, Any] | None = None,
) -> CareProfile:
    """Resolve the best available profile, most specific first."""
    if stored_profile:
        bands = {k: _band_from_dict(stored_profile.get(k)) for k in PARAMETER_LABELS}
        if any(bands.values()):
            return CareProfile(
                **bands,
                confidence=Confidence(stored_profile.get("confidence", "species")),
                source=stored_profile.get("source", "stored"),
                notes=list(stored_profile.get("notes", [])),
            )

    if not scientific_name:
        return GLOBAL_DEFAULT

    name = scientific_name.strip().lower()
    if name in SPECIES_PROFILES:
        return SPECIES_PROFILES[name]

    genus = name.split()[0] if name.split() else ""
    if genus in GENUS_PROFILES:
        return GENUS_PROFILES[genus]

    return GLOBAL_DEFAULT


@dataclass
class ParameterAssessment:
    parameter: str
    label: str
    value: float | None
    status: Severity
    message: str
    band: Band | None

    def to_dict(self) -> dict:
        return {
            "parameter": self.parameter,
            "label": self.label,
            "value": self.value,
            "status": self.status.value,
            "message": self.message,
            "ideal_range": (
                {
                    "min": self.band.min, "max": self.band.max,
                    "ideal_min": self.band.ideal_min, "ideal_max": self.band.ideal_max,
                    "unit": self.band.unit,
                }
                if self.band else None
            ),
        }


def _message(label: str, value: float, band: Band, status: Severity) -> str:
    unit = band.unit
    if status is Severity.GOOD:
        return f"{label} is in the ideal range"
    if value < band.min:
        return f"{label} is too low ({value:g}{unit}, needs at least {band.min:g}{unit})"
    if value > band.max:
        return f"{label} is too high ({value:g}{unit}, max {band.max:g}{unit})"
    lo = band.ideal_min if band.ideal_min is not None else band.min
    hi = band.ideal_max if band.ideal_max is not None else band.max
    if value < lo:
        return f"{label} is slightly low ({value:g}{unit}, ideally {lo:g}-{hi:g}{unit})"
    return f"{label} is slightly high ({value:g}{unit}, ideally {lo:g}-{hi:g}{unit})"


def assess(
    reading: dict[str, Any],
    scientific_name: str | None = None,
    stored_profile: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Assess one reading against the resolved care profile."""
    profile = resolve_profile(scientific_name, stored_profile)
    assessments: list[ParameterAssessment] = []

    for key, label in PARAMETER_LABELS.items():
        band = getattr(profile, key)
        value = reading.get(key)

        if value is None:
            assessments.append(ParameterAssessment(
                key, label, None, Severity.UNKNOWN,
                f"No {label.lower()} reading available", band,
            ))
            continue
        if band is None:
            assessments.append(ParameterAssessment(
                key, label, float(value), Severity.UNKNOWN,
                f"No guidance available for {label.lower()}", None,
            ))
            continue

        value = float(value)
        status = band.classify(value)
        assessments.append(ParameterAssessment(
            key, label, value, status, _message(label, value, band, status), band,
        ))

    overall = _overall(a.status for a in assessments)

    return {
        "status": overall.value,
        "score": _score(assessments),
        "confidence": profile.confidence.value,
        "profile_source": profile.source,
        "parameters": [a.to_dict() for a in assessments],
        "issues": [a.message for a in assessments
                   if a.status in (Severity.WARNING, Severity.BAD)],
        "recommendations": _recommendations(assessments),
        "notes": profile.notes,
    }


def _overall(statuses: Iterable[Severity]) -> Severity:
    statuses = list(statuses)
    if any(s is Severity.BAD for s in statuses):
        return Severity.BAD
    if any(s is Severity.WARNING for s in statuses):
        return Severity.WARNING
    if any(s is Severity.GOOD for s in statuses):
        return Severity.GOOD
    return Severity.UNKNOWN


def _score(assessments: list[ParameterAssessment]) -> int | None:
    """0-100 health score. None when nothing could be assessed.

    Returning None rather than 0 or 100 for "no data": a pot with a dead sensor
    is not a pot at 0% health, and showing either number would be a lie the user
    would act on.
    """
    weights = {Severity.GOOD: 1.0, Severity.WARNING: 0.6, Severity.BAD: 0.0}
    scored = [weights[a.status] for a in assessments if a.status in weights]
    if not scored:
        return None
    return round(100 * sum(scored) / len(scored))


def _recommendations(assessments: list[ParameterAssessment]) -> list[str]:
    out: list[str] = []
    for a in assessments:
        if a.status not in (Severity.WARNING, Severity.BAD) or a.band is None or a.value is None:
            continue
        low = a.value < (a.band.ideal_min if a.band.ideal_min is not None else a.band.min)
        match (a.parameter, low):
            case ("soil_pct", True):
                out.append("Water the plant until soil moisture reaches the ideal range.")
            case ("soil_pct", False):
                out.append("Hold off watering and check that the pot drains freely.")
            case ("temp_c", True):
                out.append("Move the plant somewhere warmer, away from cold draughts.")
            case ("temp_c", False):
                out.append("Move the plant out of direct heat.")
            case ("rh", True):
                out.append("Raise humidity — group plants together or use a pebble tray.")
            case ("rh", False):
                out.append("Improve air circulation to reduce fungal risk.")
            case ("lux", True):
                out.append("Move to a brighter spot or add a grow light.")
            case ("lux", False):
                out.append("Shade from direct sun to prevent leaf scorch.")
    return out
