"""Versioned API route aggregation.

Routes are mounted under /api/v1 without duplicated prefixes; every handler
stays thin and delegates to a service.
"""

from fastapi import APIRouter

from app.api.v1 import auth, restaurants

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(restaurants.router)
# Milestone 2 adds: orders (checkout + reads) and admin (read-only overview).
