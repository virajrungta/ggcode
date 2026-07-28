from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="GG_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    env: Literal["development", "staging", "production"] = "development"

    database_url: str = "sqlite+aiosqlite:///./greengenius.db"
    redis_url: str | None = None

    mqtt_host: str = "localhost"
    mqtt_port: int = 1883
    mqtt_tls: bool = False
    mqtt_username: str | None = None
    mqtt_password: str | None = None

    # Firebase project whose ID tokens we accept. Also the expected `aud` claim.
    firebase_project_id: str = "greengenius-b9d6f"
    auth_mode: Literal["firebase", "dev"] = "firebase"

    plant_id_api_key: str | None = None
    trefle_api_token: str | None = None

    # Emit synthetic device telemetry so the stack is demoable without hardware.
    simulate: bool = False

    cors_origins: list[str] = Field(default_factory=list)

    claim_code_ttl_seconds: int = 900
    command_default_ttl_seconds: int = 180

    @model_validator(mode="after")
    def _guard_production(self) -> "Settings":
        if self.env != "production":
            return self

        # These are the settings that are harmless locally and catastrophic in
        # production, so they fail at startup rather than at the first request.
        if self.auth_mode == "dev":
            raise ValueError(
                "GG_AUTH_MODE=dev bypasses token verification and cannot be "
                "used with GG_ENV=production"
            )
        if self.simulate:
            raise ValueError("GG_SIMULATE cannot be enabled in production")
        if not self.mqtt_tls:
            raise ValueError("GG_MQTT_TLS must be true in production")
        if "*" in self.cors_origins:
            raise ValueError("Wildcard CORS origin is not permitted in production")
        if self.database_url.startswith("sqlite"):
            raise ValueError("SQLite is not a supported production database")
        return self

    @property
    def is_sqlite(self) -> bool:
        return self.database_url.startswith("sqlite")


@lru_cache
def get_settings() -> Settings:
    return Settings()
