from __future__ import annotations

from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import (
    AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine,
)

from app.core.config import get_settings

_engine: AsyncEngine | None = None
_sessionmaker: async_sessionmaker[AsyncSession] | None = None


def get_engine() -> AsyncEngine:
    global _engine
    if _engine is None:
        settings = get_settings()
        kwargs: dict = {"echo": False, "future": True}
        if not settings.is_sqlite:
            kwargs |= {"pool_size": 10, "max_overflow": 20, "pool_pre_ping": True}
        _engine = create_async_engine(settings.database_url, **kwargs)
    return _engine


def get_sessionmaker() -> async_sessionmaker[AsyncSession]:
    global _sessionmaker
    if _sessionmaker is None:
        _sessionmaker = async_sessionmaker(
            get_engine(), expire_on_commit=False, class_=AsyncSession
        )
    return _sessionmaker


async def get_db() -> AsyncIterator[AsyncSession]:
    """Request-scoped session. Commits on success, rolls back on any exception.

    Committing here rather than in each route means a handler that raises after
    a partial write cannot leave half a mutation behind.
    """
    async with get_sessionmaker()() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


async def reset_engine() -> None:
    """Dispose the engine — used between test cases."""
    global _engine, _sessionmaker
    if _engine is not None:
        await _engine.dispose()
    _engine = None
    _sessionmaker = None
