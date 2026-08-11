from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1 import commands, devices, identify, ingest, pots
from app.core.config import get_settings
from app.db.models import Base
from app.db.session import get_engine

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    log.info("GreenGenius API starting (env=%s, auth=%s, simulate=%s)",
             settings.env, settings.auth_mode, settings.simulate)

    if settings.is_sqlite:
        # Convenience for local dev only. Postgres schema is owned by Alembic;
        # create_all there would let the migrations and the models drift apart
        # without anyone noticing until a deploy.
        async with get_engine().begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
        log.info("SQLite dev database ready")

    yield
    await get_engine().dispose()


def create_app() -> FastAPI:
    settings = get_settings()

    # Interactive docs are the only browsable page this service has, and it
    # exists for us rather than for users. Off outside development so a public
    # deployment presents no web surface at all.
    docs_enabled = settings.env == "development"

    app = FastAPI(
        title="GreenGenius API",
        version="1.0.0",
        description="Backend for the GreenGenius AI plant pot.",
        lifespan=lifespan,
        docs_url="/docs" if docs_enabled else None,
        redoc_url="/redoc" if docs_enabled else None,
        openapi_url="/openapi.json" if docs_enabled else None,
    )

    # The old backend used allow_origins=["*"] with allow_credentials=True — a
    # combination browsers reject anyway. Origins are now explicit.
    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )

    app.include_router(devices.router, prefix="/v1")
    app.include_router(pots.router, prefix="/v1")
    app.include_router(commands.router, prefix="/v1")
    app.include_router(identify.router, prefix="/v1")
    app.include_router(ingest.router, prefix="/v1")

    @app.get("/health", tags=["meta"])
    async def health() -> dict[str, str]:
        return {"status": "ok"}

    return app


app = create_app()
