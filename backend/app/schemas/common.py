"""Shared response building blocks: pagination and the error envelope type.

Pagination contract (assignment §7): page >= 1, page_size >= 1 with maximum
100 (larger values are rejected with 422), responses contain
{items, page, page_size, total} with stable ordering decided by the caller.
"""

from __future__ import annotations

from pydantic import BaseModel, Field

MAX_PAGE_SIZE = 100


class Page[T](BaseModel):
    items: list[T]
    page: int = Field(ge=1)
    page_size: int = Field(ge=1, le=MAX_PAGE_SIZE)
    total: int = Field(ge=0)
