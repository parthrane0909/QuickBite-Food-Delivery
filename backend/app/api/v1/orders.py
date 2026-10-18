"""Order routes (assignment §7): idempotent checkout and owner-scoped reads.

POST /orders  — customer only, Idempotency-Key REQUIRED, 202 + Location.
The handler is thin: all validation, pricing, idempotency and atomicity live
in checkout_service; all authorization decisions live in the query service.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Header, Query
from fastapi.responses import JSONResponse

from app.api.deps import CurrentUserDep, RequestIdDep, SessionDep, ShopperDep
from app.core.errors import IdempotencyKeyMissingError, ValidationFailedError
from app.schemas.common import MAX_PAGE_SIZE
from app.schemas.orders import (
    IDEMPOTENCY_KEY_MAX_LENGTH,
    ORDER_STATUS_FILTER,
    CheckoutRequest,
    NotificationPage,
    OrderAccepted,
    OrderDetail,
    OrderHistoryPage,
    OrderPage,
)
from app.services import checkout_service, order_query_service

router = APIRouter(tags=["orders"])

IdempotencyKeyHeader = Annotated[str | None, Header(alias="Idempotency-Key")]

_ACCEPTANCE_HEADERS = {
    "Location": {
        "description": "Absolute path of the created (or originally created) order.",
        "schema": {"type": "string"},
    }
}


@router.post(
    "/orders",
    status_code=202,
    response_model=OrderAccepted,
    responses={
        202: {
            "description": "Order accepted for asynchronous processing.",
            "headers": _ACCEPTANCE_HEADERS,
        },
        409: {"description": "Idempotency-Key reused with a different payload."},
    },
)
async def checkout_order(
    payload: CheckoutRequest,
    session: SessionDep,
    user: ShopperDep,
    request_id: RequestIdDep,
    idempotency_key: IdempotencyKeyHeader = None,
) -> JSONResponse:
    """Validate, price server-side and atomically persist the order, its
    initial history, the idempotency response and the `order.created` outbox
    event — or fail without partial writes. Never publishes to RabbitMQ."""
    if idempotency_key is None or not idempotency_key.strip():
        raise IdempotencyKeyMissingError(
            "The Idempotency-Key header is required for checkout.",
            details={"header": "Idempotency-Key"},
        )
    key = idempotency_key.strip()
    if len(key) > IDEMPOTENCY_KEY_MAX_LENGTH:
        raise ValidationFailedError(
            f"Idempotency-Key must be at most {IDEMPOTENCY_KEY_MAX_LENGTH} characters.",
            details={"reason": "idempotency_key_too_long"},
        )

    result = await checkout_service.create_order(
        session,
        customer_id=user.id,
        idempotency_key=key,
        checkout=payload,
        request_id=request_id,
    )
    # Replay returns the STORED original body/Location verbatim (§7).
    return JSONResponse(status_code=202, content=result.body, headers={"Location": result.location})


@router.get("/orders", response_model=OrderPage)
async def list_my_orders(
    session: SessionDep,
    user: ShopperDep,
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=MAX_PAGE_SIZE)] = 20,
    status: ORDER_STATUS_FILTER | None = None,
) -> OrderPage:
    """Paginated current-customer orders; optional exact-status filter."""
    return await order_query_service.list_orders(
        session, user=user, page=page, page_size=page_size, status=status
    )


@router.get("/orders/{order_id}", response_model=OrderDetail)
async def get_order(
    order_id: str,
    session: SessionDep,
    user: CurrentUserDep,
) -> OrderDetail:
    """Current state, items, totals, failure details, version, timestamps —
    owner or admin; other customers receive 404."""
    return await order_query_service.get_order_detail(session, user=user, order_id=order_id)


@router.get("/orders/{order_id}/history", response_model=OrderHistoryPage)
async def get_order_history(
    order_id: str,
    session: SessionDep,
    user: CurrentUserDep,
) -> OrderHistoryPage:
    """Append-only, version-ordered state-transition timeline (owner or admin)."""
    return await order_query_service.get_order_history(session, user=user, order_id=order_id)


@router.get("/orders/{order_id}/notifications", response_model=NotificationPage)
async def get_order_notifications(
    order_id: str,
    session: SessionDep,
    user: CurrentUserDep,
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=MAX_PAGE_SIZE)] = 20,
) -> NotificationPage:
    """Persisted in-app notification feed for one order (owner or admin),
    chronological order with cursorless pagination."""
    return await order_query_service.get_notifications(
        session, user=user, order_id=order_id, page=page, page_size=page_size
    )
