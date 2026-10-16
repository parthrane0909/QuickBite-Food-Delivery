"""Versioned API route aggregation.

Routes are mounted under /api/v1 without duplicated prefixes; every handler
stays thin and delegates to a service.
"""

from fastapi import APIRouter

from app.api.v1 import auth, orders, restaurants

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(restaurants.router)
api_router.include_router(orders.router)
# Later milestones add: notifications feed (M3) and admin overview (M6).
