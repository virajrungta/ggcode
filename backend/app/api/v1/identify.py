from __future__ import annotations

import hashlib
import logging

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1 import schemas as S
from app.api.v1.deps import owned_pot
from app.core.config import Settings, get_settings
from app.db.models import PlantSpecies, Pot
from app.db.session import get_db
from app.services.plant_id import PlantIdClient, PlantIdError

log = logging.getLogger(__name__)
router = APIRouter(prefix="/pots", tags=["identify"])

MAX_IMAGE_BYTES = 8 * 1024 * 1024
ACCEPTED_TYPES = {"image/jpeg", "image/png", "image/webp", "image/heic"}

# Below this the app should ask the user to retake rather than silently
# assigning a species — a wrong species means wrong care thresholds, which is
# worse than no species at all.
LOW_CONFIDENCE_THRESHOLD = 0.55


@router.post("/{pot_id}/identify", response_model=S.IdentifyResponse)
async def identify_plant(
    file: UploadFile = File(...),
    pot: Pot = Depends(owned_pot),
    db: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
):
    """Identify the plant in a photo and bind the species to the pot.

    Multipart rather than base64-in-JSON (what the old endpoint did): base64
    inflates every upload by 33% and forces the whole image into memory as a
    string on both client and server.
    """
    if file.content_type not in ACCEPTED_TYPES:
        raise HTTPException(
            status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            f"Unsupported image type {file.content_type!r}",
        )

    data = await file.read()
    if not data:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Empty upload")
    if len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(
            status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            f"Image exceeds {MAX_IMAGE_BYTES // (1024 * 1024)}MB",
        )

    if not settings.plant_id_api_key:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Plant identification is not configured on this server",
        )

    image_hash = hashlib.sha256(data).hexdigest()
    client = PlantIdClient(settings.plant_id_api_key)

    try:
        suggestions = await client.identify(data)
    except PlantIdError as exc:
        log.warning("plant.id failed for pot %s: %s", pot.id, exc)
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, str(exc)) from exc

    if not suggestions:
        return S.IdentifyResponse(
            identified=False, top=None, suggestions=[], confidence=0.0,
            message="Could not identify this plant. Try a clearer photo of the leaves.",
        )

    top = suggestions[0]
    out = [
        S.IdentifySuggestion(
            name=s["name"], probability=s["probability"],
            similar_images=s.get("similar_images", []),
        )
        for s in suggestions[:3]
    ]

    if top["probability"] < LOW_CONFIDENCE_THRESHOLD:
        return S.IdentifyResponse(
            identified=False, top=out[0], suggestions=out,
            confidence=top["probability"] * 100,
            message="Not confident about this match. Pick one below or retake the photo.",
        )

    species = await _get_or_create_species(db, top["name"])
    pot.species_id = species.id
    pot.identify_confidence = top["probability"] * 100
    log.info("pot %s identified as %s (%.0f%%, sha %s)",
             pot.id, top["name"], top["probability"] * 100, image_hash[:8])

    return S.IdentifyResponse(
        identified=True, top=out[0], suggestions=out,
        confidence=top["probability"] * 100, species_id=species.id,
    )


async def _get_or_create_species(db: AsyncSession, scientific_name: str) -> PlantSpecies:
    result = await db.execute(
        select(PlantSpecies).where(PlantSpecies.scientific_name == scientific_name)
    )
    species = result.scalar_one_or_none()
    if species is None:
        species = PlantSpecies(
            scientific_name=scientific_name,
            common_name=scientific_name,
            genus=scientific_name.split()[0] if scientific_name.split() else None,
            source="plant.id",
        )
        db.add(species)
        await db.flush()
    return species
