#!/usr/bin/env bash
# Milestone 5: build the Flutter web SPA and (optionally) refresh the nginx
# service that hosts it (compose service `web`, port 8080).
#
#   ./scripts/build_web.sh          # build + restart the nginx container
#   ./scripts/build_web.sh --build-only
#
# API_BASE_URL must be the URL the BROWSER can reach — not a Docker-internal
# name. With the Compose stack published on the host, that is
# http://localhost:8000/api/v1; the API's default CORS allow-list already
# includes http://localhost:8080 (this service), so no proxy is involved.
set -euo pipefail

cd "$(dirname "$0")/../frontend"

API_BASE_URL="${API_BASE_URL:-http://localhost:8000/api/v1}"

echo "==> flutter build web (API_BASE_URL=${API_BASE_URL})"
flutter build web --release --dart-define="API_BASE_URL=${API_BASE_URL}"

echo "==> build complete: frontend/build/web"
if [[ "${1:-}" == "--build-only" ]]; then
  exit 0
fi

cd ..
echo "==> restarting the nginx SPA service"
docker compose up -d --force-recreate web
echo "==> web UI: http://localhost:8080  (deep links fall back to index.html)"
