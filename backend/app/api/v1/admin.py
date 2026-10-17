"""Admin routes (assignment §7/§14; milestone agreement: due no later than
Milestone 5) — READ-ONLY operational overview.

GET /admin/orders  — paginated, cross-customer order listing (admin only).
GET /admin/summary — aggregate order/outbox/retry/quarantine counts.

Both endpoints are admin-gated by `require_admin`: unauthenticated callers
receive 401 and authenticated CUSTOMERS receive 403 (error envelope). There
are deliberately no mutating admin endpoints in this assignment.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Query

from app.api.deps import AdminDep, SessionDep
from app.schemas.admin import AdminOrderPage, AdminSummary
from app.schemas.common import MAX_PAGE_SIZE
from app.schemas.orders import ORDER_STATUS_FILTER
from app.services import admin_service

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/orders", response_model=AdminOrderPage)
async def list_all_orders(
    session: SessionDep,
    _admin: AdminDep,
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=MAX_PAGE_SIZE)] = 20,
    status: ORDER_STATUS_FILTER | None = None,
) -> AdminOrderPage:
    """Paginated cross-customer order listing (newest first); optional exact
    status filter. Read-only: no order mutation is exposed anywhere."""
    return await admin_service.list_orders(session, page=page, page_size=page_size, status=status)


@router.get("/summary", response_model=AdminSummary)
async def get_summary(session: SessionDep, _admin: AdminDep) -> AdminSummary:
    """Aggregate counts from authoritative PostgreSQL state: orders grouped
    by status, unpublished outbox rows, scheduled retry backlog and
    quarantine records (exact semantics documented in docs/api.md)."""
    return await admin_service.get_summary(session)
