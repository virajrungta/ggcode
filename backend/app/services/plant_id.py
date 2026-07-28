"""Plant.id v3 client.

Ported from the original `plant_id_client.py`. Changes: async (the sync
`requests` call blocked the event loop for the full 2-6s identification),
raises a typed error instead of leaking `requests` exceptions, and normalises
the nested v3 response into a flat suggestion list so route code does not have
to know the API's shape.
"""

from __future__ import annotations

import base64
import logging
from typing import Any

import httpx

log = logging.getLogger(__name__)

API_URL = "https://plant.id/api/v3/identification"
TIMEOUT = httpx.Timeout(30.0, connect=10.0)


class PlantIdError(RuntimeError):
    pass


class PlantIdClient:
    def __init__(self, api_key: str, api_url: str = API_URL) -> None:
        if not api_key:
            raise ValueError("Plant.id API key is required")
        self._api_key = api_key
        self._api_url = api_url

    async def identify(self, image: bytes) -> list[dict[str, Any]]:
        payload = {
            "images": [base64.b64encode(image).decode()],
            "similar_images": True,
        }
        headers = {"Content-Type": "application/json", "Api-Key": self._api_key}

        try:
            async with httpx.AsyncClient(timeout=TIMEOUT) as client:
                resp = await client.post(self._api_url, json=payload, headers=headers)
        except httpx.RequestError as exc:
            raise PlantIdError(f"Could not reach Plant.id: {exc}") from exc

        if resp.status_code == 401:
            raise PlantIdError("Plant.id rejected the API key")
        if resp.status_code == 429:
            raise PlantIdError("Plant.id rate limit reached")
        if resp.status_code >= 400:
            raise PlantIdError(f"Plant.id error {resp.status_code}: {resp.text[:200]}")

        try:
            body = resp.json()
        except ValueError as exc:
            raise PlantIdError("Plant.id returned malformed JSON") from exc

        return self._normalise(body)

    @staticmethod
    def _normalise(body: dict[str, Any]) -> list[dict[str, Any]]:
        """Flatten result.classification.suggestions[] into a stable shape."""
        suggestions = (
            body.get("result", {}).get("classification", {}).get("suggestions", []) or []
        )

        out: list[dict[str, Any]] = []
        for s in suggestions:
            images = [
                img["url"]
                for img in (s.get("similar_images") or [])
                if isinstance(img, dict) and img.get("url")
            ]
            out.append({
                "id": s.get("id"),
                "name": s.get("name", "Unknown"),
                "probability": float(s.get("probability") or 0.0),
                "similar_images": images[:3],
            })

        out.sort(key=lambda s: s["probability"], reverse=True)
        return out
