from __future__ import annotations

from fastapi import Depends, HTTPException, Path, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.auth import get_current_user
from app.db.models import Pot, User
from app.db.session import get_db


async def owned_pot(
    pot_id: str = Path(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Pot:
    """Load a pot, enforcing ownership.

    Every pot-scoped route depends on this rather than filtering inline. The
    most likely vulnerability in this API is an IDOR where one route forgets
    the `user_id` predicate; centralising it means a new route cannot omit the
    check without also omitting the pot.

    404 (not 403) for someone else's pot — a 403 would confirm the id exists.
    """
    result = await db.execute(
        select(Pot)
        .options(selectinload(Pot.species))
        .where(Pot.id == pot_id, Pot.user_id == user.id)
    )
    pot = result.scalar_one_or_none()
    if pot is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pot not found")
    return pot


async def owned_pot_with_device(pot: Pot = Depends(owned_pot)) -> Pot:
    if not pot.device_id:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "This pot has no paired device. Run setup to pair one.",
        )
    return pot
