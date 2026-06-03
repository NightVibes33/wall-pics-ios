#!/usr/bin/env sh
# Writes .env from GitHub Actions env vars and validates the Prism catalog URL.
set -eu

: > .env

if [ -n "${PRISM_ENV:-}" ]; then
  printf '%s\n' "$PRISM_ENV" | awk -F= '$1 !~ /^(GH_.*|GITHUB_.*|CATALOG_.*|SESSION_SECRET|APPLE_BUNDLE_ID|APP_STORE_CONNECT_.*|ASC_.*|APPLE_TEAM_ID|ALLOWED_MEDIA_HOSTS|MEDIA_CACHE_TTL_SECONDS|RC_.*|PEXELS_API_KEY|AI_CLIENT_TOKEN)$/ { print }' > .env
fi

if ! grep -q '^USER_STORE_API_BASE_URL=' .env && [ -n "${USER_STORE_API_BASE_URL:-}" ]; then
  printf '%s\n' "USER_STORE_API_BASE_URL=$USER_STORE_API_BASE_URL" >> .env
fi

if ! grep -q '^PRISM_CATALOG_BASE_URL=' .env && [ -n "${CATALOG_BASE_URL:-}" ]; then
  printf '%s\n' "PRISM_CATALOG_BASE_URL=$CATALOG_BASE_URL" >> .env
fi

if ! grep -q '^PRISM_MEDIA_BASE_URL=' .env && [ -n "${MEDIA_BASE_URL:-}" ]; then
  printf '%s\n' "PRISM_MEDIA_BASE_URL=$MEDIA_BASE_URL" >> .env
fi

if ! grep -q '^PRISM_CATALOG_BASE_URL=' .env; then
  API_BASE="$(awk -F= '$1 == "USER_STORE_API_BASE_URL" { sub(/^[^=]*=/, ""); print }' .env | tail -n 1)"
  if [ -n "$API_BASE" ]; then
    API_BASE="${API_BASE%/}"
    printf '%s\n' "PRISM_CATALOG_BASE_URL=$API_BASE/v1/catalog" >> .env
  fi
fi

CATALOG_BASE="$(awk -F= '$1 == "PRISM_CATALOG_BASE_URL" { sub(/^[^=]*=/, ""); print }' .env | tail -n 1)"
if [ -z "$CATALOG_BASE" ]; then
  echo "Missing PRISM_CATALOG_BASE_URL or USER_STORE_API_BASE_URL"
  exit 1
fi
CATALOG_BASE="${CATALOG_BASE%/}"

echo "Validating Prism catalog endpoint"
curl -fsSL --retry 3 --retry-delay 2 "$CATALOG_BASE/prism_index.json" | python3 -c 'import json,sys; json.load(sys.stdin)'
curl -fsSL --retry 3 --retry-delay 2 "$CATALOG_BASE/prism_category_lite.json" | python3 -c 'import json,sys; json.load(sys.stdin)'
curl -fsSL --retry 3 --retry-delay 2 "$CATALOG_BASE/prism_category_trees.json" | python3 -c 'import json,sys; json.load(sys.stdin)'
curl -fsSL --retry 3 --retry-delay 2 "$CATALOG_BASE/prism_category_ids.json" | python3 -c 'import json,sys; json.load(sys.stdin)'
curl -fsSL --retry 3 --retry-delay 2 "$CATALOG_BASE/prism_item_locations.json" | python3 -c 'import json,sys; json.load(sys.stdin)'
curl -fsSL --retry 3 --retry-delay 2 "$CATALOG_BASE/prism_regular_page_001.json" | python3 -c 'import json,sys; json.load(sys.stdin)'
