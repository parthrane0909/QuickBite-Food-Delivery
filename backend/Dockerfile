# syntax=docker/dockerfile:1
# QuickBite backend image — ONE pinned image reused by api, the four workers,
# migrate/seed one-shots and (from Milestone 3) the outbox dispatcher and
# retry scheduler, each with a different command. Multi-process by design;
# never scale this image as a single mixed-responsibility container.

FROM python:3.12.15-slim-bookworm

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

# Pin uv to the exact version verified in docs/requirements-matrix.md.
RUN pip install --no-cache-dir uv==0.13.1

WORKDIR /srv/quickbite

# Dependency layer, cached unless the manifest or lockfile changes.
# --frozen guarantees the committed uv.lock is used exactly (no drift).
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen

# Application source.
COPY alembic.ini ./
COPY app ./app
COPY workers ./workers
COPY scripts ./scripts
COPY migrations ./migrations
COPY tests ./tests

# Non-root runtime user; own the workdir so tests/tools may write caches.
RUN useradd --create-home --uid 10001 quickbite \
    && chown -R quickbite:quickbite /srv/quickbite
USER quickbite

ENV PATH="/srv/quickbite/.venv/bin:$PATH"

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
