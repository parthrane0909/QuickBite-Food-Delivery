"""Deterministically export the FastAPI OpenAPI contract.

Prints sorted JSON to stdout by default (reproducible output), or writes to
a file with --out. Requires a valid runtime configuration because the app
validates settings at import (run it via Compose or an exported .env):

    docker compose run --rm api python -m scripts.export_openapi > ../docs/openapi.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from app.main import create_app


def main() -> None:
    parser = argparse.ArgumentParser(description="Export QuickBite OpenAPI JSON.")
    parser.add_argument("--out", type=Path, default=None, help="Write to FILE instead of stdout.")
    args = parser.parse_args()

    app = create_app()
    document = json.dumps(app.openapi(), sort_keys=True, indent=2) + "\n"

    if args.out is None:
        sys.stdout.write(document)
        return
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(document, encoding="utf-8")
    print(f"OpenAPI contract written to {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
