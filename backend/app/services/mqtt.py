"""MQTT publish helpers. See contracts/telemetry.md."""

from __future__ import annotations

import json
import logging
import ssl
from typing import Any

import aiomqtt

from app.core.config import get_settings
from app.db.models import Command

log = logging.getLogger(__name__)

TOPIC_PREFIX = "gg/v1"


def topic(device_id: str, leaf: str) -> str:
    return f"{TOPIC_PREFIX}/{device_id}/{leaf}"


def client_kwargs() -> dict[str, Any]:
    settings = get_settings()
    kwargs: dict[str, Any] = {
        "hostname": settings.mqtt_host,
        "port": settings.mqtt_port,
        "keepalive": 60,
    }
    if settings.mqtt_username:
        kwargs["username"] = settings.mqtt_username
        kwargs["password"] = settings.mqtt_password
    if settings.mqtt_tls:
        kwargs["tls_context"] = ssl.create_default_context()
    return kwargs


async def publish_command(command: Command) -> None:
    """Publish a command at QoS 1.

    `expires_at` is included because the device enforces it: with
    clean_session=false a pot that was offline receives its whole backlog on
    reconnect, and without expiry a queued "water 5s" fires hours later,
    repeatedly. See contracts/telemetry.md.
    """
    payload = {
        "id": command.id,
        "op": command.op,
        "args": command.args,
        "expires_at": int(command.expires_at.timestamp()),
    }
    async with aiomqtt.Client(**client_kwargs()) as client:
        await client.publish(
            topic(command.device_id, "cmd"), json.dumps(payload).encode(), qos=1
        )
    log.info("published %s command %s to %s", command.op, command.id, command.device_id)
